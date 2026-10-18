import AppKit
import Darwin
import Foundation
import IOKit

@_silgen_name("responsibility_get_pid_responsible_for_pid")
private func responsibility_get_pid_responsible_for_pid(_ pid: pid_t) -> pid_t

/// Per-process CPU, memory, disk, network and GPU usage, folded into apps.
///
/// CPU and disk come from proc_pid_rusage deltas (no subprocess). Processes owned by other
/// users can't be read that way, so while a window or panel is open `ps` fills them in.
/// Network (nettop) and GPU (IORegistry) are only sampled while something shows them.
final class ProcessReader {
    struct Request {
        var includeOtherUsers = false
        var network = false
        var gpu = false
        var limit = 8
    }

    private struct Identity {
        var name: String
        var groupID: String
        var groupName: String
        var bundlePath: String?
        var executablePath: String?
        var isSystem: Bool
    }

    private struct Counters { var cpu: UInt64; var read: UInt64; var write: UInt64 }

    private var previous: [pid_t: Counters] = [:]
    private var previousDate: Date?
    private var identities: [pid_t: Identity] = [:]
    private var netPrevious: [pid_t: (UInt64, UInt64)] = [:]
    private var netDate: Date?
    private var gpuPrevious: [pid_t: UInt64] = [:]
    private var gpuDate: Date?
    private let myUID = getuid()
    private let timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    private(set) var selfUsage: (cpu: Double, memory: UInt64) = (0, 0)

    func read(_ request: Request) -> (ProcessSnapshot, [PeakProcess]) {
        let now = Date()
        let dt = previousDate.map { now.timeIntervalSince($0) } ?? 0
        previousDate = now

        var rows: [pid_t: ProcessUsage] = [:]
        var current: [pid_t: Counters] = [:]
        var unreadable: [pid_t] = []
        let pids = Self.allPIDs()

        for pid in pids where pid > 0 {
            var info = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            } == 0
            guard ok else { unreadable.append(pid); continue }
            let cpuTime = UInt64(Double(info.ri_user_time + info.ri_system_time) * timebase)
            let counters = Counters(cpu: cpuTime, read: info.ri_diskio_bytesread, write: info.ri_diskio_byteswritten)
            current[pid] = counters

            var row = usage(for: pid)
            row.memory = info.ri_phys_footprint
            if let p = previous[pid], dt > 0 {
                row.cpu = Double(counters.cpu &- p.cpu) / (dt * 1e9) * 100
                row.diskRead = Double(counters.read >= p.read ? counters.read - p.read : 0) / dt
                row.diskWrite = Double(counters.write >= p.write ? counters.write - p.write : 0) / dt
            }
            rows[pid] = row
        }
        previous = current
        let unreadableSet = Set(unreadable)
        identities = identities.filter { current[$0.key] != nil || unreadableSet.contains($0.key) }

        if request.includeOtherUsers, !unreadable.isEmpty {
            for (pid, cpu, rss) in Self.psSample() where rows[pid] == nil {
                var row = usage(for: pid)
                row.cpu = cpu
                row.memory = rss
                rows[pid] = row
            }
        }

        if request.network {
            for (pid, down, up) in networkRates(now: now) {
                if rows[pid] == nil { rows[pid] = usage(for: pid) }
                rows[pid]?.netDown = down
                rows[pid]?.netUp = up
            }
        } else {
            netPrevious = [:]
            netDate = nil
        }

        if request.gpu {
            for (pid, share) in gpuShares(now: now) {
                if rows[pid] == nil { rows[pid] = usage(for: pid) }
                rows[pid]?.gpu = share
            }
        } else {
            gpuPrevious = [:]
            gpuDate = nil
        }

        // Raw per-process top CPU, used for the peak lookback (before folding into apps).
        if let me = rows[getpid()] { selfUsage = (me.cpu, me.memory) }

        let busiest: [ProcessUsage] = rows.values.sorted { $0.cpu > $1.cpu }
        var peaks: [PeakProcess] = []
        for row in busiest.prefix(3) where row.cpu >= 1 {
            peaks.append(PeakProcess(name: identities[row.pid]?.name ?? row.name, cpu: row.cpu))
        }

