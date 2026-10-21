import Foundation

/// The app was called Hum (`com.zoro.hum`) before it became Rin. On the first launch under the
/// new name its settings and its data folder move over, before anything reads them.
enum RenameMigration {
    private static let oldDomain = "com.zoro.hum"
    private static let doneKey = "migratedFromHum"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        // Settings, status item positions and the window frame. Keys that carried the old name
        // (status items "hum.cpu", the window "HumMainWindow.v4") take the new one.
        if defaults.object(forKey: "preferences.v2") == nil, let old = defaults.persistentDomain(forName: oldDomain) {
            for (key, value) in old {
                let renamed = key.replacingOccurrences(of: "hum.", with: "rin.")
                    .replacingOccurrences(of: "HumMainWindow", with: "RinMainWindow")
                defaults.set(value, forKey: renamed)
            }
        }

        // History, the alert log, Bluetooth devices and imported characters.
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldFolder = support.appendingPathComponent("Hum", isDirectory: true)
        let newFolder = support.appendingPathComponent("Rin", isDirectory: true)
        if fm.fileExists(atPath: oldFolder.path), !fm.fileExists(atPath: newFolder.path) {
            try? fm.moveItem(at: oldFolder, to: newFolder)
        }
    }
}
