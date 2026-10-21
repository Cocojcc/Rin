import AppKit

/// Space between status items. Every app lays out its own items with `NSStatusItemSpacing`
/// (an item's window is that much wider than its content), read once when the app starts. Rin
/// sets it to zero for itself and pads each item by half the chosen spacing instead, so its
/// spacing can change at once. The system-wide value sits in the global ByHost domain; the
/// system's items take it when their processes restart, other apps when they are next opened.
enum MenuBarSpacing {
    /// macOS's spacing when nothing is set.
    static let systemDefault = 16
    static let moduleGapRange = 4...20
    static let moduleGapStep = 2

    enum Preset: Int, CaseIterable {
        case standard, compact, tightest

        var spacing: Int? { [nil, 10, 6][rawValue] }
        var selectionPadding: Int? { [nil, 8, 6][rawValue] }
    }

    private static let spacingKey = "NSStatusItemSpacing"
    private static let paddingKey = "NSStatusItemSelectionPadding"

    /// The system-wide spacing, read once and updated when Rin changes it.
    private(set) static var system = readSystem()

    private static func readSystem() -> Int {
        (CFPreferencesCopyValue(spacingKey as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                                kCFPreferencesCurrentHost) as? NSNumber)?.intValue ?? systemDefault
    }

    /// Rin's own items get no spacing from AppKit; call before the first status item exists.
    static func claimItemSpacing() {
        if UserDefaults.standard.object(forKey: spacingKey) as? Int != 0 { UserDefaults.standard.set(0, forKey: spacingKey) }
    }

    static var preset: Preset {
        let s = system
        if s >= 14 { return .standard }
        return s >= 8 ? .compact : .tightest
    }

    static func setPreset(_ preset: Preset) {
        guard preset != self.preset else { return }
        write(spacingKey, preset.spacing)
        write(paddingKey, preset.selectionPadding)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        system = readSystem()
        // The system's own items live in these two; they restart by themselves.
        for process in ["ControlCenter", "SystemUIServer"] {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            task.arguments = [process]
            try? task.run()
        }
    }

    /// Spacing between Rin's items; without a choice, the system's.
    static func moduleGap(_ prefs: Preferences) -> Int { prefs.menubar.moduleSpacing ?? system }

    /// Room on each side of a Rin item.
    static func itemPadding(_ prefs: Preferences) -> CGFloat { CGFloat(moduleGap(prefs)) / 2 }

    private static func write(_ key: String, _ value: Int?) {
        CFPreferencesSetValue(key as CFString, value.map { NSNumber(value: $0) }, kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }
}
