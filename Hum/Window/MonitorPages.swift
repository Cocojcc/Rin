import SwiftUI

private func nearest(_ points: [ChartPoint], _ date: Date) -> Int? {
    points.indices.min { abs(points[$0].date.timeIntervalSince(date)) < abs(points[$1].date.timeIntervalSince(date)) }
}

private func timeLabel(_ date: Date, _ range: TimeRange) -> String {
    range.seconds > 3600 ? Format.dayAndTime(date) : Format.time(date)
}

private func percentNumber(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))" }

private func grouped(_ n: Int) -> String { n.formatted(.number.grouping(.automatic)) }

/// One-line hover readout for a single metric.
private func hoverLine(_ metric: Metric, _ range: TimeRange, _ date: Date, _ text: (Double) -> String) -> [String] {
    let pts = Monitor.shared.history.points(metric, range: range)
    guard let i = nearest(pts, date) else { return [] }
    return [timeLabel(pts[i].date, range) + "\t" + text(pts[i].value)]
}

/// Section title with a panel underneath that fills the height of its row.
struct Section<Content: View>: View {
    var title: String
    var right: String? = nil
    var rightColor: Color = Theme.sub
    /// A process list's "全部" link to the Processes page, sorted by this.
    var link: ProcessSort? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).ui(13, 500).foregroundStyle(Theme.sub).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if let right { Text(right).ui(12).foregroundStyle(rightColor).lineLimit(1) }
                    if let link { AllProcessesLink(sort: link) }
                }
            }
            .frame(minHeight: 18)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            content
        }
    }
}

private struct StretchCardsKey: EnvironmentKey { static let defaultValue = false }

private extension EnvironmentValues {
    var stretchCards: Bool {
        get { self[StretchCardsKey.self] }
        set { self[StretchCardsKey.self] = newValue }
    }
}

/// Panel with 14 pt padding; side by side it stretches to the tallest card in its row.
private struct Card<Content: View>: View {
    var padding = EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
    @ViewBuilder var content: Content
    @Environment(\.stretchCards) private var stretch

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: stretch ? .infinity : nil, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
    }
}

/// A monitor page: the module header, then its content.
struct MonitorPageLayout<Content: View>: View {
    let module: Module
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ModuleHeader(module: module)
            content
        }
    }
}

/// Two (or more) sections side by side with equal heights.
private struct SideBySide<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) { content }
            .environment(\.stretchCards, true)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Overview

private struct SpanKey: LayoutValueKey { static let defaultValue = 1 }

/// CSS-like auto-fill grid: as many columns of at least `minWidth` as fit, rows as tall as their
/// tallest card (at least `minHeight`), children may span columns.
struct CardGrid: Layout {
    var minWidth: CGFloat = 176
    var spacing: CGFloat = 12
    var minHeight: CGFloat = 146
    /// Three columns that grow and shrink with the window; only when three would be narrower
    /// than `minWidth` does it drop to two, and never fewer.
    var columns = 3
    var minColumns = 2

    private struct Item { var index: Int; var column: Int; var span: Int }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (rows: [[Item]], heights: [CGFloat], column: CGFloat) {
        let fit = (width + spacing) / (minWidth + spacing)
        let columns = fit.isFinite ? min(self.columns, max(minColumns, Int(fit))) : self.columns
        let columnWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var rows: [[Item]] = [[]]
        var col = 0
        for (i, view) in subviews.enumerated() {
            let span = min(view[SpanKey.self], columns)
            if col + span > columns { rows.append([]); col = 0 }
            rows[rows.count - 1].append(Item(index: i, column: col, span: span))
            col += span
        }
        let heights = rows.map { row in
            row.map { item -> CGFloat in
                let w = columnWidth * CGFloat(item.span) + spacing * CGFloat(item.span - 1)
                return subviews[item.index].sizeThatFits(ProposedViewSize(width: w, height: nil)).height
            }.max().map { max($0, minHeight) } ?? 0
        }
        return (rows, heights, columnWidth)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Unspecified or unbounded proposals (measuring the ideal size) get the full columns.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? minWidth * CGFloat(columns) + spacing * CGFloat(columns - 1)
        let layout = arrange(width, subviews)
        let height = layout.heights.reduce(0, +) + spacing * CGFloat(max(0, layout.heights.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(bounds.width, subviews)
        var y = bounds.minY
        for (r, row) in layout.rows.enumerated() {
            for item in row {
                let x = bounds.minX + CGFloat(item.column) * (layout.column + spacing)
                let w = layout.column * CGFloat(item.span) + spacing * CGFloat(item.span - 1)
                subviews[item.index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                           proposal: ProposedViewSize(width: w, height: layout.heights[r]))
            }
            y += layout.heights[r] + spacing
        }
    }
}

struct OverviewPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    var alerts = Alerts.shared

