import AppKit
import SwiftUI

@main
enum RinMain {
    static func main() {
        RenameMigration.run()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        MenuBarSpacing.claimItemSpacing()
        // Tooltips name icon-only controls (widget chips, steppers); the system waits about a
        // second before showing one, which feels slow there. Milliseconds, for Rin only.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Fonts.register()
        #if DEBUG
        if Snapshots.runIfRequested() { return }
        #endif
        Appearance.apply()
        NSApp.mainMenu = MainMenu.build()
        Alerts.shared.setUp()
        Monitor.shared.start()
        StatusBarController.shared.start()
        OnboardingController.shared.showIfNeeded()
        UpdateChecker.shared.checkOnLaunch()
        #if DEBUG
        ToggleCheck.runIfRequested()
        LiveDump.scheduleIfRequested()
        // `--rest-after <s> [<s> awake again]`: acts as if the screen locked, to measure resting.
        if let i = CommandLine.arguments.firstIndex(of: "--rest-after"), i + 1 < CommandLine.arguments.count,
           let delay = Double(CommandLine.arguments[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { Monitor.shared.setRest(.locked, true) }
            if i + 2 < CommandLine.arguments.count, let wake = Double(CommandLine.arguments[i + 2]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + wake) { Monitor.shared.setRest(.locked, false) }
            }
        }
        #endif
        if CommandLine.arguments.contains("--open-window") {
            MainWindowController.shared.show(.overview)
        }
        #if DEBUG
        // `--open-page settings|alerts|cpu`: opens the window on that page (screenshots).
        if let i = CommandLine.arguments.firstIndex(of: "--open-page"), i + 1 < CommandLine.arguments.count {
            let pages: [String: Page] = ["settings": .settings, "alerts": .alerts, "cpu": .monitor(.cpu), "overview": .overview]
            if let page = pages[CommandLine.arguments[i + 1]] { MainWindowController.shared.show(page) }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        Monitor.shared.stop()
        Alerts.shared.flush()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.show(.overview)
        return true
    }
}

enum Appearance {
    /// Only touches NSApp.appearance when it actually changes: setting it redraws every window,
    /// status items included.
    static func apply() {
        let target: NSAppearance?
        switch SettingsStore.shared.prefs.general.appearance {
        case .system: target = nil
        case .light: target = NSAppearance(named: .aqua)
        case .dark: target = NSAppearance(named: .darkAqua)
        }
        guard NSApp.appearance?.name != target?.name else { return }
        NSApp.appearance = target
    }

    /// Writes the per-app language override; takes effect on next launch.
    static func applyLanguage(_ choice: LanguageChoice) {
        switch choice {
        case .system: UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .zhHans: UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        case .en: UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        }
    }

    static func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

/// Menu bar shown while the main window is open (the app is a regular app only then).
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: L10n.MainMenu.about, action: #selector(AppActions.showAbout), keyEquivalent: "").target = AppActions.shared
        app.addItem(.separator())
        app.addItem(withTitle: L10n.Menu.settings, action: #selector(AppActions.showSettings), keyEquivalent: ",").target = AppActions.shared
        app.addItem(.separator())
        app.addItem(withTitle: L10n.MainMenu.hide, action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = app.addItem(withTitle: L10n.MainMenu.hideOthers, action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(.separator())
        app.addItem(withTitle: L10n.Menu.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(app, title: L10n.App.name))

        let edit = NSMenu(title: L10n.MainMenu.edit)
        edit.addItem(withTitle: L10n.MainMenu.copy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L10n.MainMenu.selectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu(edit, title: L10n.MainMenu.edit))

        let window = NSMenu(title: L10n.MainMenu.window)
        window.addItem(withTitle: L10n.MainMenu.minimize, action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: L10n.MainMenu.close, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu(window, title: L10n.MainMenu.window))
        NSApp.windowsMenu = window
        return main
    }

    private static func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

final class AppActions: NSObject {
    static let shared = AppActions()
    @objc func showAbout() { MainWindowController.shared.show(.settings) }
    @objc func showSettings() { MainWindowController.shared.show(.settings) }
}
