import AppKit
import SwiftUI

enum PanelKind: Equatable {
    case module(Module)
    case combined

    var consumer: Consumer {
        switch self {
        case .module(let m): return .popover(m)
        case .combined: return .combinedPanel
        }
    }
}

/// Borderless panel that hangs under a status item, like a menu: closes on outside click or Esc.
final class DropdownPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        PanelController.shared.close()
    }
}

/// Hosting view that tells its panel when SwiftUI content changes height.
final class SizingHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.onSizeChange?() }
    }
}

final class PanelController {
    static let shared = PanelController()

    private(set) var kind: PanelKind?
    private var panel: DropdownPanel?
    private var host: SizingHostingView<AnyView>?
    private weak var button: NSStatusBarButton?
    private var anchorTop: CGFloat = 0
    private var anchorX: CGFloat = 0
    private var screenFrame: NSRect = .zero
    private var monitors: [Any] = []
    private var closedAt = Date.distantPast
    private var closedKind: PanelKind?

    static let width: CGFloat = 320

    #if DEBUG
    var debugContentView: NSView? { panel?.contentView }
    #endif

    func toggle(_ kind: PanelKind, from button: NSStatusBarButton) {
        // A click on the same item that just closed the panel (via the outside-click monitor) shouldn't reopen it.
        if self.kind == kind || (closedKind == kind && Date().timeIntervalSince(closedAt) < 0.3) {
            close()
            return
        }
        show(kind, from: button)
    }

    func show(_ kind: PanelKind, from button: NSStatusBarButton) {
        close()
        guard let window = button.window else { return }
        self.kind = kind
        self.button = button
        button.highlight(true)

        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        screenFrame = screen?.visibleFrame ?? .zero
        anchorTop = frame.minY - 4
        anchorX = frame.midX

        let panel = DropdownPanel()
        let root = AnyView(
            PanelRoot(kind: kind)
                .environment(\.accent, SettingsStore.shared.prefs.general.accent.colors)
        )
        let host = SizingHostingView(rootView: root)
        host.onSizeChange = { [weak self] in self?.layout() }
        panel.contentView = host
        self.panel = panel
        self.host = host
        layout()
        panel.orderFrontRegardless()
        panel.makeKey()

        Monitor.shared.setVisible(kind.consumer, true)
        installMonitors()
    }

    func close() {
        guard let panel else { return }
        if let kind {
            Monitor.shared.setVisible(kind.consumer, false)
            closedKind = kind
            closedAt = Date()
        }
        panel.orderOut(nil)
        self.panel = nil
        host = nil
        button?.highlight(false)
        button = nil
        kind = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }

    private func layout() {
        guard let panel, let host else { return }
        let size = host.fittingSize
        let width = size.width
        var x = anchorX - width / 2
        if screenFrame.width > 0 {
            x = min(max(x, screenFrame.minX + 8), screenFrame.maxX - width - 8)
        }
        let height = min(size.height, max(200, anchorTop - screenFrame.minY - 8))
        panel.setFrame(NSRect(x: x, y: anchorTop - height, width: width, height: height), display: true)
    }

    private func installMonitors() {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.close()
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window !== panel && !(event.window is DropdownPanel) && event.window?.className.contains("NSStatusBarWindow") == false {
                self.close()
            }
            return event
        }) { monitors.append(local) }
    }
}

/// Shared chrome for every dropdown: 320 wide at design size, drawn at UI scale.
struct PanelRoot: View {
    let kind: PanelKind
    var settings = SettingsStore.shared

    var body: some View {
        UIScaled {
            Group {
                switch kind {
                case .module(let m): ModulePanel(module: m)
                case .combined: CombinedPanel()
                }
            }
            .padding(16)
            .frame(width: PanelController.width)
            .environment(\.accent, settings.prefs.general.accent.colors)
            .ui(13)
            .foregroundStyle(Theme.text)
        }
        .background(GlassBackground(radius: UIScale.of(20)))
        .focusEffectDisabled()
    }
}

enum RenderContext {
    /// True while drawing debug snapshots, where AppKit-backed views can't render.
    static var offscreen = false
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}