    var body: some View {
        let s = monitor.snapshot
        let unit = settings.prefs.general.temperatureUnit
        let _ = monitor.tick
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: L10n.Overview.title)
            status
            CardGrid(spacing: 10) {
                cpuCard(s, unit)
                memoryCard(s)
                networkCard(s)
                diskCard(s)
                batteryCard(s)
                sensorsCard(s, unit)
                peakCard()
                gpuCard(s, unit)
                bluetoothCard(s)
            }
        }
    }

    /// A firing alert takes the status strip's place until it clears or is muted.
    @ViewBuilder private var status: some View {
        if let event = alerts.current {
            AlertBanner(event: event)
        } else {
            healthStrip
        }
    }

    private var healthStrip: some View {
        let issues = alerts.active.count
        return HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(issues == 0 ? Theme.ok : Theme.warn).frame(width: 8, height: 8)
                Text(issues == 0 ? L10n.Overview.allGood : L10n.Overview.issues(issues)).ui(15, 500)
            }
            .foregroundStyle(issues == 0 ? Theme.ok : Theme.warn)
            Spacer(minLength: 0)
            Text(Format.uptime(since: SystemInfo.bootTime)).ui(12).foregroundStyle(Theme.sub)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .accessibilityElement(children: .combine)
    }

    // MARK: Cards

    /// "超过 90%" in red on a card whose usage rule is firing.
    private func overLimit(_ rule: Alerts.Rule) -> (String, Color)? {
        guard let e = alerts.firing(rule) else { return nil }
        return (L10n.Alerts.overLimit(Format.percent(e.limit / 100)), Theme.danger)
    }

    private func cpuCard(_ s: Snapshot, _ unit: TemperatureUnit) -> some View {
        OverviewCard(module: .cpu, status: overLimit(.cpu)) {
            ringRow(PageRing(segments: [.init(fraction: s.cpu.system, color: Theme.sys), .init(fraction: s.cpu.user, color: Theme.cpu)],
                             size: 56, lineWidth: 4, text: Format.percent(s.cpu.total))) {
                pair(L10n.Panel.user, Format.percent(s.cpu.user), swatch: LegendItem(color: Theme.cpu, label: "", shape: .square))
                pair(L10n.Panel.system, Format.percent(s.cpu.system), swatch: LegendItem(color: Theme.sys, label: "", shape: .square))
                pair(L10n.Monitor.idle, Format.percent(max(0, 1 - s.cpu.total)), swatch: LegendItem(color: Theme.faint, label: "", shape: .outline))
            }
        } footer: {
            processes(Array(s.processes.byCPU.prefix(2))) { Format.percentValue($0.cpu) }
        }
    }

    private func memoryCard(_ s: Snapshot) -> some View {
        let m = s.memory
        let pr = PanelText.pressure(m.pressure)
        let label = m.pressure == .normal ? L10n.Overview.pressureNormal : m.pressure == .warning ? L10n.Overview.pressureWarning : L10n.Overview.pressureCritical
        return OverviewCard(module: .memory, status: (label, pr.1)) {
            ringRow(PageRing(segments: MemoryRing.segments(m), size: 56, lineWidth: 4, text: Format.percent(m.usedFraction))) {
                pair(L10n.Memory.used, Format.memory(m.used))
                pair(L10n.Monitor.ofTotal(Format.memory(m.total)), nil)
                pair(L10n.Memory.swap, Format.memory(m.swapUsed))
            }
        } footer: {
            processes(Array(s.processes.byMemory.prefix(2))) { Format.memory($0.memory) }
        }
    }

    private func networkCard(_ s: Snapshot) -> some View {
        let n = s.network
        let speed = settings.prefs.network.speedUnit
        return OverviewCard(module: .network, status: (networkLine(n), n.connected ? Theme.ok : Theme.sub)) {
            HStack(alignment: .top, spacing: 12) {
                rate(MenuBarText.downArrow, Theme.down, L10n.Panel.download, n.connected ? Format.rate(n.down, unit: speed) : L10n.Common.dash)
                rate(MenuBarText.upArrow, Theme.up, L10n.Panel.upload, n.connected ? Format.rate(n.up, unit: speed) : L10n.Common.dash)
            }
            MirrorSparkline(down: monitor.history.latest(.netDown, seconds: 120), up: monitor.history.latest(.netUp, seconds: 120))
                .frame(height: 22)
        } footer: {
            processes(Array(s.processes.byNetwork.prefix(2))) { MenuBarText.downArrow + " " + Format.rate($0.netDown, unit: speed) }
        }
    }

    private func diskCard(_ s: Snapshot) -> some View {
        let root = s.disk.root
        let other = s.disk.volumes.first { $0.id != root?.id }
        let health: (String, Color)? = s.disk.health.map { $0.ok ? (L10n.Overview.diskHealthy, Theme.ok) : (L10n.Monitor.healthService, Theme.danger) }
        return OverviewCard(module: .disk, status: health) {
            ringRow(PageRing(segments: [.init(fraction: root?.usedFraction ?? 0, color: Theme.disk)], size: 56, lineWidth: 4,
                             text: Format.percent(root?.usedFraction ?? 0))) {
                Text(root?.name ?? L10n.Common.dash).ui(12, 500).lineLimit(1)
                pair(L10n.Disk.free, Format.storage(root?.available ?? 0))
                pair(L10n.Monitor.ofTotal(Format.storage(root?.total ?? 0)), nil)
            }
        } footer: {
            if let other {
                footerText(other.name + " · ", Format.marker + " " + L10n.Disk.free, Format.storage(other.available))
            } else {
                footerText(L10n.Panel.readWriteShort(Format.rate(s.disk.read), Format.rate(s.disk.write)))
            }
        }
    }

    private func batteryCard(_ s: Snapshot) -> some View {
        let b = s.battery
        let state: (String, Color)? = b.hasBattery ? (PanelText.batteryState(b), b.onAC ? Theme.ok : Theme.sub) : nil
        return OverviewCard(module: .battery, status: state) {
            if b.hasBattery {
                ringRow(PageRing(segments: [.init(fraction: b.level, color: BatteryColors.fill(b))], size: 56, lineWidth: 4, text: Format.percent(b.level))) {
                    if b.isCharging, let m = b.minutesToFull {
                        pair(L10n.Battery.untilFull(BatteryTime.text(m)), nil)
                    } else if !b.onAC, let m = b.minutesToEmpty {
                        pair(L10n.Battery.remaining(BatteryTime.text(m)), nil)
                    }
                    if b.onAC, let w = b.adapterWatts {
                        pair(L10n.Monitor.powerSource, "\(w) W")
                    } else if let w = b.power {
                        pair(L10n.Panel.power, Format.watts(abs(w)))
                    }
                }
            } else {
                Text(L10n.Battery.noBattery).ui(12).foregroundStyle(Theme.sub)
            }
        } footer: {
            if b.hasBattery {
                HStack(spacing: 0) {
                    footerText("", L10n.Battery.health + " " + Format.marker, b.health.map(Format.percent) ?? L10n.Common.dash)
                    if let c = b.cycles { footerText(" · ", L10n.Overview.cycles(Format.marker), "\(c)") }
                }
            }
        }
    }

    private func sensorsCard(_ s: Snapshot, _ unit: TemperatureUnit) -> some View {
        let t = s.sensors
        let thermal = ThermalText.color(t.thermal)
        let fan = t.fans.first.map { L10n.Overview.fan + " " + Format.rpm($0.rpm) } ?? L10n.Overview.noFan
        let footer = [fan, t.systemPower.map(Format.watts)].compactMap { $0 }.joined(separator: " · ")
        return OverviewCard(module: .sensors, status: (L10n.Overview.thermal(t.thermal.rawValue), thermal)) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(t.cpuAverage.map { Format.temperatureNumber($0, unit: unit) + "°" } ?? L10n.Common.dash).ui(24, 500).kerning(-0.48)
                Text(L10n.Overview.cpuTemp).ui(12).foregroundStyle(Theme.sub)
            }
            LevelSegments(level: t.thermal.rawValue, color: thermal, height: 3, gap: 3)
        } footer: {
            footerText(footer)
        }
    }

    private func gpuCard(_ s: Snapshot, _ unit: TemperatureUnit) -> some View {
        let g = s.gpu
        return OverviewCard(module: .gpu, status: overLimit(.gpu)) {
            ringRow(PageRing(segments: [.init(fraction: g.utilization, color: Theme.gpu)], size: 56, lineWidth: 4, text: Format.percent(g.utilization))) {
                pair(L10n.Panel.vram, Format.memory(g.memoryUsed))
                pair(L10n.Panel.frequency, g.frequencyMHz.map(Format.frequency) ?? L10n.Common.dash)
                pair(L10n.Panel.temperature, g.temperature.map { Format.temperature($0, unit: unit, showUnit: true) } ?? L10n.Common.dash)
            }
        } footer: {
            footerText("", L10n.Overview.videoDecode(Format.marker), MediaText.state(g.decodeWatts))
        }
    }

    /// The busiest moments of the last 24 hours; opens the CPU page's lookback.
    private func peakCard() -> some View {
        let peaks = monitor.history.cpuPeaks()
        return OverviewCard(module: .cpu, title: L10n.Overview.cpuPeaks, icon: Icons.activity, status: nil,
                            action: { CPUPage.requestedRange = .h24; Navigator.shared.page = .monitor(.cpu) }) {
            PeakSparkline(points: monitor.history.points(.cpu, range: .h24), peaks: peaks)
                .frame(height: 24)
                .accessibilityLabel(L10n.Monitor.cpuChartA11y(TimeRange.h24.title))
        } footer: {
            VStack(alignment: .leading, spacing: 3) {
                if peaks.isEmpty {
                    Text(L10n.Monitor.noPeaks).ui(12).foregroundStyle(Theme.sub).frame(height: 18)
                }
                ForEach(peaks) { p in
                    HStack(spacing: 6) {
                        Text(Format.percent(p.value / 100)).fontWeight(.medium)
                        Text(p.top.first?.name ?? L10n.Common.dash).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                        Text(Format.shortDayAndTime(p.date)).foregroundStyle(Theme.sub).fixedSize()
                    }
                    .ui(12)
                    .frame(height: 18)
                }
            }
        }
    }

    /// Connected devices, lowest first; the status says how many are low.
    private func bluetoothCard(_ s: Snapshot) -> some View {
        let low = MenuBarText.lowDevices(s, settings.prefs).count
        // The devices read down from the title, rather than sitting at the bottom of the card.
        return OverviewCard(module: .bluetooth, status: low > 0 ? (L10n.Bluetooth.lowCount(low), Theme.danger) : nil) {
            BluetoothOverviewRows(snapshot: s, prefs: settings.prefs)
        } footer: {
            EmptyView()
        }
    }

    // MARK: Pieces

    private func ringRow<Lines: View>(_ ring: PageRing, @ViewBuilder lines: () -> Lines) -> some View {
        HStack(spacing: 12) {
            ring
            VStack(alignment: .leading, spacing: 3) { lines() }
        }
    }

    /// "用户 15%": grey label, value in text color, optional color square in front.
    private func pair(_ label: String, _ value: String?, swatch: LegendItem? = nil) -> some View {
        HStack(spacing: 6) {
            if let swatch { swatch.swatch }
            Text(label).foregroundStyle(Theme.sub)
            // The number stays whole; a long label gives way first.
            if let value { Text(value).fontWeight(.medium).foregroundStyle(Theme.text).layoutPriority(1) }
        }
        .ui(12)
        .lineLimit(1)
    }

    private func rate(_ arrow: String, _ color: Color, _ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(arrow).ui(12, 600).foregroundStyle(color)
                Text(label).ui(12).foregroundStyle(Theme.sub)
            }
            Text(value).ui(15, 500).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Grey footer line; with a value, the template's `Format.marker` becomes that value in
    /// text color ("T7 Shield · 590 GB 可用", "循环 214 次").
    private func footerText(_ prefix: String, _ template: String, _ value: String) -> some View {
        let parts = template.components(separatedBy: Format.marker)
        var text = Text(prefix + parts[0]).foregroundColor(Theme.sub)
        if parts.count > 1 {
            text = text + Text(value).foregroundColor(Theme.text).fontWeight(.medium) + Text(parts[1...].joined()).foregroundColor(Theme.sub)
        }
        return text.ui(12).lineLimit(1).frame(height: 16)
    }

    private func footerText(_ line: String) -> some View { footerText("", line, "") }

    private func processes(_ list: [ProcessUsage], value: @escaping (ProcessUsage) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if list.isEmpty {
                Text(L10n.Panel.noProcesses).ui(12).foregroundStyle(Theme.faint).frame(height: 18)
            }
            ForEach(list) { p in
                HStack(spacing: 8) {
                    ProcessIcon(process: p, size: 18)
                    Text(p.name).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                    Text(value(p)).fontWeight(.medium).lineLimit(1)
                }
                .ui(12)
                .frame(height: 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .overlay(alignment: .top) { Hairline() }
    }

    private func networkLine(_ n: NetworkSample) -> String {
        guard n.connected else { return L10n.Overview.disconnected }
        switch n.kind {
        case .wifi: return L10n.Overview.wifiConnected
        case .ethernet: return L10n.Overview.ethernetConnected
        default: return "\(PanelText.kindName(n.kind)) · \(L10n.Overview.connected)"
        }
    }
}

/// An overview card: icon and title, a status on the right, content, and a footer pinned to
/// the bottom. The whole card opens its monitor page and tints under the pointer.
private struct OverviewCard<Content: View, Footer: View>: View {
    let module: Module
    var title: String? = nil
    var icon: String? = nil
    var status: (String, Color)?
    var action: (() -> Void)? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    @State private var hovering = false

    init(module: Module, title: String? = nil, icon: String? = nil, status: (String, Color)?,
         action: (() -> Void)? = nil, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.module = module
        self.title = title
        self.icon = icon
        self.status = status
        self.action = action
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        Button {
            if let action { action() } else { Navigator.shared.page = .monitor(module) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            LineIcon(d: icon ?? Icons.module(module), size: 16, lineWidth: 1.5)
                            Text(title ?? module.title).ui(13, 500)
                        }
                        .foregroundStyle(Theme.sub)
                        Spacer(minLength: 0)
                        if let status { Text(status.0).ui(12, 500).foregroundStyle(status.1).lineLimit(1) }
                    }
                    .frame(height: 18)
                    content
                }
                Spacer(minLength: 12)
                footer
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(hovering ? Theme.well : Theme.panel))
            .hoverAnimation(hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityHint(L10n.Panel.openMonitor(module.title))
    }
}

/// 24 hours of CPU use as a small area chart with dots on the peaks.
struct PeakSparkline: View {
    var points: [ChartPoint]
    var peaks: [PeakMarker]

    var body: some View {
        Canvas { ctx, size in
            let end = Date(), start = end.addingTimeInterval(-86_400)
            let x = { (d: Date) in size.width * CGFloat(d.timeIntervalSince(start) / 86_400) }
            let y = { (v: Double) in size.height - CGFloat(min(100, max(0, v)) / 100) * (size.height - 3) }
            guard let first = points.first, let last = points.last else { return }
            var line = Path()
            for (i, p) in points.enumerated() {
                let pt = CGPoint(x: x(p.date), y: y(p.value))
                if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
            }
            var area = line
            area.addLine(to: CGPoint(x: x(last.date), y: size.height))
            area.addLine(to: CGPoint(x: x(first.date), y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .color(Theme.cpu.opacity(0.13)))
            ctx.stroke(line, with: .color(Theme.cpu), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            for p in peaks {
                let c = CGPoint(x: x(p.date), y: y(p.value))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(Theme.raised))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(Theme.cpu))
            }
        }
    }
}

/// Download above a center line, upload below, each scaled to its own peak (overview card).
struct MirrorSparkline: View {
    var down: [Double]
    var up: [Double]
    var minCount = 60

