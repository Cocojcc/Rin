import AppKit
import QuartzCore
import SwiftUI

/// How things stand now, one row a module in the sidebar's order: its name and what the figure means
/// on the left, the figure on the right, and the line under the row filled to the share in use. A row
/// opens its module's page, where the history lives. CPU, memory and network come first and a size up.
struct OverviewPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    var alerts = Alerts.shared
    @Environment(\.pageExtra) private var extra

    /// What the design's window leaves for the rows, and the bigger rows' share of it against the others' 1.
    private static let designHeight: CGFloat = 622, leadShare: CGFloat = 1.42

    private static func isLead(_ m: Module) -> Bool { m == .cpu || m == .memory || m == .network }

    var body: some View {
        let s = monitor.snapshot
        let _ = monitor.tick
        // A Mac without a battery has no row for one.
        let modules = Sidebar.moduleOrder.filter(settings.prefs.isEnabled).filter { $0 != .battery || s.battery.hasBattery }
        if modules.isEmpty {
            Text(L10n.Overview.allOff).ui(14).foregroundStyle(Theme.sub).padding(.top, 20)
        } else {
            let shares = modules.reduce(0) { $0 + (Self.isLead($1) ? Self.leadShare : 1) }
            // Every row has its space above the line first; the shares divide what's left, as in the design.
            let unit = (Self.designHeight + extra - OverviewRow.linePad * CGFloat(modules.count)) / shares
            VStack(spacing: 0) {
                ForEach(modules) { m in
                    let lead = Self.isLead(m)
                    OverviewRow(module: m, lead: lead, height: OverviewRow.linePad + unit * (lead ? Self.leadShare : 1), content: content(m, s))
                }
            }
        }
    }

    /// What a module's row says: the figure, the words under its name, how full its line is and whether it is past a limit.
    private func content(_ m: Module, _ s: Snapshot) -> OverviewRow.Content {
        let gap = L10n.Overview.detailGap
        switch m {
        case .cpu:
            return .init(value: Format.percentNumber(s.cpu.total), unit: "%",
                         detail: L10n.Monitor.userShare(Format.percent(s.cpu.user)) + gap + L10n.Monitor.systemShare(Format.percent(s.cpu.system)),
                         share: s.cpu.total, hot: s.cpu.total >= 0.9 || alerts.firing(.cpu) != nil)
        case .memory:
            let mem = s.memory
            return .init(value: Format.percentNumber(mem.usedFraction), unit: "%", detail: Format.memory(used: mem.used, of: mem.total),
                         share: mem.usedFraction, hot: mem.pressure == .critical || alerts.firing(.memory) != nil)
        case .network:
            let n = s.network
            guard n.connected else { return .init(value: L10n.Common.dash, unit: nil, detail: L10n.Overview.disconnected, share: 0, hot: false) }
            let speed = settings.prefs.network.speedUnit
            let down = Format.rateParts(n.down, unit: speed)
            return .init(value: down.0, unit: down.1,
                         detail: L10n.Overview.downloadSpeed + gap + L10n.Monitor.partValue(L10n.Panel.upload, Format.rate(n.up, unit: speed)),
                         share: monitor.history.downloadShare(n.down), hot: false)
        case .disk:
            let root = s.disk.root
            let free = Format.parts(Format.storage(root?.available ?? 0))
            let used = root?.usedFraction ?? 0
            return .init(value: free.0, unit: free.1,
                         detail: L10n.Overview.freeSpace + gap + L10n.Monitor.partValue(L10n.Disk.used, Format.percent(used)),
                         share: used, hot: false)
        case .gpu:
            let g = s.gpu
            let vram = g.memoryLimit > 0 ? Format.memory(used: g.memoryUsed, of: g.memoryLimit) : Format.memory(g.memoryUsed)
            return .init(value: Format.percentNumber(g.utilization), unit: "%", detail: L10n.Monitor.partValue(L10n.Panel.vram, vram), share: g.utilization, hot: false)
        case .sensors:
            let t = s.sensors.cpuAverage
            // Read to the nearest ten: the last figure only ever jitters.
            let fan = s.sensors.fans.first.map { L10n.Monitor.partValue(L10n.Overview.fan, Format.rpm(($0.rpm / 10).rounded() * 10)) }
            return .init(value: t.map { Format.temperature($0, unit: settings.prefs.general.temperatureUnit) } ?? L10n.Common.dash, unit: nil,
                         detail: L10n.Overview.cpuTemp + (fan.map { gap + $0 } ?? ""),
                         // The line stays in Celsius whatever the figure is shown in.
                         share: (t ?? 0) / 100, hot: (t ?? 0) >= 90)
        case .battery:
            let b = s.battery
            return .init(value: Format.percentNumber(b.level), unit: "%", detail: PanelText.batteryState(b), share: b.level, hot: !b.onAC && b.level <= 0.2)
        case .bluetooth:
            let devices = s.bluetooth.withBattery.sorted { ($0.level ?? 1) < ($1.level ?? 1) }
            guard let lowest = devices.first else { return .init(value: L10n.Common.dash, unit: nil, detail: "", share: 0, hot: false) }
            let others = devices.dropFirst().map { L10n.Monitor.partValue($0.name, Format.percent($0.level ?? 0)) }
            return .init(value: Format.percentNumber(lowest.level ?? 0), unit: "%", detail: ([lowest.name] + others).joined(separator: gap),
                         share: lowest.level ?? 0, hot: BluetoothText.isLow(lowest, settings.prefs))
        }
    }
}

