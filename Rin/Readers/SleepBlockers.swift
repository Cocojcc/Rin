import AppKit
import IOKit.pwr_mgt

@_silgen_name("responsibility_get_pid_responsible_for_pid")
private func responsibilityPID(_ pid: pid_t) -> pid_t

/// Who is holding the Mac awake right now, from the power assertions (`pmset -g assertions`).
struct SleepBlocker: Identifiable {
    enum Owner {
        case app(NSRunningApplication)
        case process(name: String, path: String?)
        case system
    }

    var id: String
    var owner: Owner
    /// The assertion's name ("Playing audio", "Handoff"), translated where it is a known one.
    var reason: String
    /// Holds the display on (otherwise only the system).
    var display: Bool
    var since: Date

    private static let systemSleepTypes: Set<String> = ["PreventUserIdleSystemSleep", "PreventSystemSleep"]
    private static let displaySleepTypes: Set<String> = ["PreventUserIdleDisplaySleep"]

    static func read() -> [SleepBlocker] {
        var out: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&out) == kIOReturnSuccess,
              let byPID = out?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        let me = getpid()
        var blockers: [String: SleepBlocker] = [:]
        for (pidNumber, assertions) in byPID {
            let pid = pidNumber.int32Value
            guard pid != me else { continue }
            for a in assertions {
                let type = (a["AssertionTrueType"] as? String) ?? (a["AssertType"] as? String) ?? ""
                let display = displaySleepTypes.contains(type)
                guard display || systemSleepTypes.contains(type) else { continue }
                let processName = a["Process Name"] as? String ?? ""
                // powerd's "prevent sleep while the display is on" follows from the display being on.
                if processName == "powerd" { continue }
                let behalf = (a["AssertionOnBehalfOfPID"] as? NSNumber)?.int32Value
                let owner = Self.owner(pid: behalf ?? pid, fallbackName: processName)
                let key: String
                switch owner {
                case .app(let app): key = "app:\(app.processIdentifier)"
                case .process(let name, _): key = "proc:\(name)"
                case .system: key = "system:\(pid)"
                }
                let since = a["AssertStartWhen"] as? Date ?? Date()
                let reason = Self.reason(a["AssertName"] as? String ?? "")
                if var b = blockers[key] {
                    if display && !b.display { b.display = true; b.reason = reason }
                    b.since = min(b.since, since)
                    blockers[key] = b
                } else {
                    blockers[key] = SleepBlocker(id: key, owner: owner, reason: reason, display: display, since: since)
                }
            }
        }
        // Apps first, then other processes, then macOS; longest-held first within each.
        return blockers.values.sorted {
            let ra = $0.rank, rb = $1.rank
            return ra != rb ? ra < rb : $0.since < $1.since
        }
    }

    private var rank: Int {
        switch owner {
        case .app: return 0
        case .process: return 1
        case .system: return 2
        }
    }

    private static func owner(pid: pid_t, fallbackName: String) -> Owner {
        for candidate in [pid, responsibilityPID(pid)] where candidate > 0 {
            if let app = NSRunningApplication(processIdentifier: candidate), app.bundleURL != nil,
               app.activationPolicy != .prohibited {
                return .app(app)
            }
        }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let path = proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : nil
        let systemRoots = ["/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/"]
        if path.map({ p in systemRoots.contains { p.hasPrefix($0) } }) ?? true {
            return .system
        }
        let name = path.map { ($0 as NSString).lastPathComponent } ?? fallbackName
        return .process(name: name.isEmpty ? fallbackName : name, path: path)
    }

    private static func reason(_ name: String) -> String {
        switch name {
        case "Playing audio": return L10n.Sleep.playingAudio
        case "Video Wake Lock", "Playing video": return L10n.Sleep.playingVideo
        default:
            if name.hasPrefix("com.apple.audio.") { return L10n.Sleep.playingAudio }
            return name
        }
    }
}
