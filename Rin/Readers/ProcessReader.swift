import AppKit
import Darwin
import Foundation
import IOKit

@_silgen_name("responsibility_get_pid_responsible_for_pid")
private func responsibility_get_pid_responsible_for_pid(_ pid: pid_t) -> pid_t

/// Per-process CPU, memory, disk, network and GPU usage, folded into apps.
///
/// CPU, disk and energy come from proc_pid_rusage deltas (no subprocess). Processes owned by other
/// users can't be read that way, so while a window or panel is open `ps` fills them in, and `top`
/// corrects their memory while a list of it is on screen, and adds threads and compressed memory
/// to the full list.
/// Network (nettop) is read every few seconds while a list of it is on screen and every 30 s
/// otherwise; GPU (IORegistry) only while something shows it.
final class ProcessReader {
    struct Request {
        var includeOtherUsers = false
        /// Track per-app traffic: a baseline nettop read every `networkBaseline` seconds...
        var network = false
        /// ...or one every read, while a list of it is on screen.
        var networkLive = false
        var gpu = false
        /// A list of memory is on screen: read what other users' processes really hold.
        var footprints = false
        var limit = 8
        /// Return every group (the Processes page), not just the top few per metric.
        var full = false
    }

    private struct Identity {
        var name: String
        var groupID: String
        var groupName: String
        var bundlePath: String?
        var executablePath: String?
        var isSystem: Bool
        var uid: uid_t
    }

    private struct Counters { var cpu: UInt64; var read: UInt64; var write: UInt64; var energy: UInt64 }
    private struct Moved { var at: Date; var read: Double; var write: Double; var down: Double; var up: Double }

