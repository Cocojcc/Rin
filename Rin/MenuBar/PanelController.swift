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
        PanelController.shared.cancel()
    }
}

/// Hosting view that tells its panel when SwiftUI content changes height.
final class SizingHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: (() -> Void)?

    // The details panel stays out of key, so its first click has to count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
    private var detailPanel: DropdownPanel?
    private var detailHost: SizingHostingView<AnyView>?
    private weak var button: NSStatusBarButton?
    private var anchorTop: CGFloat = 0
    private var anchorX: CGFloat = 0
    private var screenFrame: NSRect = .zero
    private var monitors: [Any] = []
    private var closedAt = Date.distantPast
    private var closedKind: PanelKind?

    static let width: CGFloat = 330

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

    /// Opens what a combined dropdown row shows beside it, or closes it when it's already open.
    func toggleDetail(_ detail: CombinedDetail) {
        setDetail(CombinedDetails.shared.selection == detail ? nil : detail)
    }

    func setDetail(_ detail: CombinedDetail?) {
        let details = CombinedDetails.shared
        guard details.selection != detail else { return }
        if case .module(let m) = details.selection { Monitor.shared.setVisible(.popover(m), false) }
        details.selection = detail
        if case .module(let m) = detail { Monitor.shared.setVisible(.popover(m), true) }
        guard detail != nil else {
            detailPanel?.orderOut(nil)
            detailPanel = nil
            detailHost = nil
            return
        }
        if detailPanel == nil {
            let panel = DropdownPanel()
            // The dropdown keeps the keyboard, so Esc and its hover keep working.
            panel.becomesKeyOnlyIfNeeded = true
            let host = SizingHostingView(rootView: AnyView(CombinedDetailRoot()))
            host.onSizeChange = { [weak self] in self?.layoutDetail() }
            panel.contentView = host
            detailPanel = panel
            detailHost = host
            layoutDetail()
            panel.orderFront(nil)
        } else {
            layoutDetail()
        }
    }

    /// Esc: the details first, then the dropdown.
    func cancel() {
        if CombinedDetails.shared.selection != nil { setDetail(nil) } else { close() }
    }

    func close() {
        guard let panel else { return }
        setDetail(nil)
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

    /// Beside the dropdown with their tops level: on its left, or its right when the left runs off the screen.
    private func layoutDetail() {
        guard let panel, let detailPanel, let detailHost else { return }
        let size = detailHost.fittingSize
        let gap = UIScale.of(10)
        let left = panel.frame.minX - gap - size.width
        let x = left >= screenFrame.minX + 8 ? left : panel.frame.maxX + gap
        let height = min(size.height, max(200, anchorTop - screenFrame.minY - 8))
        detailPanel.setFrame(NSRect(x: x, y: anchorTop - height, width: size.width, height: height), display: true)
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

/// A dropdown's contents.
struct PanelRoot: View {
    let kind: PanelKind
    var settings = SettingsStore.shared

    var body: some View {
        PanelChrome {
            switch kind {
            case .module(let m):
                ModulePanel(module: m)
            case .combined:
                CombinedPanel()
            }
        }
    }
}

/// Shared chrome for every dropdown and the details beside one: 330 wide at design size, drawn at UI scale.
struct PanelChrome<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        UIScaled {
            VStack(alignment: .leading, spacing: 0) { content }
            .padding(20)
            .frame(width: PanelController.width)
            .ui(14)
            .foregroundStyle(Theme.text)
        }
        .background(GlassBackground(radius: UIScale.of(16)))
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
