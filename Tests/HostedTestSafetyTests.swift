import AppKit
import XCTest
@testable import Rin

/// XCTest launches Rin itself to host these tests; that launch, and quitting it, must leave the
/// user's settings, alert log and history alone.
final class HostedTestSafetyTests: XCTestCase {
    private static var dataFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rin", isDirectory: true)
    }

    private static func modified(_ name: String) -> Date? {
        try? dataFolder.appendingPathComponent(name).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    func testHostedLaunchTurnsPersistenceOff() {
        XCTAssertTrue(RinMain.isRunningTests)
        XCTAssertFalse(SettingsStore.persistenceEnabled)
    }

    func testQuittingTheTestHostWritesNothing() {
        let files = ["history.plist", "alerts.json", "bluetooth.json"]
        let before = files.map(Self.modified)
        AppDelegate().applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        History().save()
        Alerts.shared.flush()
        BluetoothStore().record([BluetoothDevice(id: "rin.test.device", name: "Test Mouse", kind: .mouse, level: 0.5)], now: Date())
        XCTAssertEqual(files.map(Self.modified), before)
    }

    func testReopeningTheTestHostOpensNoWindow() {
        XCTAssertFalse(AppDelegate().applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
    }

    /// The test host starts from nothing instead of reading the user's saved history.
    func testTestHostDoesNotLoadTheUsersHistory() {
        XCTAssertNil(History().bucket(near: Date()))
    }
}
