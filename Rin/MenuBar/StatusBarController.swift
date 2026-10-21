import AppKit
import Observation
import SwiftUI

/// One status item per visible module (or one combined item), in the order set in Settings.
///
/// Each tick the SwiftUI item is rendered once into an image and handed to the button. With
/// several displays AppKit keeps a copy of every item per menu bar; an image is cheap to copy,
/// a live SwiftUI view would be laid out again for each copy. Monochrome items are drawn as a
/// shape filled at draw time with each menu bar's own text color (white or black).
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
            // Nobody sees the menu bar while the screen is off or locked; the items catch up on
            // the full read when it comes back, and the characters stand still meanwhile.
            guard !Monitor.shared.isResting else {
                self?.pauseRunners()
                return
            }
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
                Navigator.shared.moduleSwitched(SettingsStore.shared.prefs)
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
        return prefs.menubar.order.filter { prefs.showsInMenubar($0) && (!ready || MenuBarText.available($0, s)) }
    }

    /// There is one status item per module (plus the combined one), created in settings order.
    /// Showing or hiding a module only flips `isVisible`, so the other items stay put; removing
    /// and re-adding every item made the whole group blink. Only a reorder rebuilds them.
    private func rebuildIfNeeded() {
        let prefs = SettingsStore.shared.prefs
        let key = prefs.menubar.order.map(\.rawValue).joined(separator: ",")
        if key != layoutKey {
            layoutKey = key
            PanelController.shared.close()
            for entry in items { NSStatusBar.system.removeStatusItem(entry.item) }
            items = []
            renderers = [:]
            lastBytes = [:]
            // New items appear to the left of existing ones, so add right-to-left.
            add(module: nil)
            for m in prefs.menubar.order.reversed() { add(module: m) }
        }
        updateVisibility()
    }

    private func updateVisibility() {
        let prefs = SettingsStore.shared.prefs
        let modules = currentModules()
        // With nothing visible, the combined item shows the app mark so there is always a way back in.
        let combined = prefs.menubar.displayMode == .combined || modules.isEmpty
        for entry in items {
            let show = entry.module.map { !combined && modules.contains($0) } ?? combined
            guard entry.item.isVisible != show else { continue }
            if !show, PanelController.shared.kind == entry.module.map({ PanelKind.module($0) }) ?? .combined {
                PanelController.shared.close()
            }
            entry.item.isVisible = show
        }
    }

    private func add(module: Module?) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "rin." + (module?.rawValue ?? "combined")
        item.isVisible = false
        guard let button = item.button else { return }
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(clicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.identifier = NSUserInterfaceItemIdentifier(module?.rawValue ?? "combined")
        button.addSubview(StatusContentView())
        items.append((module, item))
    }

    /// Pads the items again after the system-wide spacing changed.
    func relayout() { refresh() }

    /// Re-render every item from the latest snapshot. Unchanged pictures are not handed to
    /// AppKit again, which saves the per-display relayout of every copy of the item.
    func refresh() {
        let prefs = SettingsStore.shared.prefs
        let s = Monitor.shared.snapshot
        let height = NSStatusBar.system.thickness
        let pad = MenuBarSpacing.itemPadding(prefs)
        for (index, entry) in items.enumerated() where entry.item.isVisible {
            guard let button = entry.item.button else { continue }
            let colored: Bool
            let label: String
            if let m = entry.module {
                colored = MenuBarText.needsColor(m, s, prefs)
                label = MenuBarText.accessibility(m, s, prefs)
            } else {
                let modules = prefs.menubar.order.filter { prefs.showsInMenubar($0) && MenuBarText.available($0, s) }
                if prefs.menubar.combinedIconOnly || modules.isEmpty {
                    // The avatar is a picture; the glyphs are shapes in the bar's text color.
                    colored = prefs.menubar.combinedIcon == .avatar
                } else {
                    colored = modules.contains { MenuBarText.needsColor($0, s, prefs) }
                }
                label = MenuBarText.combinedAccessibility(modules, s, prefs)
            }
            let dark = button.effectiveAppearance.isDark
            let key = RendererKey(index: index, module: entry.module, template: !colored, dark: dark, height: height)
            let renderer = renderers[key] ?? StatusImage(module: entry.module, template: !colored, dark: dark, height: height)
            renderers[key] = renderer
            guard let (picture, size, bytes) = renderer.render(),
                  let content = button.subviews.lazy.compactMap({ $0 as? StatusContentView }).first else { continue }
            if bytes != lastBytes[index] {
                lastBytes[index] = bytes
                content.show(picture, asShape: !colored)
            }
            // Rin's items have no spacing of their own; half the spacing on each side stands in.
            let frame = NSRect(x: pad, y: ((button.bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height)
            if content.frame != frame { content.frame = frame }
            let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            content.updateRunners(runners(for: entry.module, prefs, s).compactMap { r in
                renderer.slots.rects[r.key].map { (r.key, RunnerLibrary.shared.runner(r.runner), $0, still ? 0 : RunnerPace.fps(r.driver, s)) }
            }, dark: dark, scale: button.window?.backingScaleFactor ?? 2)
            if abs(entry.item.length - (size.width + pad * 2)) > 0.5 { entry.item.length = size.width + pad * 2 }
            if button.accessibilityLabel() != label { button.setAccessibilityLabel(label) }
        }
    }

    /// The characters an item plays: its module's animation widget, or the combined item's
    /// icon (paced by the CPU) or its modules' widgets.
    private func runners(for module: Module?, _ prefs: Preferences, _ s: Snapshot) -> [(key: String, runner: String, driver: Module)] {
        if let m = module {
            return prefs.widgets(m).contains(.runner) ? [(m.rawValue, prefs.options(m, .runner).runner, m)] : []
        }
        let modules = prefs.menubar.order.filter { prefs.showsInMenubar($0) && MenuBarText.available($0, s) }
        if prefs.menubar.combinedIconOnly || modules.isEmpty {
            return prefs.menubar.combinedIcon == .runner ? [("icon", prefs.menubar.combinedRunner, .cpu)] : []
        }
        return modules.filter { prefs.widgets($0).contains(.runner) }.map { ($0.rawValue, prefs.options($0, .runner).runner, $0) }
    }

    private func pauseRunners() {
        for entry in items {
            entry.item.button?.subviews.compactMap { $0 as? StatusContentView }.forEach { $0.pauseRunners() }
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
        items.filter(\.item.isVisible).compactMap { entry in entry.item.button.map { (entry.module?.rawValue ?? "combined", $0) } }
    }
    #endif

    @objc private func openMain() { MainWindowController.shared.show(.overview) }
    @objc private func openSettings() { MainWindowController.shared.show(.settings) }
    @objc private func quit() { NSApp.terminate(nil) }
}

/// Keeps one SwiftUI renderer per status item; re-rendering an existing graph is far cheaper
/// than building a new one every tick.
final class StatusImage {
    private let renderer: ImageRenderer<AnyView>
    /// Where the item's characters sit, noted as it is laid out.
    let slots: RunnerSlots
    private let template: Bool
    private let appearance: NSAppearance
    private let scale: CGFloat

    init(module: Module?, template: Bool, dark: Bool, height: CGFloat) {
        self.template = template
        // Rendered in the bar's appearance even as a shape, so text gets the same smoothing as
        // the system's (light text on a dark bar comes out heavier).
        appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let sink = RunnerSlots()
        slots = sink
        let view: AnyView = module.map { AnyView(MenuBarItemView(module: $0)) } ?? AnyView(CombinedMenuBarView())
        renderer = MainActor.assumeIsolated {
            let r = ImageRenderer(content: AnyView(view
                .frame(height: height)
                .coordinateSpace(name: RunnerSlots.space)
                .environment(\.runnerSlots, sink)
                .environment(\.colorScheme, dark ? .dark : .light)))
            r.scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
            return r
        }
    }

    /// The picture, its size in points and its raw pixels (for change detection). Drawn with
    /// font smoothing on, like the system's own menu bar text.
    func render() -> (CGImage, NSSize, Data)? {
        var cg: CGImage?
        let scale = scale
        MainActor.assumeIsolated {
            appearance.performAsCurrentDrawingAppearance {
                renderer.render { size, draw in
                    let w = Int((size.width * scale).rounded(.up)), h = Int((size.height * scale).rounded(.up))
                    guard w > 0, h > 0,
                          let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                    ctx.scaleBy(x: scale, y: scale)
                    ctx.setAllowsFontSmoothing(true)
                    ctx.setShouldSmoothFonts(true)
                    draw(ctx)
                    cg = ctx.makeImage()
                }
            }
        }
        guard let cg, let data = cg.dataProvider?.data as Data? else { return nil }
        let size = NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale)
        return (cg, size, data)
    }
}

/// Draws an item inside its status bar button, as Stats does. A monochrome item is a shape
/// filled with the system text color, which the menu bar renders as brightly as its own text
/// (a template image or plain white comes out dimmer); colored items are drawn as they are.
final class StatusContentView: NSView {
    private var picture: CGImage?
    private var shape: CGImage?
    private var players: [String: RunnerPlayer] = [:]

    func show(_ image: CGImage, asShape: Bool) {
        if asShape {
            shape = Self.coverage(of: image)
            picture = nil
        } else {
            picture = image
            shape = nil
        }
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Plays each character at its spot (top-left points in the item's picture) at its pace;
    /// players for characters no longer there are removed.
    func updateRunners(_ runners: [(key: String, runner: Runner, rect: CGRect, fps: Double)], dark: Bool, scale: CGFloat) {
        if runners.isEmpty && players.isEmpty { return }
        wantsLayer = true
        guard let host = layer else { return }
        let color = barColor
        let pixelScale = scale >= 1.5 ? 2 : 1
        for r in runners {
            let player = players[r.key] ?? {
                let p = RunnerPlayer()
                host.addSublayer(p.layer)
                players[r.key] = p
                return p
            }()
            let rect = CGRect(x: r.rect.minX, y: bounds.height - r.rect.maxY, width: r.rect.width, height: r.rect.height)
            player.show(r.runner, frames: RunnerLibrary.shared.frames(r.runner, scale: pixelScale, dark: dark), rect: rect, color: color, scale: scale)
            player.setFPS(r.fps)
        }
        let keep = Set(runners.map(\.key))
        for (key, player) in players where !keep.contains(key) {
            player.layer.removeFromSuperlayer()
            players[key] = nil
        }
    }

    func pauseRunners() {
        for player in players.values { player.setFPS(0) }
    }

    /// The menu bar's text color for this item's appearance, as the shapes are filled.
    private var barColor: CGColor {
        var color = NSColor.textColor.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { color = NSColor.textColor.cgColor }
        return color
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let color = barColor
        for player in players.values { player.setColor(color) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if let picture {
            ctx.draw(picture, in: bounds)
        } else if let shape {
            ctx.saveGState()
            ctx.clip(to: bounds, mask: shape)
            NSColor.textColor.setFill()
            bounds.fill()
            ctx.restoreGState()
        }
    }

    /// The image's alpha as a grayscale clip mask.
    private static func coverage(of image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let alpha = ctx.data else { return nil }
        let bytes = Data(bytes: alpha, count: w * h)
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
