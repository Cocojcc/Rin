import AppKit
import Observation
import SwiftUI

enum Page: Hashable {
    case overview
    case monitor(Module)
    /// A module's settings: widgets, dropdown, alerts (from the monitor page's settings button).
    case moduleSettings(Module)
    case settings
    /// Every process, sortable, with an inspector for the selected one.
    case processes
    /// Keep-awake and the apps holding the Mac awake.
    case sleep
    /// Alert rules, what fired recently and how alerts are sent.
    case alerts
    case about

    /// The sidebar entry that should look selected for this page.
    var sidebarPage: Page {
        if case .moduleSettings(let m) = self { return .monitor(m) }
        return self
    }
}

@Observable
final class Navigator {
    static let shared = Navigator()
    /// The Processes page's sort column, set by the "全部" links on the way in.
    var processSort: ProcessSort = .cpu
    /// A rule the Alerts page should point out when it opens (from a chart or module settings).
    var alertFocus: Alerts.Rule?
    var page: Page = .overview {
        didSet {
            guard page != oldValue else { return }
            MainWindowController.shared.pageChanged(from: oldValue, to: page)
        }
    }
}

final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible ?? false }

    /// Opens the Processes page sorted by the list the "全部" link sat on.
    func showProcesses(sortedBy sort: ProcessSort) {
        Navigator.shared.processSort = sort
        show(.processes)
    }

    /// Opens the Alerts page with one rule pointed out.
    func showAlerts(focus rule: Alerts.Rule?) {
        Navigator.shared.alertFocus = rule
        show(.alerts)
    }

    func show(_ page: Page) {
        PanelController.shared.close()
        Navigator.shared.page = page
        if window == nil { makeWindow() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        Monitor.shared.setVisible(.window(Navigator.shared.page), true)
    }

    fileprivate func pageChanged(from old: Page, to new: Page) {
        guard isVisible else { return }
        Monitor.shared.setVisible(.window(old), false)
        Monitor.shared.setVisible(.window(new), true)
    }

    private func makeWindow() {
        let root = MainView()
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = L10n.App.name
        window.isMovableByWindowBackground = true
        // The SwiftUI root draws the frosted glass, so the window itself is clear.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.setContentSize(NSSize(width: UIScale.of(800), height: UIScale.of(700)))
        window.contentMinSize = MainView.minSize
        window.setFrameAutosaveName("HumMainWindow.v4")
        window.isReleasedWhenClosed = false
        window.delegate = self
        if !window.setFrameUsingName("HumMainWindow.v4") { window.center() }
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        Monitor.shared.setVisible(.window(Navigator.shared.page), false)
        NSApp.setActivationPolicy(.accessory)
    }
}
