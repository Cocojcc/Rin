import AppKit
import Observation
import SwiftUI

/// One status item per visible module (or one combined item), in the order set in Settings.
///
/// Each tick the SwiftUI item is rendered once into an image and handed to the button. With
/// several displays AppKit keeps a copy of every item per menu bar; an image is cheap to copy,
/// a live SwiftUI view would be laid out again for each copy. Monochrome items are template
/// images, so each menu bar tints them for its own light or dark appearance.
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private var items: [(module: Module?, item: NSStatusItem)] = []
    private var layoutKey = ""
    private var themeObserver: NSObjectProtocol?

    func start() {
        rebuildIfNeeded()
        observeSettings()
        Monitor.shared.onSample = { [weak self] _ in
            Alerts.shared.evaluate()
            self?.rebuildIfNeeded()
            self?.refresh()
            if let self { NotchWatcher.shared.check(self.items) }
        }
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.refresh() }
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = SettingsStore.shared.prefs
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                Monitor.shared.applyConfiguration()
                Appearance.apply()
                self?.rebuildIfNeeded()
                self?.refresh()
                self?.observeSettings()
            }
        }
    }

    /// Modules shown right now: visible in settings and backed by hardware this Mac has.
    private func currentModules() -> [Module] {
        let prefs = SettingsStore.shared.prefs
        let s = Monitor.shared.snapshot
        let ready = Monitor.shared.tick > 0
        return prefs.menubar.order.filter { prefs.isVisible($0) && (!ready || MenuBarText.available($0, s)) }
    }

    private func rebuildIfNeeded() {
        let prefs = SettingsStore.shared.prefs
        let modules = currentModules()
        let key = prefs.menubar.displayMode.rawValue + ":" + modules.map(\.rawValue).joined(separator: ",")
        guard key != layoutKey else { return }
        layoutKey = key
        PanelController.shared.close()
        for entry in items { NSStatusBar.system.removeStatusItem(entry.item) }
        items = []
        renderers = [:]
        lastBytes = [:]

        if prefs.menubar.displayMode == .combined || modules.isEmpty {
            // With nothing visible, the combined item shows the app mark so there is always a way back in.
            add(module: nil)
        } else {
            // New items appear to the left of existing ones, so add right-to-left.
            for m in modules.reversed() { add(module: m) }
        }
        refresh()
    }

    private func add(module: Module?) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "hum." + (module?.rawValue ?? "combined")
        guard let button = item.button else { return }
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(clicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.identifier = NSUserInterfaceItemIdentifier(module?.rawValue ?? "combined")
        items.append((module, item))
    }

    /// Re-render every item from the latest snapshot. Unchanged pictures are not handed to
    /// AppKit again, which saves the per-display relayout of every copy of the item.
    func refresh() {
        let prefs = SettingsStore.shared.prefs
        let s = Monitor.shared.snapshot
        let height = NSStatusBar.system.thickness
        for (index, entry) in items.enumerated() {
            guard let button = entry.item.button else { continue }
            let colored: Bool
            let label: String
            if let m = entry.module {
                colored = MenuBarText.needsColor(m, s, prefs)
                label = MenuBarText.accessibility(m, s, prefs)
            } else {
                let modules = prefs.menubar.order.filter { prefs.isVisible($0) && MenuBarText.available($0, s) }
                colored = modules.contains { MenuBarText.tone($0, s, prefs).emphasized }
                label = MenuBarText.combinedAccessibility(modules, s, prefs)
            }
            let dark = button.effectiveAppearance.isDark
            let key = RendererKey(index: index, module: entry.module, template: !colored, dark: dark, height: height)
            let renderer = renderers[key] ?? StatusImage(module: entry.module, template: !colored, dark: dark, height: height)
            renderers[key] = renderer
            guard let (image, bytes) = renderer.render() else { continue }
            if bytes != lastBytes[index] {
                lastBytes[index] = bytes
                button.image = image
                if abs(entry.item.length - image.size.width) > 0.5 { entry.item.length = image.size.width }
            }
            if button.accessibilityLabel() != label { button.setAccessibilityLabel(label) }
        }
    }

    private struct RendererKey: Hashable {
        var index: Int
        var module: Module?
        var template: Bool
        var dark: Bool
        var height: CGFloat
    }

    private var renderers: [RendererKey: StatusImage] = [:]
    private var lastBytes: [Int: Data] = [:]

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            showMenu(from: sender)
            return
        }
        let id = sender.identifier?.rawValue ?? ""
        if let module = Module(rawValue: id) {
            PanelController.shared.toggle(.module(module), from: sender)
        } else {
            PanelController.shared.toggle(.combined, from: sender)
        }
    }

    private func showMenu(from button: NSStatusBarButton) {
        PanelController.shared.close()
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.Menu.open, action: #selector(openMain), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.Menu.settings, action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.Menu.quit, action: #selector(quit), keyEquivalent: "q").target = self
        let point = NSPoint(x: 0, y: button.bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: button)
    }

    #if DEBUG
    func debugButtons() -> [(String, NSStatusBarButton)] {
        items.compactMap { entry in entry.item.button.map { (entry.module?.rawValue ?? "combined", $0) } }
    }
    #endif

    @objc private func openMain() { MainWindowController.shared.show(.overview) }
    @objc private func openSettings() { MainWindowController.shared.show(.general) }
    @objc private func quit() { NSApp.terminate(nil) }
}

/// Keeps one SwiftUI renderer per status item; re-rendering an existing graph is far cheaper
/// than building a new one every tick.
final class StatusImage {
    private let renderer: ImageRenderer<AnyView>
    private let template: Bool
    private let appearance: NSAppearance
    private let scale: CGFloat

    init(module: Module?, template: Bool, dark: Bool, height: CGFloat) {
        self.template = template
        appearance = NSAppearance(named: template || !dark ? .aqua : .darkAqua)!
        scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let view: AnyView = module.map { AnyView(MenuBarItemView(module: $0)) } ?? AnyView(CombinedMenuBarView())
        renderer = MainActor.assumeIsolated {
            let r = ImageRenderer(content: AnyView(view
                .frame(height: height)
                .environment(\.colorScheme, template || !dark ? .light : .dark)))
            r.scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
            return r
        }
    }

    /// The image plus its raw pixels, for change detection. Template images keep only alpha.
    func render() -> (NSImage, Data)? {
        var cg: CGImage?
        MainActor.assumeIsolated {
            appearance.performAsCurrentDrawingAppearance { cg = renderer.cgImage }
        }
        guard let cg, let data = cg.dataProvider?.data as Data? else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
        image.isTemplate = template
        return (image, data)
    }
}
