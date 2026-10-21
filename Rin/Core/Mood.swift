import SwiftUI

/// Her face for how things stand: calm while all is well, annoyed while something runs high or
/// a rule holds quietly, angry while an alert is up.
enum Mood {
    case calm, annoyed, angry

    var avatar: String {
        switch self {
        case .calm: return "Avatar"
        case .annoyed: return "AvatarAnnoyed"
        case .angry: return "AvatarAngry"
        }
    }
}

/// The status line, as she says it, with its mood and color. Shared by the overview strip, the
/// combined dropdown, the sidebar mark and the menu bar avatar, so they always agree.
struct Status {
    var mood: Mood
    var line: String
    var color: Color

    static func now(_ s: Snapshot = Monitor.shared.snapshot, _ prefs: Preferences = SettingsStore.shared.prefs) -> Status {
        #if DEBUG
        // `RIN_MOOD=annoyed|angry`: her other faces, for snapshots.
        switch ProcessInfo.processInfo.environment["RIN_MOOD"] {
        case "annoyed": return Status(mood: .annoyed, line: words(.memory), color: Theme.warn)
        case "angry":
            let e = AlertEvent(rule: .cpu, date: Date(), value: 94, limit: 90, held: 60)
            return Status(mood: .angry, line: AlertText.banner(e), color: Theme.danger)
        default: break
        }
        #endif
        if let e = Alerts.shared.current { return Status(mood: .angry, line: AlertText.banner(e), color: Theme.danger) }
        let reasons = strained(s, prefs)
        switch reasons.count {
        case 0: return Status(mood: .calm, line: L10n.Overview.allGood, color: Theme.ok)
        case 1: return Status(mood: .annoyed, line: words(reasons[0]), color: Theme.warn)
        default: return Status(mood: .annoyed, line: L10n.Overview.issues(reasons.count), color: Theme.warn)
        }
    }

    /// Modules with a rule holding, or running high by the menu bar's own measure (whether or
    /// not the bar is set to color them).
    static func strained(_ s: Snapshot, _ prefs: Preferences) -> [Module] {
        let active = Alerts.shared.active
        return Module.allCases.filter { m in
            prefs.isEnabled(m) && (active[m] != nil || MenuBarText.load(m, s, prefs) != .normal)
        }
    }

    private static func words(_ m: Module) -> String {
        switch m {
        case .cpu: return L10n.Mood.cpu
        case .gpu: return L10n.Mood.gpu
        case .memory: return L10n.Mood.memory
        case .network: return L10n.Mood.network
        case .disk: return L10n.Mood.disk
        case .battery: return L10n.Mood.battery
        case .bluetooth: return L10n.Mood.bluetooth
        case .sensors: return L10n.Mood.sensors
        }
    }
}