    var body: some View {
        Canvas { ctx, size in
            let mid = size.height / 2
            draw(&ctx, down, size: size, sign: -1, color: Theme.down, fill: 0.16)
            draw(&ctx, up, size: size, sign: 1, color: Theme.up, fill: 0.2)
            var center = Path()
            center.move(to: CGPoint(x: 0, y: mid))
            center.addLine(to: CGPoint(x: size.width, y: mid))
            ctx.stroke(center, with: .color(Theme.cross), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, _ values: [Double], size: CGSize, sign: CGFloat, color: Color, fill: Double) {
        guard !values.isEmpty else { return }
        let peak = max(values.max() ?? 0, 10_000)
        let mid = size.height / 2
        let count = max(values.count, minCount)
        let step = size.width / CGFloat(max(count - 1, 1))
        let offset = CGFloat(count - values.count) * step
        var line = Path()
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: offset + CGFloat(i) * step, y: mid + sign * CGFloat(min(1, v / peak)) * (mid - 1))
            if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
        }
        var area = line
        area.addLine(to: CGPoint(x: offset + CGFloat(values.count - 1) * step, y: mid))
        area.addLine(to: CGPoint(x: offset, y: mid))
        area.closeSubpath()
        ctx.fill(area, with: .color(color.opacity(fill)))
        ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }
}

enum MemoryRing {
    /// App, wired and compressed memory around the ring.
    static func segments(_ m: MemorySample) -> [Ring.Segment] {
        let total = max(Double(m.total), 1)
        return [
            .init(fraction: Double(m.app) / total, color: Theme.mem),
            .init(fraction: Double(m.wired) / total, color: Theme.mem, opacity: 0.6),
            .init(fraction: Double(m.compressed) / total, color: Theme.mem, opacity: 0.35),
        ]
    }
}

enum ThermalText {
    static func color(_ t: ThermalLevel) -> Color {
        switch t {
        case .nominal: return Theme.ok
        case .fair: return Theme.warn
        case .serious, .critical: return Theme.danger
        }
    }
}

/// Media engine power, shown as active/idle with the wattage (utilization isn't exposed).
enum MediaText {
    static func state(_ watts: Double?) -> String {
        guard let watts else { return L10n.Common.dash }
        return watts < 0.01 ? L10n.Monitor.idleState : Format.watts(watts)
    }
}

enum BatteryColors {
    static func fill(_ b: BatterySample) -> Color {
        b.level <= 0.2 && !b.onAC ? Theme.danger : Theme.bat
    }
}

