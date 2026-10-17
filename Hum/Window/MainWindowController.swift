import AppKit
import Observation
import SwiftUI

enum Page: Hashable {
    case overview
    case monitor(Module)
    case general
    case menubar
    case menubarModule(Module)
    case alerts
    case about

    /// The sidebar entry that should look selected for this page.
    var sidebarPage: Page {
        if case .menubarModule = self { return .menubar }
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
        window.setContentSize(NSSize(width: 860, height: 660))
        window.contentMinSize = NSSize(width: 760, height: 560)
        window.setFrameAutosaveName("HumMainWindow")
        window.isReleasedWhenClosed = false
        window.delegate = self
        if !window.setFrameUsingName("HumMainWindow") { window.center() }
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        Monitor.shared.setVisible(.window(Navigator.shared.page), false)
        NSApp.setActivationPolicy(.accessory)
    }
}