    private var previous: [pid_t: Counters] = [:]
    private var previousDate: Date?
    private var identities: [pid_t: Identity] = [:]
    private var netPrevious: [pid_t: (UInt64, UInt64)] = [:]
    private var netDate: Date?
    /// When each app last moved data, so a list keeps apps that just paused instead of
    /// shrinking every time one goes quiet for a few seconds.
    private var netLastActive: [String: Date] = [:]
    private static let netRecent: TimeInterval = 60
    private var gpuPrevious: [pid_t: UInt64] = [:]
    private var gpuDate: Date?
    private let footprints = FootprintProbe()
    /// What each app moved lately, while the full list is read.
    private var moved: [String: [Moved]] = [:]
    private var movedSince: Date?
    private static let movedWindow: TimeInterval = 60
    /// What each app's CPU has been lately, while the full list is read.
    private var cpuLately: [String: [(at: Date, cpu: Double)]] = [:]
    private static let cpuWindow: TimeInterval = 30
    private let myUID = getuid()
    /// Seconds between background nettop reads that keep per-app traffic ready to show.
    private static let networkBaseline: TimeInterval = 30
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
            var info = rusage_info_v6()
            let ok = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
            } == 0
            guard ok else { unreadable.append(pid); continue }
            let cpuTime = UInt64(Double(info.ri_user_time + info.ri_system_time) * timebase)
            let counters = Counters(cpu: cpuTime, read: info.ri_diskio_bytesread, write: info.ri_diskio_byteswritten,
                                    energy: info.ri_energy_nj)
            current[pid] = counters

            var row = usage(for: pid)
            row.memory = info.ri_phys_footprint
            row.cpuTime = Double(cpuTime) / 1e9
            row.totalRead = info.ri_diskio_bytesread
            row.totalWritten = info.ri_diskio_byteswritten
            row.energyUsed = Double(info.ri_energy_nj) / 1e9 / 3600
            if let p = previous[pid], dt > 0 {
                row.cpu = Double(counters.cpu &- p.cpu) / (dt * 1e9) * 100
                row.diskRead = Double(counters.read >= p.read ? counters.read - p.read : 0) / dt
                row.diskWrite = Double(counters.write >= p.write ? counters.write - p.write : 0) / dt
                // CPU energy, in nanojoules.
                row.energy = Double(counters.energy >= p.energy ? counters.energy - p.energy : 0) / dt / 1e9
            }
            rows[pid] = row
        }
        previous = current
        let unreadableSet = Set(unreadable)
        identities = identities.filter { current[$0.key] != nil || unreadableSet.contains($0.key) }

        if request.footprints { footprints.tick() } else { footprints.reset() }
        let held = request.footprints ? footprints.results() : [:]
        if request.includeOtherUsers, !unreadable.isEmpty {
            for (pid, cpu, rss) in Self.psSample() where rows[pid] == nil {
                var row = usage(for: pid)
                row.cpu = cpu
                row.memory = held[pid]?.memory ?? rss
                rows[pid] = row
            }
        }
        if request.full {
            for (pid, h) in held {
                guard var row = rows[pid] else { continue }
                row.threads = h.threads
                row.compressed = h.compressed
                row.cpuTime = max(row.cpuTime, h.cpuTime)
                rows[pid] = row
            }
        }

        var netMoved: [String: (down: Double, up: Double)] = [:]
        var netSpan: TimeInterval = 0
        if request.network {
            let due = request.networkLive || netDate.map { now.timeIntervalSince($0) >= Self.networkBaseline } ?? true
            if due {
                netSpan = netDate.map { now.timeIntervalSince($0) } ?? 0
                let rates = networkRates(now: now)
                if request.networkLive {
                    for (pid, down, up) in rates {
                        if rows[pid] == nil { rows[pid] = usage(for: pid) }
                        rows[pid]?.netDown = down
                        rows[pid]?.netUp = up
                    }
                }
                if request.full {
                    for (pid, down, up) in rates {
                        let id = identity(for: pid).groupID
                        netMoved[id, default: (0, 0)].down += down * netSpan
                        netMoved[id, default: (0, 0)].up += up * netSpan
                    }
                }
            }
            if request.full {
                for (pid, total) in netPrevious {
                    rows[pid]?.totalDown = total.0
                    rows[pid]?.totalUp = total.1
                }
            }
        } else {
            netPrevious = [:]
            netDate = nil
            netLastActive = [:]
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

        var grouped = group(Array(rows.values))
        if request.full {
            grouped = withRecent(grouped, network: netMoved, since: now.addingTimeInterval(-max(dt, netSpan, 1)), dt: dt, now: now)
        } else {
            moved = [:]
            movedSince = nil
            cpuLately = [:]
        }
        var snapshot = ProcessSnapshot()
        snapshot.date = now
        let n = request.limit
        snapshot.byCPU = Array(grouped.sorted { $0.cpu > $1.cpu }.prefix(n))
        snapshot.byMemory = Array(grouped.sorted { $0.memory > $1.memory }.prefix(n))
        snapshot.byDisk = Array(grouped.filter { $0.diskTotal > 0 }.sorted { $0.diskTotal > $1.diskTotal }.prefix(n))
        if request.networkLive {
            for g in grouped where g.netTotal > 0 { netLastActive[g.id] = now }
            netLastActive = netLastActive.filter { now.timeIntervalSince($0.value) < Self.netRecent }
            // Busiest first; apps that moved data within the last minute follow, most recent first.
            snapshot.byNetwork = Array(grouped.filter { netLastActive[$0.id] != nil }.sorted {
                if $0.netTotal != $1.netTotal { return $0.netTotal > $1.netTotal }
                return (netLastActive[$0.id] ?? .distantPast) > (netLastActive[$1.id] ?? .distantPast)
            }.prefix(n))
        }
        if request.gpu {
            snapshot.byGPU = Array(grouped.filter { $0.gpu > 0.05 }.sorted { $0.gpu > $1.gpu }.prefix(n))
        }
        snapshot.byEnergy = Array(grouped.filter { $0.energy > 0.005 }.sorted { $0.energy > $1.energy }.prefix(n))
        if request.full { snapshot.all = grouped }
        let load = Self.loadInfo()
        snapshot.processCount = load?.tasks ?? pids.count
        snapshot.threadCount = load?.threads ?? 0
        return (snapshot, peaks)
    }

    /// Adds this read to what each app moved lately, and gives each its last minute's average.
    private func withRecent(_ groups: [ProcessUsage], network: [String: (down: Double, up: Double)], since: Date, dt: TimeInterval, now: Date) -> [ProcessUsage] {
        // The first read's amounts go back further than this read, to the one before it.
        let start = movedSince ?? since
        movedSince = start
        for g in groups {
            let entry = Moved(at: now, read: g.diskRead * dt, write: g.diskWrite * dt, down: network[g.id]?.down ?? 0, up: network[g.id]?.up ?? 0)
            if entry.read + entry.write + entry.down + entry.up > 0 { moved[g.id, default: []].append(entry) }
        }
        let cutoff = now.addingTimeInterval(-Self.movedWindow)
        moved = moved.compactMapValues { entries in
            let kept = entries.filter { $0.at > cutoff }
            return kept.isEmpty ? nil : kept
        }
        let span = max(min(now.timeIntervalSince(start), Self.movedWindow), 1)
        let cpuCutoff = now.addingTimeInterval(-Self.cpuWindow)
        var cpuNow: [String: [(at: Date, cpu: Double)]] = [:]
        cpuNow.reserveCapacity(groups.count)
        let result = groups.map { group in
            var g = group
            var lately = cpuLately[group.id, default: []].filter { $0.at > cpuCutoff }
            lately.append((now, group.cpu))
            cpuNow[group.id] = lately
            g.recentCPU = lately.reduce(0) { $0 + $1.cpu } / Double(lately.count)
            guard let entries = moved[group.id] else { return g }
            g.recentRead = entries.reduce(0) { $0 + $1.read } / span
            g.recentWrite = entries.reduce(0) { $0 + $1.write } / span
            g.recentDown = entries.reduce(0) { $0 + $1.down } / span
            g.recentUp = entries.reduce(0) { $0 + $1.up } / span
            return g
        }
        cpuLately = cpuNow
        return result
    }

    // MARK: - Identity and grouping

    private func usage(for pid: pid_t) -> ProcessUsage {
        let id = identity(for: pid)
        var row = ProcessUsage(id: id.groupID, pid: pid, pids: [pid], name: id.groupName,
                               bundlePath: id.bundlePath, executablePath: id.executablePath, isSystem: id.isSystem)
        row.uid = id.uid
        return row
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
            identity = Identity(name: name, groupID: bundle, groupName: display, bundlePath: bundle, executablePath: path,
                                isSystem: isSystem && !bundle.hasPrefix("/Applications"), uid: uid)
        } else {
            identity = Identity(name: name, groupID: "pid:\(pid)", groupName: name, bundlePath: nil, executablePath: path,
                                isSystem: isSystem, uid: uid)
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
                g.energy += row.energy
                g.cpuTime += row.cpuTime
                g.totalRead += row.totalRead
                g.totalWritten += row.totalWritten
                g.totalDown += row.totalDown
                g.totalUp += row.totalUp
                g.energyUsed += row.energyUsed
                g.threads += row.threads
                g.compressed += row.compressed
                g.pids.append(row.pid)
                // Prefer the app's main executable as the representative pid.
                if let bundle = row.bundlePath, let exe = row.executablePath,
                   (exe as NSString).deletingLastPathComponent.hasSuffix("\(bundle)/Contents/MacOS") {
                    g.pid = row.pid
                    g.executablePath = exe
                    g.uid = row.uid
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

    fileprivate static func run(_ tool: String, _ args: [String]) -> String {
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

/// What `top` knows about every process, at most every 30 seconds. It runs as root, so it has the
/// footprint of other users' processes, where `ps` only has their resident size, which counts shared
/// memory and leaves out what's compressed; Activity Monitor reports the footprint too. One read
/// costs about 0.4 s of CPU, so it runs on its own queue and only while a list that needs it is on screen.
private final class FootprintProbe {
    struct Held {
        var memory: UInt64
        var threads: Int
        var compressed: UInt64
        var cpuTime: Double
    }

    private static let interval: TimeInterval = 30
    private let queue = DispatchQueue(label: "rin.footprints", qos: .utility)
    private let lock = NSLock()
    private var lastStart = Date.distantPast
    private var latest: [pid_t: Held] = [:]

    func tick() {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(lastStart) >= Self.interval else { return }
        lastStart = now
        queue.async { [self] in
            let read = Self.parse(ProcessReader.run("/usr/bin/top", ["-l", "1", "-F", "-R", "-stats", "pid,mem,th,cmprs,time"]))
            lock.lock()
            latest = read
            lock.unlock()
        }
    }

    func results() -> [pid_t: Held] {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        lastStart = .distantPast
        latest = [:]
    }

    /// The rows under top's "PID MEM #TH CMPRS TIME" header.
    private static func parse(_ output: String) -> [pid_t: Held] {
        var result: [pid_t: Held] = [:]
        var inRows = false
        for line in output.split(separator: "\n") {
            let columns = line.split(separator: " ")
            guard inRows else {
                inRows = columns.first == "PID"
                continue
            }
            guard columns.count == 5, let pid = pid_t(columns[0]), let memory = bytes(columns[1]) else { continue }
            result[pid] = Held(memory: memory, threads: threads(columns[2]), compressed: bytes(columns[3]) ?? 0, cpuTime: seconds(columns[4]))
        }
        return result
    }

    /// "6304K", "942M", in powers of 1024; top may mark a figure as rising or falling with + or -.
    private static func bytes(_ text: Substring) -> UInt64? {
        let figure = text.trimmingCharacters(in: marks)
        guard let unit = figure.last, let number = Double(figure.dropLast()) else { return nil }
        switch unit {
        case "B": return UInt64(number)
        case "K": return UInt64(number * 1024)
        case "M": return UInt64(number * 1_048_576)
        case "G": return UInt64(number * 1_073_741_824)
        case "T": return UInt64(number * 1_099_511_627_776)
        default: return nil
        }
    }

    /// "14", or "767/10" with how many of them are running.
    private static func threads(_ text: Substring) -> Int {
        Int(text.prefix { $0 != "/" }.trimmingCharacters(in: marks)) ?? 0
    }

    /// "05:47.56", "1:02:30".
    private static func seconds(_ text: Substring) -> Double {
        text.trimmingCharacters(in: marks).split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }

    private static let marks = CharacterSet(charactersIn: "+-")
}