/// One module's row.
private struct OverviewRow: View {
    struct Content {
        var value: String
        var unit: String?
        var detail: String
        var share: Double
        var hot: Bool
    }

    let module: Module
    var lead: Bool
    var height: CGFloat
    var content: Content
    @State private var hovering = false

    /// How far the hover's background reaches past the row's text and line.
    private static let reach: CGFloat = 12
    /// The space between a row's text and its line.
    static let linePad: CGFloat = 8

    var body: some View {
        Button { Navigator.shared.page = .monitor(module) } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(module.title).ui(lead ? 16 : 15, 500).lineLimit(1).frame(height: 20).accessibilityAddTraits(.isHeader)
                    Text(content.detail).ui(12.5).foregroundStyle(Theme.sub).lineLimit(1).truncationMode(.tail).frame(height: 17)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                BigValue(value: content.value, unit: content.unit, size: lead ? 34 : 26, color: content.hot ? Theme.danger : Theme.text, proportional: false)
                    .fixedSize()
            }
            .padding(.bottom, Self.linePad)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                OverviewLine(share: min(max(content.share, 0), 1), color: content.hot ? Theme.danger : Theme.hue(module) ?? Theme.sub)
                    .frame(height: 1.5)
            }
            .padding(.horizontal, Self.reach)
            .frame(height: height)
            .background { if hovering { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.lgHover) } }
            .padding(.horizontal, -Self.reach)
            .hoverAnimation(hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.Panel.openMonitor(module.title))
    }
}

/// The line under a row, filled to a share. Core Animation glides it in the window server: a line that
/// changes with most readings would otherwise have the app redrawing without pause.
private struct OverviewLine: View {
    var share: Double
    var color: Color

    var body: some View {
        if RenderContext.offscreen {
            // Snapshots can't draw AppKit views.
            LevelBar(fraction: share, color: color, height: 1.5)
        } else {
            OverviewLineLayers(share: share, color: color)
        }
    }
}

private struct OverviewLineLayers: NSViewRepresentable {
    var share: Double
    var color: Color

    func makeNSView(context: Context) -> OverviewLineView { OverviewLineView() }

    func updateNSView(_ view: OverviewLineView, context: Context) {
        view.update(share: share, color: color, glide: !context.environment.accessibilityReduceMotion)
    }
}

private final class OverviewLineView: NSView {
    private let track = CALayer(), fill = CALayer()
    private var share = 0.0
    private var color = Color.clear

    override var isFlipped: Bool { true }
    // Clicks go through to the row.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(track)
        track.addSublayer(fill)
        track.masksToBounds = true
        track.cornerRadius = 0.75
        fill.cornerRadius = 0.75
        fill.anchorPoint = .zero
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func update(share new: Double, color newColor: Color, glide: Bool) {
        color = newColor
        paint()
        // Before the first layout there is no width to tell a change by: keep the share for layout() to place.
        guard bounds.width == 0 || abs(new - share) * bounds.width >= 0.5 else { return }
        share = new
        place(duration: glide && bounds.width > 0 ? 0.5 : 0)
    }

    override func layout() {
        super.layout()
        place(duration: 0)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    private func place(duration: TimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = bounds
        fill.position = .zero
        fill.bounds.size.height = bounds.height
        CATransaction.commit()
        CATransaction.begin()
        CATransaction.setDisableActions(duration == 0)
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        fill.bounds.size.width = bounds.width * CGFloat(share)
        CATransaction.commit()
    }

    private func paint() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            track.backgroundColor = NSColor(Theme.track).cgColor
            fill.backgroundColor = NSColor(color).cgColor
        }
        CATransaction.commit()
    }
}