        let grouped = group(Array(rows.values))
        var snapshot = ProcessSnapshot()
        let n = request.limit
        snapshot.byCPU = Array(grouped.sorted { $0.cpu > $1.cpu }.prefix(n))
        snapshot.byMemory = Array(grouped.sorted { $0.memory > $1.memory }.prefix(n))
        snapshot.byDisk = Array(grouped.filter { $0.diskTotal > 0 }.sorted { $0.diskTotal > $1.diskTotal }.prefix(n))
        if request.network {
            snapshot.byNetwork = Array(grouped.filter { $0.netTotal > 0 }.sorted { $0.netTotal > $1.netTotal }.prefix(n))
        }
        if request.gpu {
            snapshot.byGPU = Array(grouped.filter { $0.gpu > 0.05 }.sorted { $0.gpu > $1.gpu }.prefix(n))
        }
        let load = Self.loadInfo()
        snapshot.processCount = load?.tasks ?? pids.count
        snapshot.threadCount = load?.threads ?? 0
        return (snapshot, peaks)
    }

    // MARK: - Identity and grouping

    private func usage(for pid: pid_t) -> ProcessUsage {
        let id = identity(for: pid)
        return ProcessUsage(id: id.groupID, pid: pid, pids: [pid], name: id.groupName,
                            bundlePath: id.bundlePath, executablePath: id.executablePath, isSystem: id.isSystem)
    }

    private func identity(for pid: pid_t) -> Identity {
        if let cached = identities[pid] { return cached }
        let path = Self.path(of: pid)
        var name = Self.name(of: pid) ?? path.map { ($0 as NSString).lastPathComponent } ?? "\(pid)"
        var uid: uid_t = 0
        var bsd = proc_bsdshortinfo()
        if proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdshortinfo>.size)) > 0 {
            uid = bsd.pbsi_uid
        } else {
            uid = 0
        }
        let isSystem = uid != myUID || pid < 100

        var bundle: String?
        if let path {
            bundle = Self.outerAppBundle(path)
            if bundle == nil, path.contains("/WebKit.framework/") || path.contains(".xpc/") {
                let owner = responsibility_get_pid_responsible_for_pid(pid)
                if owner > 0, owner != pid, let ownerPath = Self.path(of: owner) {
                    bundle = Self.outerAppBundle(ownerPath)
                }
            }
        }

        let identity: Identity
        if let bundle {
            let display = FileManager.default.displayName(atPath: bundle).replacingOccurrences(of: ".app", with: "")
            if path.map({ ($0 as NSString).deletingLastPathComponent.hasSuffix("\(bundle)/Contents/MacOS") }) ?? false {
                name = display
            }
            identity = Identity(name: name, groupID: bundle, groupName: display, bundlePath: bundle, executablePath: path, isSystem: isSystem && !bundle.hasPrefix("/Applications"))
        } else {
            identity = Identity(name: name, groupID: "pid:\(pid)", groupName: name, bundlePath: nil, executablePath: path, isSystem: isSystem)
        }
        identities[pid] = identity
        return identity
    }

    private func group(_ rows: [ProcessUsage]) -> [ProcessUsage] {
        var groups: [String: ProcessUsage] = [:]
        for row in rows {
            if var g = groups[row.id] {
                g.cpu += row.cpu
                g.memory += row.memory
                g.diskRead += row.diskRead
                g.diskWrite += row.diskWrite
                g.netDown += row.netDown
                g.netUp += row.netUp
                g.gpu += row.gpu
                g.pids.append(row.pid)
                // Prefer the app's main executable as the representative pid.
                if let bundle = row.bundlePath, let exe = row.executablePath,
                   (exe as NSString).deletingLastPathComponent.hasSuffix("\(bundle)/Contents/MacOS") {
                    g.pid = row.pid
                    g.executablePath = exe
                }
                groups[row.id] = g
            } else {
                groups[row.id] = row
            }
        }
        return Array(groups.values)
    }

    /// Outermost `.app` bundle containing `path`, e.g. Chrome helpers fold into Google Chrome.app.
    /// Command-line tools that merely live inside an app (Xcode's swift-frontend) stay separate.
    private static func outerAppBundle(_ path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        let bundle = String(path[..<range.lowerBound]) + ".app"
        let rest = String(path[range.upperBound...])
        let isMain = rest.hasPrefix("Contents/MacOS/")
        let isNestedBundle = rest.contains(".app/") || rest.contains(".xpc/") || rest.contains(".appex/")
        return isMain || isNestedBundle ? bundle : nil
    }

    private static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return n > 0 ? String(cString: buffer) : nil
    }

    private static func name(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        let n = proc_name(pid, &buffer, UInt32(buffer.count))
        return n > 0 ? String(cString: buffer) : nil
    }

    /// System-wide task and thread counts, as `top` reports them.
    private static func loadInfo() -> (tasks: Int, threads: Int)? {
        var pset = processor_set_name_t()
        guard processor_set_default(mach_host_self(), &pset) == KERN_SUCCESS else { return nil }
        var info = processor_set_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<processor_set_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                processor_set_statistics(pset, PROCESSOR_SET_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (Int(info.task_count), Int(info.thread_count))
    }

    private static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Array(pids.prefix(Int(max(0, n))))
    }

    // MARK: - Subprocess-backed sources

    private static func run(_ tool: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private static func psSample() -> [(pid_t, Double, UInt64)] {
        run("/bin/ps", ["-Ao", "pid=,pcpu=,rss="]).split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3, let pid = pid_t(parts[0]), let cpu = Double(parts[1]), let rss = UInt64(parts[2]) else { return nil }
            return (pid, cpu, rss * 1024)
        }
    }

    private func networkRates(now: Date) -> [(pid_t, Double, Double)] {
        let output = Self.run("/usr/bin/nettop", ["-P", "-L", "1", "-x", "-n", "-J", "bytes_in,bytes_out"])
        var totals: [pid_t: (UInt64, UInt64)] = [:]
        for line in output.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cols.count >= 3, let dot = cols[0].lastIndex(of: "."),
                  let pid = pid_t(cols[0][cols[0].index(after: dot)...]),
                  let rx = UInt64(cols[1]), let tx = UInt64(cols[2]) else { continue }
            totals[pid] = (rx, tx)
        }
        defer { netPrevious = totals; netDate = now }
        guard let last = netDate else { return [] }
        let dt = now.timeIntervalSince(last)
        guard dt > 0 else { return [] }
        return totals.compactMap { pid, value in
            guard let p = netPrevious[pid] else { return nil }
            let down = Double(value.0 >= p.0 ? value.0 - p.0 : 0) / dt
            let up = Double(value.1 >= p.1 ? value.1 - p.1 : 0) / dt
            return down + up > 0 ? (pid, down, up) : nil
        }
    }

    /// GPU time per process from the accelerator's user clients (`AppUsage.accumulatedGPUTime`, ns).
    private func gpuShares(now: Date) -> [(pid_t, Double)] {
        var totals: [pid_t: UInt64] = [:]
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == kIOReturnSuccess else { return [] }
        defer { IOObjectRelease(iterator) }
        while case let accel = IOIteratorNext(iterator), accel != 0 {
            defer { IOObjectRelease(accel) }
            var children: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(accel, kIOServicePlane, &children) == kIOReturnSuccess else { continue }
            defer { IOObjectRelease(children) }
            while case let client = IOIteratorNext(children), client != 0 {
                defer { IOObjectRelease(client) }
                guard let creator = IORegistryEntryCreateCFProperty(client, "IOUserClientCreator" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
                      let usage = IORegistryEntryCreateCFProperty(client, "AppUsage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [[String: Any]],
                      let pidPart = creator.split(separator: ",").first?.split(separator: " ").last,
                      let pid = pid_t(pidPart) else { continue }
                let time = usage.reduce(UInt64(0)) { $0 + ((($1["accumulatedGPUTime"] as? NSNumber)?.uint64Value) ?? 0) }
                totals[pid, default: 0] += time
            }
        }
        defer { gpuPrevious = totals; gpuDate = now }
        guard let last = gpuDate else { return [] }
        let dt = now.timeIntervalSince(last)
        guard dt > 0 else { return [] }
        return totals.compactMap { pid, value in
            guard let p = gpuPrevious[pid], value > p else { return nil }
            return (pid, min(100, Double(value - p) / (dt * 1e9) * 100))
        }
    }
}
