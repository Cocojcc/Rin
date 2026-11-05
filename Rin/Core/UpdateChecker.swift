import AppKit
import Observation
import Sparkle

/// Updates through Sparkle, with the whole conversation on one button in Settings: a click checks,
/// and what it finds downloads, installs and relaunches without another question. An automatic
/// check only puts the new version on the button.
///
/// Only release builds name a feed (`RIN_UPDATE_FEED`, set by scripts/release.sh). Without one
/// Sparkle never starts and the button stays disabled, so an update can't replace a build in development.
@Observable
final class UpdateChecker: NSObject {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle, checking, upToDate, checkFailed, updateFailed, installing
        case available(version: String)
        case downloading(percent: Int?)
    }

    private(set) var state: State = .idle

    @ObservationIgnored private var updater: SPUUpdater?
    /// Sparkle's question about the update an automatic check found, until the button is clicked.
    @ObservationIgnored private var answer: ((SPUUserUpdateChoice) -> Void)?
    @ObservationIgnored private var expectedBytes: UInt64 = 0
    @ObservationIgnored private var receivedBytes: UInt64 = 0
    private static let reopenKey = "update.reopenSettings"

    var isConfigured: Bool {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else { return false }
        return !feed.isEmpty
    }

    /// Something is under way, and the button has nothing to offer until it ends.
    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    var buttonTitle: String {
        switch state {
        case .idle: return L10n.Settings.checkForUpdates
        case .checking: return L10n.Settings.checkingUpdates
        case .upToDate: return L10n.Settings.upToDate
        case .checkFailed: return L10n.Settings.checkFailed
        case .updateFailed: return L10n.Settings.updateFailed
        case .available(let version): return L10n.Settings.updateToVersion(version)
        case .downloading(let percent): return percent.map(L10n.Settings.downloadingUpdate) ?? L10n.Settings.downloadStarting
        case .installing: return L10n.Settings.installingUpdate
        }
    }

    func start() {
        guard isConfigured else { return }
        // Back from an update the button started: the window it was in opens again.
        if UserDefaults.standard.bool(forKey: Self.reopenKey) {
            UserDefaults.standard.removeObject(forKey: Self.reopenKey)
            MainWindowController.shared.show(.settings)
        }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil)
        do {
            try updater.start()
        } catch {
            NSLog("Rin: Sparkle didn't start: %@", error.localizedDescription)
            return
        }
        self.updater = updater
        applyAutomaticChecks()
    }

    /// Follows the setting; Sparkle itself checks at launch and once a day after that.
    func applyAutomaticChecks() {
        updater?.automaticallyChecksForUpdates = SettingsStore.shared.prefs.general.autoCheckUpdates
    }

    /// Installs what an automatic check found, or checks now and installs what that finds.
    func checkOrInstall() {
        if let answer {
            self.answer = nil
            answer(.install)
        } else if !isBusy {
            updater?.checkForUpdates()
        }
    }
}

extension UpdateChecker: SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: SettingsStore.shared.prefs.general.autoCheckUpdates, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        state = .checking
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state updateState: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if appcastItem.isInformationOnlyUpdate {
            reply(.dismiss)
        } else if updateState.userInitiated {
            reply(.install)
        } else {
            answer = reply
            state = .available(version: appcastItem.displayVersionString)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        state = .upToDate
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        NSLog("Rin: update failed: %@", error.localizedDescription)
        state = state == .checking ? .checkFailed : .updateFailed
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedBytes = 0
        receivedBytes = 0
        state = .downloading(percent: nil)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedBytes = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedBytes += length
        guard expectedBytes > 0 else { return }
        let next = State.downloading(percent: Int(min(receivedBytes * 100 / expectedBytes, 100)))
        if next != state { state = next }
    }

    func showDownloadDidStartExtractingUpdate() {
        state = .installing
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        state = .installing
        reply(.install)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        UserDefaults.standard.set(true, forKey: Self.reopenKey)
        state = .installing
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        state = .idle
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        answer = nil
        // What the session ended with stays on the button.
        switch state {
        case .upToDate, .checkFailed, .updateFailed: break
        default: state = .idle
        }
    }
}