/// The big battery (96 × 44 design units), bolt knocked out while charging.
struct LargeBattery: View {
    var level: Double
    var charging: Bool
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 96
            ctx.stroke(Path(roundedRect: CGRect(x: 0.75 * s, y: 0.75 * s, width: 86.5 * s, height: 42.5 * s), cornerRadius: 11 * s),
                       with: .color(Theme.faint), lineWidth: 1.5 * s)
            let width = max(4, 80 * min(1, max(0, level)))
            ctx.fill(Path(roundedRect: CGRect(x: 4 * s, y: 4 * s, width: width * s, height: 36 * s), cornerRadius: 8 * s), with: .color(color))
            var cap = Path()
            cap.move(to: CGPoint(x: 92 * s, y: 16 * s))
            cap.addLine(to: CGPoint(x: 92 * s, y: 28 * s))
            ctx.stroke(cap, with: .color(Theme.faint), style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))
            if charging {
                let bolt = SVGShape(d: "M46.5 11L38 23.5h6.5L42 33l9.5-13H45z", viewBox: CGSize(width: 96, height: 44)).path(in: CGRect(origin: .zero, size: size))
                ctx.fill(bolt, with: .color(Theme.onInk))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - CPU

struct CPUPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    @State private var range: TimeRange = CPUPage.takeRequestedRange()

    /// Set before opening the page to start on another range (the overview's peaks card).
    static var requestedRange: TimeRange?

    private static func takeRequestedRange() -> TimeRange {
        defer { requestedRange = nil }
        return requestedRange ?? .m5
    }
    @State private var selectedPeak: Date?

    var body: some View {
        let s = monitor.snapshot
        let history = monitor.history
        let _ = monitor.tick
        let lookback = range == .h24
        let peaks = history.cpuPeaks()
        let selected = selectedPeak.flatMap { d in peaks.first { $0.date == d } } ?? peaks.first

        MonitorPageLayout(module: .cpu) {
            if !lookback { summary(s) }
            VStack(alignment: .leading, spacing: 12) {
                RangeRow {
                    RangeControl(range: $range)
                    if lookback {
                        WellButton(title: L10n.Monitor.backToNow, height: 30, radius: 9, fontSize: 12) { range = .m5 }
                    }
                } trailing: {
                    if !lookback, let top = peaks.first { peakLink(top) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    ChartPanel(height: lookback ? 150 : 76, alert: .cpu, alertLine: settings.prefs.alerts.cpuThreshold / 100) {
                        MonitorChart(
                            series: [
                                ChartSeries(id: "total", points: history.points(.cpu, range: range), color: Theme.cpu, fill: lookback ? 0.13 : 0.16, lineWidth: lookback ? 1.5 : 2),
                                ChartSeries(id: "system", points: lookback ? [] : history.points(.cpuSystem, range: range), color: Theme.sys, fill: 0.24, lineWidth: 1.5),
                            ],
                            range: range, maxValue: 100, markers: lookback ? peaks : [], selectedMarker: lookback ? selected?.date : nil, markerColor: Theme.cpu,
                            hoverText: { hoverLines($0) },
                            onTap: { date in
                                if let nearest = peaks.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }),
                                   abs(nearest.date.timeIntervalSince(date)) < range.seconds / 30 { selectedPeak = nearest.date }
                            },
                            pinnedTip: lookback ? selected.map { peakTip($0) } : nil,
                            threshold: Alerts.Rule.cpu.isOn(settings.prefs) ? (settings.prefs.alerts.cpuThreshold, Theme.danger) : nil
                        )
                        .accessibilityLabel(L10n.Monitor.cpuChartA11y(range.title))
                    }
                    if lookback || range == .d7 { TimeAxisLabels(range: range) }
                }
            }

            if lookback {
                Section(title: L10n.Monitor.peaks24h) {
                    VStack(spacing: 0) {
                        if peaks.isEmpty {
                            Text(L10n.Monitor.noPeaks).ui(13).foregroundStyle(Theme.faint)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 46)
                        }
                        ForEach(peaks) { peak in
                            PeakRow(peak: peak, selected: peak.date == selected?.date) { selectedPeak = peak.date }
                        }
                    }
                    .slidingThumb(selected?.date) { GlassThumb(cornerRadius: 14) }
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
                }
                Section(title: selected.map { L10n.Monitor.peakTop(Format.dayAndTime($0.date)) } ?? L10n.Monitor.peakTopNone) {
                    PeakProcessList(processes: selected?.top ?? [])
                }
            } else {
                Section(title: L10n.Panel.cores, right: L10n.Monitor.coreTotal(s.cpu.perCore.count)) {
                    CoreBarsPanel(cpu: s.cpu)
                }
                SideBySide {
                    Section(title: L10n.Panel.loadAverage) {
                        Card(padding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)) {
                            ValueLine(label: L10n.Monitor.load1, value: Format.load(s.cpu.load.0), labelColor: Theme.sub, height: 22)
                            ValueLine(label: L10n.Monitor.load5, value: Format.load(s.cpu.load.1), labelColor: Theme.sub, height: 22)
                            ValueLine(label: L10n.Monitor.load15, value: Format.load(s.cpu.load.2), labelColor: Theme.sub, height: 22)
                        }
                    }
                    Section(title: L10n.Panel.frequency) {
                        Card(padding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)) {
                            ValueLine(label: L10n.Monitor.allCores, value: s.cpu.frequencyMHz.map(Format.frequency) ?? L10n.Common.dash, labelColor: Theme.sub, height: 22)
                            if SystemInfo.efficiencyCores > 0 {
                                ValueLine(label: L10n.Monitor.performanceCores, value: s.cpu.performanceMHz.map(Format.frequency) ?? L10n.Common.dash, labelColor: Theme.sub, height: 22)
                                ValueLine(label: L10n.Monitor.efficiencyCores, value: s.cpu.efficiencyMHz.map(Format.frequency) ?? L10n.Common.dash, labelColor: Theme.sub, height: 22)
                            }
                        }
                    }
                }
                Section(title: L10n.Monitor.topCPU, right: L10n.Monitor.processThreads(grouped(s.processes.processCount), grouped(s.processes.threadCount)), link: .cpu) {
                    let list = Array(s.processes.byCPU.prefix(4))
                    let peak = max(list.map(\.cpu).max() ?? 1, 0.0001)
                    ProcessTable(processes: list, fraction: { $0.cpu / peak }, color: Theme.cpu,
                                 value: { Format.percentValue($0.cpu) }, rowHeight: 28)
                }
            }
        }
    }

    private func summary(_ s: Snapshot) -> some View {
        let unit = settings.prefs.general.temperatureUnit
        let right = [s.sensors.cpuAverage.map { Format.temperature($0, unit: unit, showUnit: true) }, s.sensors.cpuPower.map(Format.watts)].compactMap { $0 }
        let idle = max(0, 1 - s.cpu.total)
        return HStack(spacing: 20) {
            PageRing(segments: [.init(fraction: s.cpu.system, color: Theme.sys), .init(fraction: s.cpu.user, color: Theme.cpu)],
                      size: 64, lineWidth: 5, text: Format.percent(s.cpu.total), textSize: 20)
            VStack(alignment: .leading, spacing: 12) {
                StackedBar(parts: [(s.cpu.system, Theme.sys), (s.cpu.user, Theme.cpu), (idle, Theme.track)])
                HStack(spacing: 20) {
                    legendValue(LegendItem(color: Theme.sys, label: L10n.Panel.system, shape: .square), Format.percent(s.cpu.system))
                    legendValue(LegendItem(color: Theme.cpu, label: L10n.Panel.user, shape: .square), Format.percent(s.cpu.user))
                    legendValue(LegendItem(color: Theme.faint, label: L10n.Monitor.idle, shape: .outline), Format.percent(idle))
                    Spacer(minLength: 0)
                    if !right.isEmpty { Text(right.joined(separator: " · ")).ui(12).foregroundStyle(Theme.sub).lineLimit(1).fixedSize() }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .accessibilityElement(children: .combine)
    }

    private func legendValue(_ item: LegendItem, _ value: String) -> some View {
        HStack(spacing: 6) {
            item.swatch
            Text(item.label).ui(12).foregroundStyle(Theme.sub)
            Text(value).ui(13, 500)
        }
        .fixedSize()
    }

    private func peakLink(_ peak: PeakMarker) -> some View {
        Button {
            selectedPeak = peak.date
            range = .h24
        } label: {
            HStack(spacing: 6) {
                Text(L10n.Monitor.peak24h).ui(12).foregroundStyle(Theme.sub)
                Text(Format.percent(peak.value / 100)).ui(13, 500)
                Text(Format.dayAndTime(peak.date)).ui(12).foregroundStyle(Theme.sub)
                LineIcon(d: "M1 1l4 4-4 4", width: 6, height: 10, viewBox: CGSize(width: 6, height: 10), lineWidth: 1.5)
                    .foregroundStyle(Theme.sub)
            }
            .frame(height: 28)
            .padding(.trailing, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func peakTip(_ p: PeakMarker) -> [String] {
        [Format.dayAndTime(p.date) + "\t" + Format.percent(p.value / 100)] + p.top.prefix(2).map { "\($0.name)\t\(Format.percent($0.cpu / 100))" }
    }

    private func hoverLines(_ date: Date) -> [String] {
        let history = monitor.history
        if range == .h24 || range == .d7, let b = history.bucket(near: date) {
            let cpu = Double(b.max[Metric.cpu.rawValue])
            return [Format.dayAndTime(Date(timeIntervalSince1970: b.start)) + "\t" + Format.percent(cpu / 100)]
                + b.top.prefix(3).map { "\($0.name)\t\(Format.percent($0.cpu / 100))" }
        }
        let pts = history.points(.cpu, range: range)
        let sys = history.points(.cpuSystem, range: range)
        guard let i = nearest(pts, date) else { return [] }
        var lines = [Format.time(pts[i].date) + "\t" + Format.percent(pts[i].value / 100)]
        if i < sys.count {
            lines.append(L10n.Panel.system + "\t" + Format.percent(sys[i].value / 100))
            lines.append(L10n.Panel.user + "\t" + Format.percent(max(0, pts[i].value - sys[i].value) / 100))
        }
        return lines
    }
}

/// One bar per core (system from the bottom, user above), performance and efficiency cores
/// side by side with a divider; every gap is equal and the divider takes two.
struct CoreBarsPanel: View {
    var cpu: CPUSample

    var body: some View {
        let groups = groupsOf(cpu)
        CoreBarsLayout(counts: groups.map(\.indices.count)) {
            ForEach(groups.indices, id: \.self) { g in
                ForEach(Array(groups[g].indices.enumerated()), id: \.element) { n, i in
                    bar(i).help(groups[g].tip(n + 1, Format.percent(cpu.perCore[i]), Format.percent(system(i))))
                }
            }
            ForEach(1..<max(groups.count, 1), id: \.self) { _ in
                Rectangle().fill(Theme.line).frame(width: 1, height: 40)
            }
            ForEach(groups.indices, id: \.self) { g in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(groups[g].label).foregroundStyle(Theme.sub)
                    Text(Format.percent(groups[g].average)).fontWeight(.medium)
                }
                .ui(12)
                .lineLimit(1)
                .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(groups.map { g in
            L10n.Monitor.coresA11y(g.label, g.indices.map { Format.percent(cpu.perCore[$0]) }.joined(separator: L10n.A11y.separator))
        }.joined(separator: L10n.A11y.separator))
    }

    private func system(_ i: Int) -> Double { i < cpu.perCoreSystem.count ? cpu.perCoreSystem[i] : 0 }
    private func user(_ i: Int) -> Double { i < cpu.perCoreUser.count ? cpu.perCoreUser[i] : max(0, cpu.perCore[i] - system(i)) }

    private func bar(_ i: Int) -> some View {
        let sys = min(1, max(0, system(i))) * CoreBarsLayout.height
        let usr = min(1, max(0, user(i))) * CoreBarsLayout.height
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2, style: .continuous)
                .fill(Theme.cpu)
                .frame(height: max(0, usr - 1))
            Color.clear.frame(height: usr > 0 ? 1 : 0)
            Rectangle().fill(Theme.sys).frame(height: sys)
        }
        .background(Theme.track)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private struct Group {
        var label: String
        var indices: [Int]
        var average: Double
        var tip: (Int, String, String) -> String
    }

    private func groupsOf(_ cpu: CPUSample) -> [Group] {
        let isE = { (i: Int) in i < cpu.coreKinds.count && cpu.coreKinds[i] == .efficiency }
        let p = cpu.perCore.indices.filter { !isE($0) }
        let e = cpu.perCore.indices.filter { isE($0) }
        let avg = { (ix: [Int]) in ix.isEmpty ? 0 : ix.map { cpu.perCore[$0] }.reduce(0, +) / Double(ix.count) }
        if e.isEmpty { return [Group(label: L10n.Monitor.coreGroup(p.count), indices: p, average: avg(p), tip: L10n.Monitor.coreTip)] }
        return [
            Group(label: L10n.Monitor.performanceGroup(p.count), indices: p, average: avg(p), tip: L10n.Monitor.pCoreTip),
            Group(label: L10n.Monitor.efficiencyGroup(e.count), indices: e, average: avg(e), tip: L10n.Monitor.eCoreTip),
        ]
    }
}

/// Lays out the cores panel. Subviews come in order: every bar, the dividers between groups,
/// then one label per group, placed under the group's first bar.
struct CoreBarsLayout: Layout {
    var counts: [Int]
    static let height: CGFloat = 40
    private let barWidth: CGFloat = 10
    private let minBar: CGFloat = 4
    private let minGap: CGFloat = 2
    private let labelGap: CGFloat = 8

    /// Bar width and gap for a row this wide.
    private func metrics(_ width: CGFloat) -> (bar: CGFloat, gap: CGFloat) {
        let bars = CGFloat(counts.reduce(0, +))
        // Gaps inside groups, plus two for each divider.
        let gaps = CGFloat(counts.map { max($0 - 1, 0) }.reduce(0, +) + 2 * max(counts.count - 1, 0))
        guard bars > 0 else { return (barWidth, minGap) }
        let gap = gaps > 0 ? (width - bars * barWidth) / gaps : 0
        if gap >= minGap { return (barWidth, gap) }
        return (max(minBar, (width - gaps * minGap) / bars), minGap)
    }

    private func labelHeight(_ subviews: Subviews) -> CGFloat {
        let bars = counts.reduce(0, +), dividers = max(counts.count - 1, 0)
        return subviews.dropFirst(bars + dividers).map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 400
        return CGSize(width: width, height: Self.height + labelGap + labelHeight(subviews))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let m = metrics(bounds.width)
        let bars = counts.reduce(0, +)
        var x = bounds.minX
        var index = 0
        var starts: [CGFloat] = []
        for (g, count) in counts.enumerated() {
            starts.append(x)
            for _ in 0..<count {
                guard index < subviews.count else { return }
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: m.bar, height: Self.height))
                x += m.bar + m.gap
                index += 1
            }
            if g < counts.count - 1 {
                // The divider sits centered in a double gap.
                let divider = bars + g
                if divider < subviews.count {
                    subviews[divider].place(at: CGPoint(x: x, y: bounds.minY), anchor: .top,
                                            proposal: ProposedViewSize(width: 1, height: Self.height))
                }
                x += m.gap
            }
        }
        let labels = subviews.dropFirst(bars + max(counts.count - 1, 0))
        for (label, start) in zip(labels, starts) {
            label.place(at: CGPoint(x: start, y: bounds.minY + Self.height + labelGap), anchor: .topLeading, proposal: .unspecified)
        }
    }
}

/// Two children on a four-column grid: the first takes one column, the second the other three
/// (the connection log), both centered vertically.
struct QuarterSplit: Layout {
    var gap: CGFloat = 12

    private func widths(_ total: CGFloat) -> (CGFloat, CGFloat) {
        let column = (total - gap * 3) / 4
        return (column, column * 3 + gap * 2)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 400
        let w = widths(width)
        let heights = zip(subviews, [w.0, w.1]).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = widths(bounds.width)
        var x = bounds.minX
        for (view, width) in zip(subviews, [w.0, w.1]) {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            view.place(at: CGPoint(x: x, y: bounds.midY - size.height / 2), anchor: .topLeading,
                       proposal: ProposedViewSize(width: width, height: size.height))
            x += width + gap
        }
    }
}

/// One bar per logical core (3 pt), spread across the width; efficiency cores lighter, set apart.
struct CoreBars: View {
    var cpu: CPUSample
    var split: Bool
    var height: CGFloat
    var gap: CGFloat = 14
    var color: Color = Theme.cpu

    static func averages(_ cpu: CPUSample) -> (p: Double, e: Double) {
        var p: [Double] = [], e: [Double] = []
        for (i, v) in cpu.perCore.enumerated() {
            if i < cpu.coreKinds.count, cpu.coreKinds[i] == .efficiency { e.append(v) } else { p.append(v) }
        }
        let avg = { (a: [Double]) in a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }
        return (avg(p), avg(e))
    }

    var body: some View {
        let indices = Array(cpu.perCore.indices)
        let isE = { (i: Int) in split && i < cpu.coreKinds.count && cpu.coreKinds[i] == .efficiency }
        let perf = indices.filter { !isE($0) }
        let eff = indices.filter { isE($0) }
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(perf.enumerated()), id: \.offset) { n, i in
                if n > 0 { Spacer(minLength: 0) }
                bar(i, dim: false)
            }
            if !eff.isEmpty {
                Spacer(minLength: gap)
                ForEach(Array(eff.enumerated()), id: \.offset) { n, i in
                    if n > 0 { Spacer(minLength: 0) }
                    bar(i, dim: true)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// System at the bottom, user stacked on top.
    private func bar(_ i: Int, dim: Bool) -> some View {
        let sys = i < cpu.perCoreSystem.count ? cpu.perCoreSystem[i] : 0
        let total = min(1, max(0, cpu.perCore[i]))
        return ZStack(alignment: .bottom) {
            Capsule().fill(Theme.track)
            Capsule().fill(color.opacity(dim ? 0.5 : 1)).frame(height: height * total)
            Capsule().fill(Theme.sys.opacity(dim ? 0.5 : 1)).frame(height: height * min(total, max(0, sys)))
        }
        .frame(width: 3, height: height)
    }
}

struct PeakRow: View {
    var peak: PeakMarker
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Format.dayAndTime(peak.date)).ui(13, 500)
                    Text(peak.top.first?.name ?? L10n.Common.dash).ui(12).foregroundStyle(Theme.sub)
                }
                Spacer()
                Text(Format.percent(peak.value / 100)).ui(15, 500)
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .thumbAnchor(selected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Busiest processes recorded at a past moment (no quit controls — they may be long gone).
struct PeakProcessList: View {
    var processes: [PeakProcess]

    var body: some View {
        let maxValue = max(processes.map(\.cpu).max() ?? 1, 0.0001)
        VStack(spacing: 0) {
            if processes.isEmpty {
                Text(L10n.Panel.noProcesses).ui(13).foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 34)
            }
            ForEach(processes, id: \.self) { p in
                HStack(spacing: 10) {
                    LetterTile(name: p.name)
                    Text(p.name).lineLimit(1).frame(width: 130, alignment: .leading)
                    MeterBar(fraction: p.cpu / maxValue, color: Theme.cpu)
                    Text(Format.percentValue(p.cpu)).ui(13, 500).frame(width: 60, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
    }
}

// MARK: - GPU

struct GPUPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    @State private var range: TimeRange = .m5

    var body: some View {
        let g = monitor.snapshot.gpu
        let history = monitor.history
        let _ = monitor.tick
        MonitorPageLayout(module: .gpu) {
            rings(g)
            VStack(alignment: .leading, spacing: 12) {
                RangeRow {
                    RangeControl(range: $range)
                } trailing: {
                    ChartLegend(items: [
                        LegendItem(color: Theme.gpu, label: L10n.Panel.utilization),
                        LegendItem(color: Theme.gpu, label: L10n.Monitor.renderer, value: g.renderer.map(Format.percent), opacity: 0.5),
                        LegendItem(color: Theme.faint, label: L10n.Monitor.tiler, value: g.tiler.map(Format.percent)),
                    ])
                }
                ChartPanel(height: 124, alert: .gpu, alertLine: settings.prefs.alerts.gpuThreshold / 100) {
                    MonitorChart(series: [
                        ChartSeries(id: "gpu", points: history.points(.gpu, range: range), color: Theme.gpu),
                        ChartSeries(id: "renderer", points: history.points(.gpuRenderer, range: range), color: Theme.gpu, fill: 0, lineWidth: 1.5, opacity: 0.5),
                        ChartSeries(id: "tiler", points: history.points(.gpuTiler, range: range), color: Theme.faint, fill: 0, lineWidth: 1.5, dash: [3, 3]),
                    ], range: range, maxValue: 100, hoverText: { hover($0) },
                       threshold: Alerts.Rule.gpu.isOn(settings.prefs) ? (settings.prefs.alerts.gpuThreshold, Theme.danger) : nil)
                    .accessibilityLabel(L10n.Monitor.gpuChartA11y(range.title))
                }
            }
            SideBySide {
                mediaCard(L10n.Monitor.videoDecode, watts: g.decodeWatts, metric: .videoDecode)
                mediaCard(L10n.Monitor.videoEncode, watts: g.encodeWatts, metric: .videoEncode)
                Section(title: L10n.Monitor.frameRate) {
                    Card {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(g.fps.map { "\(Int($0.rounded()))" } ?? L10n.Common.dash).ui(20, 500)
                                Text(L10n.Monitor.fps).ui(12).foregroundStyle(Theme.sub)
                            }
                            Spacer(minLength: 0)
                            if g.maxFPS > 60 { Text(L10n.Monitor.proMotion).ui(12).foregroundStyle(Theme.sub).lineLimit(1) }
                        }
                        MiniChart(series: [.init(values: history.last(.fps, count: 60).map { $0 / Double(max(g.maxFPS, 60)) }, color: Theme.gpu, fill: 0.12)],
                                  gridLines: 0, minCount: 60)
                            .frame(height: 28)
                            .padding(.top, 10)
                            .accessibilityHidden(true)
                    }
                }
            }
            Section(title: L10n.Monitor.topGPU, link: .gpu) {
                let list = Array(monitor.snapshot.processes.byGPU.prefix(4))
                let peak = max(list.map(\.gpu).max() ?? 1, 0.0001)
                ProcessTable(processes: list, fraction: { $0.gpu / peak }, color: Theme.gpu, value: { Format.percentValue($0.gpu) })
            }
        }
    }

    private func rings(_ g: GPUSample) -> some View {
        let unit = settings.prefs.general.temperatureUnit
        let vram = g.memoryLimit > 0 ? Double(g.memoryUsed) / Double(g.memoryLimit) : 0
        let freq = (g.maxMHz ?? 0) > 0 ? (g.frequencyMHz ?? 0) / (g.maxMHz ?? 1) : 0
        let ghz = { (mhz: Double?) in mhz.map { String(format: "%.2f", $0 / 1000) } ?? L10n.Common.dash }
        return HStack(alignment: .top, spacing: 12) {
            gauge(fraction: g.utilization, color: Theme.gpu, value: Format.percent(g.utilization),
                  title: L10n.Panel.utilization, detail: g.cores > 0 ? L10n.Monitor.gpuCores(g.cores) : nil)
            gauge(fraction: vram, color: Theme.gpu, value: Format.percent(vram), title: L10n.Monitor.vramUnified,
                  detail: g.memoryLimit > 0 ? L10n.Monitor.usedSlashLimit(Format.memory(g.memoryUsed), Format.memory(g.memoryLimit)) : Format.memory(g.memoryUsed))
            gauge(fraction: (g.temperature ?? 0) / 100, color: Theme.temp,
                  value: g.temperature.map { Format.temperatureNumber($0, unit: unit) + "°" } ?? L10n.Common.dash,
                  title: L10n.Panel.temperature, detail: g.power.map { L10n.Monitor.powerValue(Format.watts($0)) })
            gauge(fraction: freq, color: Theme.gpu, value: ghz(g.frequencyMHz), title: L10n.Monitor.frequencyGHz,
                  detail: L10n.Monitor.averageMax(ghz(g.averageMHz), ghz(g.maxMHz)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
    }

    private func gauge(fraction: Double, color: Color, value: String, title: String, detail: String?) -> some View {
        VStack(spacing: 0) {
            PageRing(segments: [.init(fraction: fraction, color: color)], size: 64, lineWidth: 4, text: value)
            Text(title).ui(13).lineLimit(1).padding(.top, 10)
            if let detail { Text(detail).ui(12).foregroundStyle(Theme.sub).lineLimit(1).padding(.top, 2) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func mediaCard(_ title: String, watts: Double?, metric: Metric) -> some View {
        let active = (watts ?? 0) >= 0.01
        let values = monitor.history.last(metric, count: 60)
        let peak = max(values.max() ?? 0, 0.5)
        return Section(title: title) {
            Card {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(watts.map(Format.watts) ?? L10n.Common.dash).ui(20, 500).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(active ? L10n.Monitor.activeState : L10n.Monitor.idleState).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
                }
                MiniChart(series: [.init(values: values.map { $0 / peak }, color: active ? Theme.gpu : Theme.faint, fill: 0.12)], gridLines: 0, minCount: 60)
                    .frame(height: 28)
                    .padding(.top, 10)
                    .accessibilityHidden(true)
            }
        }
    }

    private func hover(_ date: Date) -> [String] {
        let history = monitor.history
        let pts = history.points(.gpu, range: range)
        guard let i = nearest(pts, date) else { return [] }
        var lines = [timeLabel(pts[i].date, range) + "\t" + Format.percent(pts[i].value / 100)]
        let r = history.points(.gpuRenderer, range: range), t = history.points(.gpuTiler, range: range)
        if let j = nearest(r, date) { lines.append(L10n.Monitor.renderer + "\t" + Format.percent(r[j].value / 100)) }
        if let j = nearest(t, date) { lines.append(L10n.Monitor.tiler + "\t" + Format.percent(t[j].value / 100)) }
        return lines
    }
}

// MARK: - Memory

struct MemoryPage: View {
    var monitor = Monitor.shared
    @State private var range: TimeRange = .m5

    var body: some View {
        let s = monitor.snapshot
        let m = s.memory
        let _ = monitor.tick
        let pr = PanelText.pressure(m.pressure)
        MonitorPageLayout(module: .memory) {
            summary(m)
            VStack(alignment: .leading, spacing: 12) {
                RangeRow {
                    RangeControl(range: $range)
                } trailing: {
                    ChartLegend(items: [LegendItem(color: pr.1, label: L10n.Monitor.memoryPressure)])
                }
                ChartPanel(height: 104, alert: .memory) {
                    MonitorChart(series: [ChartSeries(id: "pressure", points: monitor.history.points(.memoryPressure, range: range), color: pr.1)],
                                 range: range, maxValue: 100, hoverText: { date in hoverLine(.memoryPressure, range, date) { Format.percent($0 / 100) } },
                                 threshold: (50, Theme.sys))
                        .accessibilityLabel(L10n.Monitor.memoryChartA11y(range.title))
                }
            }
            SideBySide {
                Section(title: L10n.Monitor.memoryPressure) {
                    Card {
                        HStack(alignment: .firstTextBaseline) {
                            Text(pr.0).ui(15, 500).foregroundStyle(pr.1)
                            Spacer(minLength: 0)
                            Text(Format.percent(m.pressureLevel)).ui(15, 500)
                        }
                        .padding(.bottom, 12)
                        ZoneTrack(zones: [(50, Theme.ok), (30, Theme.sys), (20, Theme.temp)], position: m.pressureLevel, knob: pr.1)
                    }
                }
                Section(title: L10n.Memory.swap) {
                    Card {
                        HStack(alignment: .firstTextBaseline) {
                            Text(Format.memory(m.swapUsed)).ui(15, 500)
                            Spacer(minLength: 0)
                            if m.swapTotal > 0 { Text(L10n.Monitor.swapFile(Format.memory(m.swapTotal))).ui(12).foregroundStyle(Theme.sub) }
                        }
                        .padding(.bottom, 12)
                        MeterBar(fraction: m.swapTotal > 0 ? Double(m.swapUsed) / Double(m.swapTotal) : 0, color: Theme.mem)
                    }
                }
            }
            Section(title: L10n.Monitor.topMemory, link: .memory) {
                let list = Array(s.processes.byMemory.prefix(5))
                let peak = max(Double(list.map(\.memory).max() ?? 1), 1)
                ProcessTable(processes: list, fraction: { Double($0.memory) / peak }, color: Theme.mem, value: { Format.memory($0.memory) })
            }
        }
    }

    private func summary(_ m: MemorySample) -> some View {
        HStack(spacing: 20) {
            PageRing(segments: MemoryRing.segments(m), size: 72, lineWidth: 5, text: Format.percent(m.usedFraction), textSize: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.Monitor.usedOfTotal(Format.memory(m.used), Format.memory(m.total))).ui(13).foregroundStyle(Theme.sub)
                    .padding(.bottom, 10)
                StackedBar(parts: [(Double(m.app), Theme.mem), (Double(m.wired), Theme.mem.opacity(0.6)), (Double(m.compressed), Theme.mem.opacity(0.35)),
                                   (Double(m.cached), Theme.cache), (Double(m.free), Theme.track)])
                    .accessibilityElement()
                    .accessibilityLabel(L10n.Monitor.compositionA11y(Format.memory(m.app), Format.memory(m.wired), Format.memory(m.compressed), Format.memory(m.cached), Format.memory(m.free)))
                HStack(alignment: .top, spacing: 12) {
                    part(Format.memory(m.app), LegendItem(color: Theme.mem, label: L10n.Monitor.appMemory, shape: .square))
                    part(Format.memory(m.wired), LegendItem(color: Theme.mem, label: L10n.Memory.wired, shape: .square, opacity: 0.6))
                    part(Format.memory(m.compressed), LegendItem(color: Theme.mem, label: L10n.Monitor.compressed, shape: .square, opacity: 0.35))
                    part(Format.memory(m.cached), LegendItem(color: Theme.cache, label: L10n.Monitor.cache, shape: .square))
                    part(Format.memory(m.free), LegendItem(color: Theme.track, label: L10n.Memory.free, shape: .square))
                }
                .padding(.top, 10)
                .accessibilityHidden(true)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
    }

    private func part(_ value: String, _ item: LegendItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).ui(15, 500).lineLimit(1)
            HStack(spacing: 5) {
                item.swatch
                Text(item.label).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Network

struct NetworkPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    @State private var range: TimeRange = .m5

    var body: some View {
        let s = monitor.snapshot
        let n = s.network
        let unit = settings.prefs.network.speedUnit
        let _ = monitor.tick
        MonitorPageLayout(module: .network) {
            HStack(alignment: .top, spacing: 12) {
                speed(n.down, unit: unit, color: Theme.down, label: L10n.Panel.download, session: n.sessionDown, today: n.todayDown)
                speed(n.up, unit: unit, color: Theme.up, label: L10n.Panel.upload, session: n.sessionUp, today: n.todayUp)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            VStack(alignment: .leading, spacing: 12) {
                RangeRow {
                    RangeControl(range: $range)
                } trailing: {
                    ChartLegend(items: [LegendItem(color: Theme.down, label: L10n.Panel.download), LegendItem(color: Theme.up, label: L10n.Panel.upload)])
                }
                ChartPanel(height: 90, alert: .network) { mirrored }
            }
            Section(title: L10n.Monitor.connection) { connection(n) }
            Section(title: L10n.Monitor.topNetwork, link: .network) {
                let list = Array(s.processes.byNetwork.prefix(4))
                let peak = max(list.map(\.netTotal).max() ?? 1, 0.0001)
                ProcessTable(processes: list, fraction: { $0.netTotal / peak }, color: Theme.down,
                             value: { MenuBarText.downArrow + " " + Format.rate($0.netDown, unit: unit) }, valueWidth: 80,
                             secondary: { MenuBarText.upArrow + " " + Format.rate($0.netUp, unit: unit) }, secondaryWidth: 72)
            }
        }
    }

    private func speed(_ rate: Double, unit: SpeedUnit, color: Color, label: String, session: UInt64, today: UInt64) -> some View {
        let parts = Format.rateParts(rate, unit: unit)
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(parts.0).ui(36, 500).kerning(-1.08)
                Text(parts.1).ui(15).foregroundStyle(Theme.sub)
            }
            .lineLimit(1)
            .frame(height: 40)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 8, height: 8)
                Text(label).ui(13)
            }
            .padding(.top, 4)
            Text(L10n.Monitor.sessionToday(Format.storage(session), Format.storage(today))).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Download above the center line, upload below, each scaled to its own peak.
    private var mirrored: some View {
        let history = monitor.history
        let down = history.points(.netDown, range: range)
        let up = history.points(.netUp, range: range)
        let dPeak = max(down.map(\.value).max() ?? 0, 10_000) * 1.1
        let uPeak = max(up.map(\.value).max() ?? 0, 10_000) * 1.1
        return MonitorChart(series: [
            ChartSeries(id: "down", points: down.map { ChartPoint(date: $0.date, value: $0.value / dPeak) }, color: Theme.down, fill: 0.16, lineWidth: 1.5),
            ChartSeries(id: "up", points: up.map { ChartPoint(date: $0.date, value: -$0.value / uPeak) }, color: Theme.up, fill: 0.2, lineWidth: 1.5),
        ], range: range, maxValue: nil, hoverText: { hover($0) }, domain: -1...1, gridValues: [-0.5, 0.5], centerLine: true)
        .accessibilityLabel(L10n.Monitor.networkChartA11y(range.title))
    }

    private func connection(_ n: NetworkSample) -> some View {
        let showLatency = settings.prefs.network.showLatency
        let detail = [n.localIP.isEmpty ? nil : L10n.Monitor.localIP(n.localIP), n.router.isEmpty ? nil : L10n.Monitor.router(n.router)].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                LineIcon(d: n.kind == .wifi ? Icons.wifi : Icons.network, size: 16, lineWidth: 1.5)
                    .foregroundStyle(Theme.sub)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.well))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(n.interface.isEmpty ? PanelText.kindName(n.kind) : L10n.Settings.interfaceOption(PanelText.kindName(n.kind), n.interface)).ui(13, 500).lineLimit(1)
                        HStack(spacing: 5) {
                            Circle().fill(n.connected ? Theme.ok : Theme.faint).frame(width: 6, height: 6)
                            Text(n.connected ? L10n.Overview.connected : L10n.Panel.notConnected).ui(12)
                        }
                        .foregroundStyle(n.connected ? Theme.ok : Theme.sub)
                    }
                    if !detail.isEmpty {
                        Text(detail.joined(separator: " · ")).ui(12).foregroundStyle(Theme.sub).lineLimit(1).truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
                if showLatency {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(n.latencyMS.map { L10n.Monitor.milliseconds(Int($0.rounded())) } ?? L10n.Common.dash).ui(15, 500)
                        Text(L10n.Monitor.latency).ui(12).foregroundStyle(Theme.sub)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if showLatency {
                QuarterSplit {
                    Text(L10n.Monitor.connectionLog).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
                    ConnectionLog(checks: n.checks)
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Hairline() }
                .padding(.top, 12)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
    }

    private func hover(_ date: Date) -> [String] {
        let d = monitor.history.points(.netDown, range: range)
        let u = monitor.history.points(.netUp, range: range)
        guard let i = nearest(d, date) else { return [] }
        return [timeLabel(d[i].date, range), L10n.Panel.download + "\t" + Format.rate(d[i].value), L10n.Panel.upload + "\t" + Format.rate(i < u.count ? u[i].value : 0)]
    }
}

/// The last 48 connection checks as small squares (ok / slow / failed; empty slots are track).
struct ConnectionLog: View {
    var checks: [ConnectionCheck]

    var body: some View {
        let slots = Array(repeating: ConnectionCheck?.none, count: max(0, 48 - checks.count)) + checks.suffix(48).map { Optional($0) }
        HStack(spacing: 2) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, c in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(color(c))
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel(L10n.Monitor.checksA11y(checks.count, checks.filter { $0 == .ok }.count,
                                                    checks.filter { $0 == .slow }.count, checks.filter { $0 == .failed }.count))
    }

    private func color(_ c: ConnectionCheck?) -> Color {
        switch c {
        case .ok: return Theme.ok.opacity(0.7)
        case .slow: return Theme.sys
        case .failed, nil: return Theme.track
        }
    }
}

// MARK: - Disk

struct DiskPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    @State private var range: TimeRange = .m5

    var body: some View {
        let s = monitor.snapshot
        let d = s.disk
        let unit = settings.prefs.general.temperatureUnit
        let _ = monitor.tick
        MonitorPageLayout(module: .disk) {
            VStack(spacing: 0) {
                ForEach(Array(d.volumes.enumerated()), id: \.element.id) { i, v in
                    VolumeRow(volume: v)
                        .padding(.top, i > 0 ? 14 : 0)
                        .overlay(alignment: .top) { if i > 0 { Hairline() } }
                        .padding(.top, i > 0 ? 14 : 0)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            VStack(alignment: .leading, spacing: 12) {
                RangeRow {
                    RangeControl(range: $range)
                } trailing: {
                    ChartLegend(items: [LegendItem(color: Theme.read, label: L10n.Disk.read, value: Format.rate(d.read)),
                                        LegendItem(color: Theme.write, label: L10n.Disk.write, value: Format.rate(d.write))])
                }
                ChartPanel(height: 88, alert: .disk) {
                    MonitorChart(series: [
                        ChartSeries(id: "read", points: monitor.history.points(.diskRead, range: range), color: Theme.read),
                        ChartSeries(id: "write", points: monitor.history.points(.diskWrite, range: range), color: Theme.write, fill: 0, lineWidth: 1.5),
                    ], range: range, maxValue: nil, hoverText: { hover($0) })
                    .accessibilityLabel(L10n.Monitor.diskChartA11y(range.title))
                }
            }
            if let h = d.health, let root = d.root {
                Section(title: L10n.Monitor.diskHealth(root.name), right: h.ok ? L10n.Monitor.smartGood : L10n.Monitor.smartFailing,
                        rightColor: h.ok ? Theme.ok : Theme.danger) {
                    Card {
                        HStack(alignment: .firstTextBaseline) {
                            Text(L10n.Monitor.lifeRemaining).ui(13)
                            Spacer(minLength: 0)
                            Text(Format.percent(h.lifeRemaining)).ui(15, 500)
                        }
                        .padding(.bottom, 10)
                        MeterBar(fraction: h.lifeRemaining, color: h.lifeRemaining >= 0.1 ? Theme.ok : Theme.danger)
                        HStack(alignment: .top, spacing: 12) {
                            stat(Format.storage(h.totalWritten), L10n.Monitor.totalWritten)
                            stat(Format.storage(d.totalWritten), L10n.Disk.writeSinceBoot)
                            stat(Format.storage(d.totalRead), L10n.Disk.readSinceBoot)
                            stat(h.temperature.map { Format.temperature($0, unit: unit, showUnit: true) } ?? L10n.Common.dash, L10n.Panel.temperature)
                        }
                        .padding(.top, 14)
                    }
                }
            }
            Section(title: L10n.Panel.topDisk, link: .disk) {
                let list = Array(s.processes.byDisk.prefix(4))
                let peak = max(list.map(\.diskTotal).max() ?? 1, 0.0001)
                ProcessTable(processes: list, fraction: { $0.diskTotal / peak }, color: Theme.read,
                             value: { L10n.Monitor.readRate(Format.rate($0.diskRead)) }, valueWidth: 92,
                             secondary: { L10n.Monitor.writeRate(Format.rate($0.diskWrite)) }, secondaryWidth: 80)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).ui(15, 500).lineLimit(1)
            Text(label).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func hover(_ date: Date) -> [String] {
        let r = monitor.history.points(.diskRead, range: range)
        let w = monitor.history.points(.diskWrite, range: range)
        guard let i = nearest(r, date) else { return [] }
        return [timeLabel(r[i].date, range), L10n.Disk.read + "\t" + Format.rate(r[i].value), L10n.Disk.write + "\t" + Format.rate(i < w.count ? w[i].value : 0)]
    }
}

/// Icon, name, internal/external pill, eject, free space; stacked used / purgeable / free bar.
struct VolumeRow: View {
    var volume: Volume

    var body: some View {
        let used = max(0, volume.used - volume.purgeable)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                LineIcon(d: Icons.disk, size: 16, lineWidth: 1.5)
                    .foregroundStyle(Theme.sub)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.well))
                    .accessibilityHidden(true)
                HStack(spacing: 8) {
                    Text(volume.name).ui(15, 500).lineLimit(1)
                    Text(volume.isInternal ? L10n.Disk.internalDrive : L10n.Disk.external).ui(12).foregroundStyle(Theme.sub)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.well))
                    if volume.isEjectable && !volume.isRoot { EjectButton(volume: volume, size: 28) }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Format.storage(volume.available)).ui(15, 500)
                    Text(L10n.Disk.free).ui(12).foregroundStyle(Theme.sub)
                }
            }
            StackedBar(parts: [(Double(used), Theme.disk), (Double(volume.purgeable), Theme.disk.opacity(0.4)), (Double(volume.available), Theme.track)])
                .padding(.top, 12)
            HStack(spacing: 12) {
                Text(detail).lineLimit(1)
                Spacer(minLength: 0)
                Text(Format.percent(volume.usedFraction))
            }
            .ui(12)
            .foregroundStyle(Theme.sub)
            .padding(.top, 8)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        volume.purgeable > 0
            ? L10n.Monitor.volumeUsedPurgeable(Format.storage(volume.used), Format.storage(volume.purgeable), Format.storage(volume.total))
            : L10n.Monitor.volumeUsed(Format.storage(volume.used), Format.storage(volume.total))
    }
}

struct EjectButton: View {
    var volume: Volume
    var size: CGFloat = 20

    var body: some View {
        Button {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
        } label: {
            SVGShape(d: "M6 1.5L10.5 7h-9zM1.5 8.5h9v1.6h-9z", viewBox: CGSize(width: 12, height: 12))
                .fill(Theme.text)
                .frame(width: size > 24 ? 10 : 9, height: size > 24 ? 10 : 9)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size > 24 ? 7 : 6, style: .continuous).fill(Theme.raised).raisedShadow())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Disk.eject(volume.name))
    }
}

// MARK: - Battery

struct BatteryPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    @State private var range: TimeRange = .h24

    var body: some View {
        let s = monitor.snapshot
        let b = s.battery
        let _ = monitor.tick
        MonitorPageLayout(module: .battery) {
            if b.hasBattery {
                hero(b)
                SideBySide {
                    Section(title: L10n.Monitor.powerSource) { powerCard(b) }
                    Section(title: L10n.Monitor.batteryHealth, right: (b.health ?? 1) >= 0.8 ? L10n.Monitor.healthNormal : L10n.Monitor.healthService,
                            rightColor: (b.health ?? 1) >= 0.8 ? Theme.ok : Theme.warn) { healthCard(b, s) }
                }
                VStack(alignment: .leading, spacing: 12) {
                    RangeRow {
                        Segmented(label: L10n.Range.label, options: [(TimeRange.h24, TimeRange.h24.title), (.d7, TimeRange.d7.title)], selection: $range, style: .range)
                            .fixedSize()
                    } trailing: {
                        ChartLegend(items: [LegendItem(color: Theme.bat, label: L10n.Battery.level),
                                            LegendItem(color: Theme.bat, label: L10n.Monitor.chargingLegend, shape: .bar, opacity: 0.25)])
                    }
                    ChartPanel(height: 136, alert: .battery, alertLine: settings.prefs.alerts.batteryPercent / 100) {
                        MonitorChart(series: [ChartSeries(id: "battery", points: monitor.history.points(.battery, range: range), color: Theme.bat)],
                                     range: range, maxValue: 100, hoverText: { hover($0) },
                                     threshold: Alerts.Rule.battery.isOn(settings.prefs) ? (settings.prefs.alerts.batteryPercent, Theme.danger) : nil,
                                     bands: ChargingBands.of(range))
                            .accessibilityLabel(L10n.Monitor.batteryChartA11y(range.title))
                    }
                }
                energySection(s, wholeMac: b.onAC ? max(0, (b.systemPowerIn ?? 0) - max(0, b.power ?? 0)) : abs(b.power ?? 0))
            } else {
                HStack(spacing: 14) {
                    LineIcon(d: Icons.batteryOff, size: 16, lineWidth: 1.5)
                        .foregroundStyle(Theme.sub)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.well))
                    Text(L10n.Battery.noBattery).ui(15, 500)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            }
            if !b.ups.isEmpty {
                Section(title: L10n.Battery.ups) {
                    VStack(spacing: 0) { DividedRows { ForEach(b.ups) { UPSRow(source: $0) } } }
                        .padding(.horizontal, 14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
                }
            }
            if !b.hasBattery { energySection(s, wholeMac: s.sensors.systemPower) }
        }
    }

    /// The apps drawing the most power, with the whole Mac's draw on the right.
    private func energySection(_ s: Snapshot, wholeMac: Double?) -> some View {
        let list = Array(s.processes.byEnergy.prefix(5))
        let peak = max(list.map(\.energy).max() ?? 1, 0.0001)
        return Section(title: L10n.Processes.topEnergy, right: wholeMac.map { L10n.Processes.wholeMac(Format.watts($0)) }, link: .energy) {
            ProcessTable(processes: list, fraction: { $0.energy / peak }, color: Theme.bat, value: { Format.appWatts($0.energy) })
        }
    }

    private func hero(_ b: BatterySample) -> some View {
        HStack(spacing: 20) {
            LargeBattery(level: b.level, charging: b.isCharging, color: BatteryColors.fill(b)).frame(width: 96, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(percentNumber(b.level)).ui(36, 500).kerning(-1.08)
                    Text("%").ui(15).foregroundStyle(Theme.sub)
                }
                .frame(height: 40)
                Text(status(b)).ui(13).lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .accessibilityElement(children: .combine)
    }

    private func status(_ b: BatterySample) -> String {
        if b.isCharging, let m = b.minutesToFull { return L10n.Battery.charging + " · " + L10n.Battery.untilFull(BatteryTime.text(m)) }
        if b.isCharging { return L10n.Battery.charging }
        if b.onAC { return b.isCharged || b.level >= 0.99 ? L10n.Battery.charged : L10n.Battery.onAC }
        if let m = b.minutesToEmpty { return L10n.Battery.onBattery + " · " + L10n.Battery.remaining(BatteryTime.text(m)) }
        return L10n.Battery.onBattery
    }

    private func powerCard(_ b: BatterySample) -> some View {
        let charge = max(0, b.power ?? 0)
        let system = b.onAC ? max(0, (b.systemPowerIn ?? 0) - charge) : abs(b.power ?? 0)
        let adapter = Double(b.adapterWatts ?? 0)
        let headroom = max(0, adapter - system - charge)
        return Card {
            if b.onAC {
                ValueLine(label: L10n.Monitor.adapter, value: b.adapterWatts.map { "\($0) W" } ?? L10n.Common.dash)
                StackedBar(parts: [(system, Theme.sys), (charge, Theme.bat), (headroom, Theme.track)]).padding(.top, 10)
                ValueLine(label: L10n.Monitor.systemDraw, value: Format.watts(system), swatch: LegendItem(color: Theme.sys, label: "", shape: .square))
                    .padding(.top, 12)
                ValueLine(label: L10n.Monitor.chargePower, value: Format.watts(charge), swatch: LegendItem(color: Theme.bat, label: "", shape: .square))
                    .padding(.top, 6)
                ValueLine(label: L10n.Monitor.headroom, value: Format.watts(headroom), swatch: LegendItem(color: Theme.faint, label: "", shape: .outline))
                    .padding(.top, 6)
            } else {
                ValueLine(label: L10n.Battery.onBattery, value: Format.watts(system))
                StackedBar(parts: [(1, Theme.sys)]).padding(.top, 10)
                ValueLine(label: L10n.Monitor.systemDraw, value: Format.watts(system), swatch: LegendItem(color: Theme.sys, label: "", shape: .square))
                    .padding(.top, 12)
            }
        }
    }

    private func healthCard(_ b: BatterySample, _ s: Snapshot) -> some View {
        let unit = settings.prefs.general.temperatureUnit
        let design = b.designCycles ?? 1000
        return Card {
            ValueLine(label: L10n.Battery.health, value: b.health.map(Format.percent) ?? L10n.Common.dash)
            MeterBar(fraction: b.health ?? 0, color: (b.health ?? 1) >= 0.8 ? Theme.ok : Theme.warn).padding(.top, 8)
            ValueLine(label: L10n.Battery.cycles, value: b.cycles.map { L10n.Monitor.cyclesOf($0, design) } ?? L10n.Common.dash).padding(.top, 14)
            MeterBar(fraction: Double(b.cycles ?? 0) / Double(max(design, 1)), color: Theme.bat).padding(.top, 8)
            ValueLine(label: L10n.Battery.temperature,
                      value: (b.temperature ?? s.sensors.value(.battery)).map { Format.temperature($0, unit: unit, showUnit: true) } ?? L10n.Common.dash)
                .padding(.top, 14)
            if let full = b.maxCapacity, let designCap = b.designCapacity {
                ValueLine(label: L10n.Monitor.capacity, value: L10n.Monitor.capacityValue(grouped(full), grouped(designCap))).padding(.top, 6)
            }
        }
    }

    private func hover(_ date: Date) -> [String] {
        let pts = monitor.history.points(.battery, range: range)
        guard let i = nearest(pts, date) else { return [] }
        return [Format.dayAndTime(pts[i].date) + "\t" + Format.percent(pts[i].value / 100)]
    }
}

enum ChargingBands {
    /// Spans where the battery was charging, from the per-minute (or five-minute) buckets.
    static func of(_ range: TimeRange) -> [ClosedRange<Date>] {
        let pts = Monitor.shared.history.points(.charging, range: range)
        var bands: [ClosedRange<Date>] = []
        var start: Date?
        let step = range == .h24 ? 60.0 : 300.0
        for p in pts {
            if p.value >= 0.5 {
                if start == nil { start = p.date }
            } else if let s = start {
                bands.append(s...p.date)
                start = nil
            }
        }
        if let s = start, let last = pts.last { bands.append(s...last.date.addingTimeInterval(step)) }
        return bands
    }
}

enum BatteryTime {
    /// "0:42" or "42 分钟", per the battery module's time format.
    static func text(_ minutes: Int) -> String {
        SettingsStore.shared.prefs.battery.timeFormat == .minutes ? L10n.Battery.minutesShort(minutes) : Format.clockDuration(minutes: minutes)
    }
}

struct UPSRow: View {
    var source: PowerSource

    var body: some View {
        HStack(spacing: 12) {
            LineIcon(d: Icons.ups, size: 16, lineWidth: 1.4)
                .foregroundStyle(Theme.sub)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.well))
            VStack(alignment: .leading, spacing: 0) {
                Text(source.name).lineLimit(1)
                Text(source.onAC ? (source.minutesLeft.map { L10n.Battery.upsDetail($0) } ?? L10n.Battery.upsOnAC) : L10n.Battery.onBattery)
                    .ui(12).foregroundStyle(Theme.sub).lineLimit(1)
            }
            Spacer(minLength: 8)
            BatteryGlyph(level: source.level, fill: Theme.bat, rim: Theme.faint, rimOpacity: 1)
            Text(Format.percent(source.level)).ui(13, 500).frame(width: 40, alignment: .trailing)
        }
        .frame(minHeight: 54)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sensors

struct SensorsPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    @State private var range: TimeRange = .m5

    var body: some View {
        let s = monitor.snapshot.sensors
        let unit = settings.prefs.general.temperatureUnit
        let _ = monitor.tick
        MonitorPageLayout(module: .sensors) {
            hero(s, unit)
            VStack(alignment: .leading, spacing: 12) {
                RangeRow {
                    RangeControl(range: $range)
                } trailing: {
                    ChartLegend(items: [LegendItem(color: Theme.temp, label: L10n.Monitor.cpuAverageShort)])
                }
                ChartPanel(height: 76, alert: .temperature, alertLine: settings.prefs.alerts.tempThreshold / 110) {
                    MonitorChart(series: [ChartSeries(id: "cpu", points: monitor.history.points(.cpuTemp, range: range), color: Theme.temp)],
                                 range: range, maxValue: 110,
                                 hoverText: { date in hoverLine(.cpuTemp, range, date) { Format.temperature($0, unit: unit, showUnit: true) } },
                                 threshold: Alerts.Rule.temperature.isOn(settings.prefs) ? (settings.prefs.alerts.tempThreshold, Theme.danger) : nil)
                        .accessibilityLabel(L10n.Monitor.tempChartA11y(range.title))
                }
            }
            Section(title: L10n.Sensors.temperatures) {
                VStack(spacing: 0) {
                    DividedRows {
                        ForEach(s.temps) { t in
                            HStack(spacing: 10) {
                                Text(PanelText.tempName(t.group)).lineLimit(1).frame(width: 110, alignment: .leading)
                                ZoneTrack(zones: [(50, Theme.ok), (20, Theme.sys), (10, Theme.temp)], position: (t.value - 20) / 80,
                                          knob: TempZone.color(t.value), zoneOpacity: 0.3)
                                Text(Format.temperature(t.value, unit: unit, showUnit: true)).fontWeight(.medium).frame(width: 56, alignment: .trailing)
                            }
                            .ui(13)
                            .frame(height: 32)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            }
            .overlay(alignment: .topTrailing) { zoneLegend(unit).padding(.trailing, 14) }
            SideBySide {
                Section(title: L10n.Sensors.fans, right: s.fans.isEmpty ? nil : (s.fansAuto ? L10n.Monitor.fanAuto : L10n.Monitor.fanManual)) {
                    fanCard(s)
                }
                Section(title: L10n.Sensors.power) { powerCard(s) }
            }
        }
    }

    private func hero(_ s: SensorsSample, _ unit: TemperatureUnit) -> some View {
        let color = ThermalText.color(s.thermal)
        return HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(s.cpuAverage.map { Format.temperatureNumber($0, unit: unit) } ?? L10n.Common.dash).ui(36, 500).kerning(-1.08)
                    Text(unit == .celsius ? "°C" : "°F").ui(15).foregroundStyle(Theme.sub)
                }
                .frame(height: 40)
                Text(s.cpuMax.map { L10n.Monitor.cpuAverageMax(Format.temperature($0, unit: unit, showUnit: true)) } ?? L10n.Monitor.cpuAverageShort)
                    .ui(12).foregroundStyle(Theme.sub).lineLimit(1)
            }
            .fixedSize()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.Sensors.thermalState).ui(13)
                    Spacer(minLength: 0)
                    Text(PanelText.thermal(s.thermal).0).ui(13, 500).foregroundStyle(color).lineLimit(1)
                }
                LevelSegments(level: s.thermal.rawValue, color: color).padding(.top, 10)
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { i in
                        Text(L10n.Monitor.thermalLevel(i)).ui(12).foregroundStyle(i == s.thermal.rawValue ? color : Theme.sub)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 6)
                .accessibilityHidden(true)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .accessibilityElement(children: .combine)
    }

    private func zoneLegend(_ unit: TemperatureUnit) -> some View {
        let t = { (c: Double) in Format.temperature(c, unit: unit, showUnit: true) }
        return HStack(spacing: 12) {
            Text(L10n.Monitor.zoneLow(t(70))).foregroundStyle(Theme.ok)
            Text(L10n.Monitor.zoneMid(Format.temperatureNumber(70, unit: unit), t(90))).foregroundStyle(Theme.sys)
            Text(L10n.Monitor.zoneHigh(t(90))).foregroundStyle(Theme.temp)
        }
        .ui(12)
        .lineLimit(1)
        .frame(height: 18)
    }

    private func fanCard(_ s: SensorsSample) -> some View {
        Card {
            if s.fans.isEmpty {
                Text(L10n.Sensors.fanless).foregroundStyle(Theme.sub)
            } else {
                ForEach(Array(s.fans.enumerated()), id: \.offset) { i, f in
                    ValueLine(label: PanelText.fanName(f.id, count: s.fans.count), value: Format.rpm(f.rpm)).padding(.top, i > 0 ? 12 : 0)
                    MeterBar(fraction: f.max > f.min ? (f.rpm - f.min) / (f.max - f.min) : 0, color: Theme.faint).padding(.top, 8)
                }
                if let f = s.fans.first, f.max > 0 {
                    Text(L10n.Monitor.fanRange(Int(f.min.rounded()), Int(f.max.rounded()))).ui(12).foregroundStyle(Theme.sub).padding(.top, 12)
                }
            }
        }
    }

    private func powerCard(_ s: SensorsSample) -> some View {
        let cpu = s.cpuPower ?? 0, gpu = s.gpuPower ?? 0
        let total = s.systemPower ?? (cpu + gpu)
        let other = max(0, total - cpu - gpu)
        return Card {
            ValueLine(label: L10n.Monitor.system, value: s.systemPower.map(Format.watts) ?? L10n.Common.dash)
            StackedBar(parts: [(cpu, Theme.cpu), (gpu, Theme.gpu), (other, Theme.track)]).padding(.top, 10)
            FlowLayout(spacing: 12, lineSpacing: 6) {
                powerItem(LegendItem(color: Theme.cpu, label: L10n.Module.cpu, shape: .square), s.cpuPower)
                powerItem(LegendItem(color: Theme.gpu, label: L10n.Module.gpu, shape: .square), s.gpuPower)
                powerItem(LegendItem(color: Theme.faint, label: L10n.Monitor.other, shape: .outline), s.systemPower == nil ? nil : other)
            }
            .padding(.top, 12)
        }
    }

    private func powerItem(_ item: LegendItem, _ watts: Double?) -> some View {
        HStack(spacing: 6) {
            item.swatch
            Text(item.label).foregroundStyle(Theme.sub)
            Text(watts.map(Format.watts) ?? L10n.Common.dash).fontWeight(.medium)
        }
        .ui(12)
        .fixedSize()
    }
}

enum TempZone {
    static func color(_ celsius: Double) -> Color {
        celsius >= 90 ? Theme.temp : celsius >= 70 ? Theme.sys : Theme.ok
    }
}

/// Five-part bar: app, wired, compressed, cached, free (3 pt gaps, rounded ends).
struct MemoryComposition: View {
    var m: MemorySample
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let total = max(Double(m.total), 1)
            let parts: [(Double, Color)] = [
                (Double(m.app), Theme.mem), (Double(m.wired), Theme.mem.opacity(0.6)), (Double(m.compressed), Theme.mem.opacity(0.35)),
                (Double(m.cached), Theme.cache), (Double(m.free), Theme.track),
            ].filter { $0.0 > 0 }
            let gaps = CGFloat(max(parts.count - 1, 0)) * 3
            HStack(spacing: 3) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                    Capsule().fill(p.1).frame(width: max(height, (geo.size.width - gaps) * p.0 / total))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct MemoryLegend: View {
    var color: Color
    var label: String
    var bytes: UInt64
    var size: CGFloat = 6
    var ring = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: size, height: size)
                .overlay(Circle().strokeBorder(ring ? Theme.cache : .clear, lineWidth: 1))
            Text(label).foregroundStyle(Theme.sub).lineLimit(1)
            Spacer(minLength: 4)
            Text(Format.memory(bytes)).fontWeight(.medium)
        }
        .ui(12)
    }
}
