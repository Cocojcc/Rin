import AppKit
import Observation
import SwiftUI

enum Page: Hashable {
    case overview
    case monitor(Module)
    /// A module's settings: widgets, dropdown, alerts (from the monitor page's settings button).
    case moduleSettings(Module)
    case settings

    /// The sidebar entry that should look selected for this page.
    var sidebarPage: Page {
        if case .moduleSettings(let m) = self { return .monitor(m) }
        return self
    }
}

@Observable
final class Navigator {
    static let shared = Navigator()
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
        window.contentMinSize = NSSize(width: UIScale.of(720), height: UIScale.of(560))
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
