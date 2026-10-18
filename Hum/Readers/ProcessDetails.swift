import Darwin
import Foundation

/// The inspector's extra facts about one process group, read on demand for the selected row.
struct ProcessDetails {
    var user: String?
    var threads: Int?
    var started: Date?
    var parent: (name: String, pid: pid_t)?
    /// Names of the representative process's children.
    var children: [String] = []

    static func read(_ p: ProcessUsage) -> ProcessDetails {
        var d = ProcessDetails()
        d.user = getpwuid(p.uid).flatMap { String(cString: $0.pointee.pw_name) }

        var threads = 0
        var readable = false
        for pid in Set(p.pids + [p.pid]) {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size {
                threads += Int(info.pti_threadnum)
                readable = true
            }
        }
        d.threads = readable ? threads : nil

        if let k = kinfo(p.pid) {
            let start = k.kp_proc.p_starttime
            if start.tv_sec > 0 { d.started = Date(timeIntervalSince1970: TimeInterval(start.tv_sec)) }
            let ppid = k.kp_eproc.e_ppid
            if ppid > 0 { d.parent = (name(of: ppid) ?? "\(ppid)", ppid) }
        }

        let count = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(p.pid), nil, 0)
        if count > 0 {
            var pids = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.size + 16)
            let bytes = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(p.pid), &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
            let n = max(0, Int(bytes) / MemoryLayout<pid_t>.size)
            d.children = pids.prefix(n).filter { $0 > 0 }.compactMap { name(of: $0) }
        }
        return d
    }

    private static func kinfo(_ pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    private static func name(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 { return String(cString: buffer) }
        guard var k = kinfo(pid) else { return nil }
        return withUnsafeBytes(of: &k.kp_proc.p_comm) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
    }
}
