import AppKit
import Observation

/// Checks a JSON feed (`{"version": "0.2.0", "url": "https://…"}`) named by the
/// `HumUpdateFeedURL` Info.plist key. There is no distribution channel yet, so without that key
/// the check button stays disabled.
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle, checking, upToDate, failed
        case available(version: String, url: URL)
    }

    private(set) var state: State = .idle

    @ObservationIgnored let feed: URL? = (Bundle.main.object(forInfoDictionaryKey: "HumUpdateFeedURL") as? String)
        .flatMap { $0.isEmpty ? nil : URL(string: $0) }

    var isConfigured: Bool { feed != nil }

    var buttonTitle: String {
        switch state {
        case .idle: return L10n.Settings.checkForUpdates
        case .checking: return L10n.Settings.checkingUpdates
        case .upToDate: return L10n.Settings.upToDate
        case .failed: return L10n.Settings.checkFailed
        case .available(let version, _): return L10n.Settings.downloadVersion(version)
        }
    }

    func checkOnLaunch() {
        guard isConfigured, SettingsStore.shared.prefs.general.autoCheckUpdates else { return }
        check()
    }

    /// Checks the feed, or opens the download page once a newer version has been found.
    func check() {
        if case .available(_, let url) = state {
            NSWorkspace.shared.open(url)
            return
        }
        guard let feed, state != .checking else { return }
        state = .checking
        URLSession.shared.dataTask(with: feed) { data, _, _ in
            var result = State.failed
            if let data,
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let version = object["version"] as? String,
               let url = (object["url"] as? String).flatMap(URL.init(string:)) {
                result = Self.isNewer(version, than: SystemInfo.appVersion) ? .available(version: version, url: url) : .upToDate
            }
            DispatchQueue.main.async { self.state = result }
        }.resume()
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }
}
