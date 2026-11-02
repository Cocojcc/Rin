import AppKit
import Observation
import SwiftUI

enum Page: Hashable {
    case overview
    case monitor(Module)
    /// A module's settings: widgets, dropdown, alerts (from the monitor page's settings button).
    case moduleSettings(Module)
    case settings
    /// 设置 › 菜单栏: separate items or one, and what the combined dropdown shows.
    case menuBar
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

    /// Leaves a module's pages once the module is switched off.
    func moduleSwitched(_ prefs: Preferences) {
        switch page {
        case .monitor(let m), .moduleSettings(let m):
            if !prefs.isEnabled(m) { page = .overview }
        default: break
        }
    }

    /// The Processes page's sort column, set by the "全部" links on the way in.
    var processSort: ProcessSort = .cpu
    /// What the title bar's search field filters the Processes page by.
    var processQuery = ""
    /// Each monitor page's time range; the title bar switches it.
    var ranges: [Module: TimeRange] = [:]
    var overviewRange: TimeRange = .m5

    func range(_ m: Module) -> TimeRange { ranges[m] ?? (m == .battery ? .h24 : .m5) }

    /// The ranges a page offers in the title bar.
    static func ranges(for m: Module) -> [TimeRange] { m == .battery ? [.h24, .d7] : [.m5, .h1, .h24, .d7] }
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

    /// Whether the page can be seen; a minimized window reads no more than a closed one.
    var isVisible: Bool { window.map { $0.isVisible && !$0.isMiniaturized } ?? false }

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

    /// Off while the pointer is over something a press drags.
    func setMovableByBackground(_ movable: Bool) { window?.isMovableByWindowBackground = movable }

    /// The Dock icon: back to the window on the page it was left on.
    func reopen() { show(Navigator.shared.page) }

    func show(_ page: Page) {
        PanelController.shared.close()
        Navigator.shared.page = page
        if window == nil { makeWindow() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
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
        window.setFrameAutosaveName("RinMainWindow.v4")
        window.isReleasedWhenClosed = false
        window.delegate = self
        if !window.setFrameUsingName("RinMainWindow.v4") { window.center() }
        self.window = window
        placeTrafficLights()
    }

    /// Centres the traffic lights in the title bar, 18 in from the left. AppKit puts them back on its own layouts, so this runs again after those.
    private func placeTrafficLights() {
        guard let window, !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let mini = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              let container = close.superview?.superview else { return }
        let band = UIScale.of(Sidebar.titleBand)
        let pitch = mini.frame.minX - close.frame.minX
        var frame = container.frame
        frame.size.height = band
        frame.origin.y = window.frame.height - band
        container.frame = frame
        let y = ((band - close.frame.height) / 2).rounded()
        for (i, button) in [close, mini, zoom].enumerated() {
            button.setFrameOrigin(NSPoint(x: UIScale.of(18) + CGFloat(i) * pitch, y: y))
        }
    }

    func windowDidResize(_ notification: Notification) { placeTrafficLights() }
    func windowDidBecomeKey(_ notification: Notification) { placeTrafficLights() }
    func windowDidExitFullScreen(_ notification: Notification) { placeTrafficLights() }
    func windowDidChangeBackingProperties(_ notification: Notification) { placeTrafficLights() }

    func windowDidMiniaturize(_ notification: Notification) {
        Monitor.shared.setVisible(.window(Navigator.shared.page), false)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        Monitor.shared.setVisible(.window(Navigator.shared.page), true)
    }

    func windowWillClose(_ notification: Notification) {
        Monitor.shared.setVisible(.window(Navigator.shared.page), false)
        NSApp.setActivationPolicy(.accessory)
    }
}
