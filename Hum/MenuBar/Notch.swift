import AppKit
import Observation
import SwiftUI

/// Finds status items the MacBook notch is covering.
///
/// AppKit doesn't say when an item doesn't fit: a covered item stays `isVisible` and
/// `occlusionState` is unreliable. Its window frame does tell: it either sits under the notch
/// (left of the screen's `auxiliaryTopRightArea`, which is in global coordinates) or is moved
/// off every screen (`window.screen == nil`). Items only count once two checks in a row agree,
/// so a relayout in progress doesn't trigger anything.
@Observable
final class NotchWatcher {
    static let shared = NotchWatcher()

    /// Modules currently covered, in menu bar order.
    private(set) var hidden: [Module] = []

    @ObservationIgnored private var lastCheck: [Module] = []
    @ObservationIgnored private var alerted = false

    func check(_ items: [(module: Module?, item: NSStatusItem)]) {
        var covered: [Module] = []
        if NSScreen.screens.contains(where: { $0.auxiliaryTopRightArea != nil }) {
            for entry in items {
                guard let module = entry.module, let window = entry.item.button?.window else { continue }
                if let screen = window.screen {
                    if let area = screen.auxiliaryTopRightArea, window.frame.minX < area.minX { covered.append(module) }
                } else {
                    covered.append(module)
                }
            }
        }
        let confirmed = covered.filter(lastCheck.contains)
        lastCheck = covered
        let order = SettingsStore.shared.prefs.menubar.order
        let sorted = order.filter(confirmed.contains)
        if sorted != hidden { hidden = sorted }

        if hidden.isEmpty {
            NotchAlertController.shared.close()
        } else {
            alertIfNeeded()
        }
    }

    #if DEBUG
    func debugSetHidden(_ modules: [Module]) { hidden = modules }
    #endif

    private func alertIfNeeded() {
        let prefs = SettingsStore.shared.prefs
        guard !alerted, prefs.general.onboarded, prefs.menubar.displayMode == .separate,
              !prefs.menubar.notchAlertDismissed else { return }
        alerted = true
        NotchAlertController.shared.show()
    }
}

/// The glass card under the menu bar: "菜单栏放不下".
final class NotchAlertController {
    static let shared = NotchAlertController()

    private var panel: NSPanel?

    func show() {
        close()
        let panel = NotchPanel()
        let host = NSHostingView(rootView: NotchAlertView()
            .environment(\.accent, SettingsStore.shared.prefs.general.accent.colors))
        panel.contentView = host
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.auxiliaryTopRightArea != nil } ?? NSScreen.main
        if let screen {
            let menuBar = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
            // Just right of the notch, under where the covered items would be.
            let notchRight = screen.auxiliaryTopRightArea?.minX ?? screen.frame.midX
            let x = min(max(notchRight - 23, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
            let y = screen.frame.maxY - menuBar - 8 - size.height
            panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        }
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .alertPanel
    }

    override var canBecomeKey: Bool { true }
}

struct NotchAlertView: View {
    var watcher = NotchWatcher.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                LineIcon(d: Icons.notch, size: 18, lineWidth: 1.5)
                    .foregroundStyle(Theme.warn)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.warnBg))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Notch.title).ui(17, 500).kerning(-0.17).accessibilityAddTraits(.isHeader)
                    Text(L10n.Notch.hiddenCount(watcher.hidden.count)).ui(12).foregroundStyle(Theme.sub)
                }
                Spacer(minLength: 0)
            }
            FlowLayout(spacing: 6) {
                ForEach(watcher.hidden) { m in
                    HStack(spacing: 6) {
                        LineIcon(d: Icons.module(m), size: 14, lineWidth: 1.5).foregroundStyle(Theme.sub)
                        Text(m.title)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.well))
                }
            }
            HStack(spacing: 8) {
                WellButton(title: L10n.Notch.dontRemind, height: 38, radius: 12, horizontalPadding: 14) {
                    SettingsStore.shared.prefs.menubar.notchAlertDismissed = true
                    NotchAlertController.shared.close()
                }
                PrimaryButton(title: L10n.Notch.merge) {
                    SettingsStore.shared.prefs.menubar.displayMode = .combined
                    NotchAlertController.shared.close()
                }
                IconButton(d: Icons.general, size: 38, radius: 12, iconSize: 15, viewBox: 16, lineWidth: 1.6, tint: Theme.text, label: L10n.Notch.openSettings) {
                    NotchAlertController.shared.close()
                    MainWindowController.shared.show(.menubar)
                }
            }
        }
        .padding(18)
        .frame(width: 320)
        .background(GlassBackground(radius: 22))
        .ui(13)
        .foregroundStyle(Theme.text)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// Left-to-right wrapping layout (chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
