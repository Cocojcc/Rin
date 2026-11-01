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
                Text(title).ui(14, 500).foregroundStyle(Theme.sub).accessibilityAddTraits(.isHeader)
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

/// A monitor page: the module header with its time ranges on the right, then the panels 10 apart.
struct MonitorPageLayout<Content: View>: View {
    let module: Module
    var range: Binding<TimeRange>? = nil
    var ranges: [TimeRange] = TimeRange.allCases
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ModuleHeader(module: module) {
                if let range { RangeControl(range: range, options: ranges, tint: Theme.hue(module)) }
            }
            content
        }
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
    /// Edit mode: every card shows, each with its module's switch; off ones stay dimmed in place.
    @State private var editing = OverviewPage.initialEditing
    /// Lets the snapshot tool render edit mode.
    static var initialEditing = false

    var body: some View {
        let s = monitor.snapshot
        let unit = settings.prefs.general.temperatureUnit
        let _ = monitor.tick
        let shows = { (m: Module) in editing || settings.prefs.isEnabled(m) }
        VStack(alignment: .leading, spacing: 10) {
            PageTitle(title: L10n.Overview.title) {
                status
                Text(Format.uptime(since: SystemInfo.bootTime)).ui(14).foregroundStyle(Theme.sub).lineLimit(1)
                OverviewEditButton(editing: editing) { withAnimation(Motion.slide) { editing.toggle() } }
            }
            if !editing && Module.allCases.allSatisfy({ !settings.prefs.isEnabled($0) }) {
                Text(L10n.Overview.allOff).ui(14).foregroundStyle(Theme.sub)
            }
            FillGrid(spacing: 10) {
                if shows(.cpu) { cpuTile(s) }
                if shows(.memory) { memoryTile(s) }
                if shows(.network) { networkTile(s) }
                if shows(.disk) { diskTile(s) }
                if shows(.battery) { batteryTile(s) }
                if shows(.sensors) { sensorsTile(s, unit) }
                if shows(.cpu) { peakTile() }
                if shows(.gpu) { gpuTile(s, unit) }
                if shows(.bluetooth) { bluetoothTile(s) }
            }
            .environment(\.overviewEditing, editing)
        }
    }

    /// How things stand, as she says it; while an alert is up, its snooze and view beside it.
    @ViewBuilder private var status: some View {
        let st = Status.now()
        StatusText(text: st.line, color: st.color)
        if let event = alerts.current {
            Button { alerts.snooze(event.rule) } label: {
                Text(L10n.Alerts.snooze).ui(12).foregroundStyle(Theme.sub).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { alerts.show(event) } label: {
                Text(L10n.Alerts.view).ui(12, 500).foregroundStyle(Theme.text)
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.well))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Tiles

    /// "超过 90%" in red on a tile whose usage rule is firing.
    private func overLimit(_ rule: Alerts.Rule) -> (String, Color)? {
        guard let e = alerts.firing(rule) else { return nil }
        return (L10n.Alerts.overLimit(Format.percent(e.limit / 100)), Theme.danger)
    }

    private func chart(_ kind: ConsoleChart.Kind, _ series: [ChartSeries], range: TimeRange = .m5, max: Double, bottom: Double = 1, grid: [Double] = [0.5], baseline: Bool = true, markers: [PeakMarker] = []) -> some View {
        ConsoleChart(kind: kind, series: series, range: range, maxValue: max, bottomMax: bottom, gutter: 0, grid: grid, baseline: baseline,
                     showTimes: false, markers: markers, markerColor: Theme.cpu)
            .allowsHitTesting(false)
    }

    private func cpuTile(_ s: Snapshot) -> some View {
        OverviewTile(module: .cpu, key: Theme.cpu, status: overLimit(.cpu)) {
            BigValue(value: Format.percent(s.cpu.total), color: Theme.cpu)
        } aside: {
            KeyValue(label: L10n.Monitor.idle, value: Format.percent(max(0, 1 - s.cpu.total)))
        } chart: {
            chart(.area, ChartSeries.cpuStack(total: monitor.history.points(.cpu, range: .m5), system: monitor.history.points(.cpuSystem, range: .m5)), max: 100)
        } rows: {
            HStack(spacing: 12) {
                KeyValue(label: L10n.Panel.user, value: Format.percent(s.cpu.user), key: Theme.cpu)
                KeyValue(label: L10n.Panel.system, value: Format.percent(s.cpu.system), key: Theme.sys)
            }
            .frame(height: 20)
            processRows(Array(s.processes.byCPU.prefix(2))) { Format.percentValue($0.cpu) }
        }
    }

    private func memoryTile(_ s: Snapshot) -> some View {
        let m = s.memory
        let pr = PanelText.pressure(m.pressure)
        let label = m.pressure == .normal ? L10n.Overview.pressureNormal : m.pressure == .warning ? L10n.Overview.pressureWarning : L10n.Overview.pressureCritical
        let used = Format.parts(Format.memory(m.used))
        return OverviewTile(module: .memory, key: Theme.mem, status: (label, pr.1)) {
            BigValue(value: used.0, unit: L10n.Monitor.ofTotal(Format.memory(m.total)), color: Theme.mem)
        } aside: {
            Text(Format.percent(m.usedFraction)).ui(14).foregroundStyle(Theme.sub)
        } chart: {
            chart(.area, [ChartSeries(id: "m", points: monitor.history.points(.memory, range: .m5), color: Theme.mem, fill: 0.2, lineWidth: 1.5)], max: 100)
        } rows: {
            TileRow(label: L10n.Memory.swap, value: Format.memory(m.swapUsed))
            processRows(Array(s.processes.byMemory.prefix(2))) { Format.memory($0.memory) }
        }
    }

    private func networkTile(_ s: Snapshot) -> some View {
        let n = s.network
        let speed = settings.prefs.network.speedUnit
        let down = monitor.history.points(.netDown, range: .m5), up = monitor.history.points(.netUp, range: .m5)
        let d = Format.rateParts(n.down, unit: speed)
        let dash = L10n.Common.dash
        return OverviewTile(module: .network, key: Theme.down, status: (networkLine(n), n.connected ? Theme.ok : Theme.sub)) {
            BigValue(value: n.connected ? d.0 : dash, unit: n.connected ? d.1 + " " + MenuBarText.downArrow : nil, color: Theme.down)
        } aside: {
            Text(n.connected ? Format.rate(n.up, unit: speed) + " " + MenuBarText.upArrow : "").ui(14, 500)
        } chart: {
            chart(.mirroredArea, ChartSeries.mirrored(down, Theme.down, up, Theme.up),
                  max: ConsoleChart.niceMax(Swift.max(down.map(\.value).max() ?? 0, 10_000) * 1.1),
                  bottom: ConsoleChart.niceMax(Swift.max(up.map(\.value).max() ?? 0, 10_000) * 1.1), grid: [], baseline: false)
        } rows: {
            TileRow(label: L10n.Overview.localShort, value: n.connected && !n.localIP.isEmpty ? n.localIP : dash, keepLabel: true)
            if settings.prefs.network.showPublicIP {
                TileRow(label: L10n.Overview.publicShort, value: n.connected ? monitor.publicIP ?? dash : dash, keepLabel: true)
            } else {
                TileRow(label: L10n.Network.router, value: n.connected && !n.router.isEmpty ? n.router : dash, keepLabel: true)
            }
        }
    }

    private func diskTile(_ s: Snapshot) -> some View {
        let root = s.disk.root
        let other = s.disk.volumes.first { $0.id != root?.id }
        let health: (String, Color)? = s.disk.health.map { $0.ok ? (L10n.Overview.diskHealthy, Theme.ok) : (L10n.Monitor.healthService, Theme.danger) }
        let free = Format.parts(Format.storage(root?.available ?? 0))
        return OverviewTile(module: .disk, key: Theme.disk, status: health) {
            BigValue(value: free.0, unit: L10n.Monitor.unitFree(free.1), color: Theme.disk)
        } aside: {
            EmptyView()
        } chart: {
            VStack(alignment: .leading, spacing: 6) {
                TileRow(label: (root?.name ?? L10n.Common.dash) + " · " + L10n.Monitor.totalOf(Format.storage(root?.total ?? 0)),
                        value: Format.percent(root?.usedFraction ?? 0))
                WaffleGrid(fraction: root?.usedFraction ?? 0, color: Theme.disk)
            }
        } rows: {
            if let other {
                TileRow(label: other.name, value: Format.storage(other.available) + " " + L10n.Disk.free)
            } else {
                TileRow(label: L10n.Disk.readShort, value: Format.rate(s.disk.read))
            }
        }
    }

    private func batteryTile(_ s: Snapshot) -> some View {
        let b = s.battery
        let state: (String, Color)? = b.hasBattery ? (PanelText.batteryState(b), b.onAC ? Theme.ok : Theme.sub) : nil
        return OverviewTile(module: .battery, key: Theme.bat, status: state) {
            BigValue(value: b.hasBattery ? Format.percent(b.level) : L10n.Common.dash)
        } aside: {
            if b.isCharging, let m = b.minutesToFull {
                Text(L10n.Battery.untilFull(BatteryTime.text(m))).ui(14).foregroundStyle(Theme.sub)
            } else if b.hasBattery, !b.onAC, let m = b.minutesToEmpty {
                Text(L10n.Battery.remaining(BatteryTime.text(m))).ui(14).foregroundStyle(Theme.sub)
            }
        } chart: {
            if b.hasBattery {
                chart(.area, [ChartSeries(id: "b", points: monitor.history.points(.battery, range: .h24), color: Theme.bat, fill: 0.16, lineWidth: 1.5)], range: .h24, max: 100)
            } else {
                Text(L10n.Battery.noBattery).ui(14).foregroundStyle(Theme.sub).frame(maxHeight: .infinity)
            }
        } rows: {
            if b.hasBattery {
                if b.onAC, let w = b.adapterWatts {
                    TileRow(label: L10n.Monitor.powerSource, value: "\(w) W")
                } else if let w = b.power {
                    TileRow(label: L10n.Panel.power, value: Format.watts(abs(w)))
                }
                if let h = b.health { TileRow(label: L10n.Battery.health, value: Format.percent(h)) }
                if let c = b.cycles { TileRow(label: L10n.Overview.cyclesLabel, value: L10n.Overview.cycleCount(c)) }
            }
        }
    }

    private func sensorsTile(_ s: Snapshot, _ unit: TemperatureUnit) -> some View {
        let t = s.sensors
        return OverviewTile(module: .sensors, key: Theme.temp, status: (L10n.Overview.thermal(t.thermal.rawValue), ThermalText.color(t.thermal))) {
            BigValue(value: t.cpuAverage.map { Format.temperatureNumber($0, unit: unit) + "°" } ?? L10n.Common.dash, unit: L10n.Overview.cpuTemp, color: Theme.temp)
        } aside: {
            EmptyView()
        } chart: {
            chart(.area, [ChartSeries(id: "t", points: monitor.history.points(.cpuTemp, range: .m5), color: Theme.temp, fill: 0.2, lineWidth: 1.5)], max: 100)
        } rows: {
            TileRow(label: L10n.Overview.fan, value: t.fans.first.map { Format.rpm($0.rpm) } ?? L10n.Overview.noFan)
            TileRow(label: L10n.Panel.power, value: t.systemPower.map(Format.watts) ?? L10n.Common.dash)
        }
    }

    private func gpuTile(_ s: Snapshot, _ unit: TemperatureUnit) -> some View {
        let g = s.gpu
        return OverviewTile(module: .gpu, key: Theme.gpu, status: overLimit(.gpu)) {
            BigValue(value: Format.percent(g.utilization), color: Theme.gpu)
        } aside: {
            Text(g.temperature.map { Format.temperature($0, unit: unit, showUnit: true) } ?? "").ui(14).foregroundStyle(Theme.sub)
        } chart: {
            chart(.area, [ChartSeries(id: "g", points: monitor.history.points(.gpu, range: .m5), color: Theme.gpu, fill: 0.2, lineWidth: 1.5)], max: 100)
        } rows: {
            TileRow(label: L10n.Panel.vram, value: Format.memory(g.memoryUsed))
            TileRow(label: L10n.Panel.frequency, value: g.frequencyMHz.map(Format.frequency) ?? L10n.Common.dash)
            TileRow(label: L10n.Monitor.videoDecode, value: MediaText.state(g.decodeWatts))
        }
    }

    /// The busiest moments of the last 24 hours; opens the CPU page's lookback.
    private func peakTile() -> some View {
        let peaks = monitor.history.cpuPeaks()
        let top = peaks.first
        return OverviewTile(module: .cpu, title: L10n.Overview.cpuPeaks, key: Theme.cpu, status: nil,
                            action: { CPUPage.requestedRange = .h24; Navigator.shared.page = .monitor(.cpu) }) {
            BigValue(value: top.map { Format.percent($0.value / 100) } ?? L10n.Common.dash, unit: top?.top.first?.name, color: Theme.cpu)
        } aside: {
            if let top { Text(Format.dayAndTime(top.date)).ui(12).foregroundStyle(Theme.sub).lineLimit(1) }
        } chart: {
            chart(.area, [ChartSeries(id: "c", points: monitor.history.points(.cpu, range: .h24), color: Theme.cpu, fill: 0.16, lineWidth: 1.5)],
                  range: .h24, max: 100, markers: peaks)
                .accessibilityLabel(L10n.Monitor.cpuChartA11y(TimeRange.h24.title))
        } rows: {
            if peaks.isEmpty { TileRow(label: L10n.Monitor.noPeaks, value: "") }
            ForEach(peaks.dropFirst().prefix(2)) { p in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(p.top.first?.name ?? L10n.Common.dash).ui(14).foregroundStyle(Theme.sub).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(Format.percent(p.value / 100)).ui(14, 500).fixedSize()
                    Text(Format.time(p.date)).ui(12).foregroundStyle(Theme.sub).fixedSize()
                }
                .frame(height: 20)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// The lowest device leads; the others read down to the bottom with their levels as cells.
    private func bluetoothTile(_ s: Snapshot) -> some View {
        let lowCount = MenuBarText.lowDevices(s, settings.prefs).count
        let devices = s.bluetooth.withBattery.sorted { ($0.level ?? 1) < ($1.level ?? 1) }
        let first = devices.first
        let firstLow = first.map { BluetoothText.isLow($0, settings.prefs) } ?? false
        return OverviewTile(module: .bluetooth, key: Theme.neutral, status: lowCount > 0 ? (L10n.Bluetooth.lowCount(lowCount), Theme.danger) : nil) {
            BigValue(value: first?.level.map(Format.percent) ?? L10n.Common.dash, unit: first?.name, color: firstLow ? Theme.danger : Theme.text)
        } aside: {
            EmptyView()
        } chart: {
            VStack(alignment: .leading, spacing: 10) {
                Spacer(minLength: 0)
                if devices.isEmpty { Text(L10n.Bluetooth.noDevices).ui(14).foregroundStyle(Theme.sub) }
                ForEach(devices.dropFirst().prefix(3)) { d in
                    let low = BluetoothText.isLow(d, settings.prefs)
                    VStack(alignment: .leading, spacing: 4) {
                        TileRow(label: d.name, value: Format.percent(d.level ?? 0), valueColor: low ? Theme.danger : Theme.text)
                        LevelBar(fraction: d.level ?? 0, color: low ? Theme.danger : Theme.bat, height: 6)
                    }
                }
            }
        } rows: {
            EmptyView()
        }
    }

    private func processRows(_ list: [ProcessUsage], value: @escaping (ProcessUsage) -> String) -> some View {
        ForEach(list) { p in
            // No icon here, so a long name ("WindowServer") still fits beside its value.
            TileRow(label: p.name, value: value(p))
        }
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

/// A label on the left in grey, its value on the right (the overview tiles' rows).
private struct TileRow: View {
    var label: String
    var value: String
    var valueColor: Color = Theme.text
    /// A short label ("公网") stays whole and a long value (an address) gives way instead.
    var keepLabel = false

    var body: some View {
        HStack(spacing: 8) {
            if keepLabel {
                Text(label).ui(14).foregroundStyle(Theme.sub).lineLimit(1).fixedSize()
                Spacer(minLength: 8)
                Text(value).ui(14, 500).foregroundStyle(valueColor).lineLimit(1).truncationMode(.middle)
            } else {
                Text(label).ui(14).foregroundStyle(Theme.sub).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
                Text(value).ui(14, 500).foregroundStyle(valueColor).lineLimit(1).fixedSize()
            }
        }
        .frame(height: 20)
        .accessibilityElement(children: .combine)
    }
}

/// Tiles in rows of three (two when narrow) that share the height they are given.
private struct FillGrid: Layout {
    var spacing: CGFloat = 10
    var minWidth: CGFloat = 176

    private func columns(_ width: CGFloat) -> Int { width.isFinite && (width + spacing) / (minWidth + spacing) < 3 ? 2 : 3 }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 600
        let cols = columns(width)
        let rows = max(1, Int(ceil(Double(subviews.count) / Double(cols))))
        let w = (width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        let natural = subviews.map { $0.sizeThatFits(ProposedViewSize(width: w, height: nil)).height }.max() ?? 0
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? (natural * CGFloat(rows) + spacing * CGFloat(rows - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cols = columns(bounds.width)
        let rows = max(1, Int(ceil(Double(subviews.count) / Double(cols))))
        let w = (bounds.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        let h = (bounds.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
        for (i, view) in subviews.enumerated() {
            let x = bounds.minX + CGFloat(i % cols) * (w + spacing)
            let y = bounds.minY + CGFloat(i / cols) * (h + spacing)
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: h))
        }
    }
}

private struct OverviewEditButton: View {
    var editing: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        let label = editing ? L10n.Overview.done : L10n.Overview.edit
        Button(action: action) {
            LineIcon(d: editing ? Icons.check : Icons.pencil, size: 14, lineWidth: 1.5)
                .foregroundStyle(editing || hovering ? Theme.text : Theme.sub)
                .frame(width: 30, height: 22)
                .background {
                    if editing { GlassThumb() } else if hovering { RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.lgHover) }
                }
                .hoverAnimation(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(2)
        .background(GlassTrack())
        .help(label)
        .accessibilityLabel(label)
        .accessibilityHint(editing ? "" : L10n.Overview.editA11y)
        .accessibilityAddTraits(editing ? [.isSelected] : [])
    }
}

private struct OverviewEditingKey: EnvironmentKey { static let defaultValue = false }

private extension EnvironmentValues {
    var overviewEditing: Bool {
        get { self[OverviewEditingKey.self] }
        set { self[OverviewEditingKey.self] = newValue }
    }
}

/// An overview tile: the module's color key, name and status; a 28 pt reading with a note on
/// the right; a small chart that takes the height left; rows of details at the bottom. The
/// whole tile opens its page and lightens under the pointer; in edit mode it shows the module's switch.
private struct OverviewTile<Value: View, Aside: View, Chart: View, Rows: View>: View {
    let module: Module
    var title: String? = nil
    var key: Color
    var status: (String, Color)?
    var action: (() -> Void)? = nil
    @ViewBuilder var value: Value
    @ViewBuilder var aside: Aside
    @ViewBuilder var chart: Chart
    @ViewBuilder var rows: Rows
    @State private var hovering = false
    @Environment(\.overviewEditing) private var editing
    var settings = SettingsStore.shared

    /// The CPU peak tile rides on the CPU module's switch, so it shows none of its own.
    private var hasSwitch: Bool { title == nil }

    var body: some View {
        if editing {
            tile(on: settings.prefs.isEnabled(module))
        } else {
            Button {
                if let action { action() } else { Navigator.shared.page = .monitor(module) }
            } label: {
                tile(on: true)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityHint(L10n.Panel.openMonitor(module.title))
        }
    }

    private func tile(on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(key).frame(width: 8, height: 8)
                Text(title ?? module.title).ui(16, 600).lineLimit(1)
                Spacer(minLength: 0)
                if editing {
                    if hasSwitch {
                        RinSwitch(isOn: Binding(get: { settings.prefs.isEnabled(module) },
                                                set: { v in withAnimation(Motion.slide) { settings.prefs.setEnabled(module, v) } }),
                                  label: L10n.Overview.moduleSwitch(module.title))
                    }
                } else if let status {
                    StatusText(text: status.0, color: status.1)
                }
            }
            .frame(height: 20)
            Group {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    value
                    Spacer(minLength: 0)
                    aside.lineLimit(1).fixedSize()
                }
                .frame(height: 30)
                .padding(.top, 8)
                chart
                    .frame(maxHeight: .infinity)
                    .padding(.top, 10)
                VStack(alignment: .leading, spacing: 2) { rows }
                    .padding(.top, 8)
            }
            .opacity(on ? 1 : 0.35)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PanelBackground(fill: hovering && !editing ? Theme.panelHover : Theme.panel))
        .hoverAnimation(hovering)
        .contentShape(Rectangle())
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
        let unit = settings.prefs.general.temperatureUnit

        MonitorPageLayout(module: .cpu, range: $range) {
            ConsolePanel(tint: Theme.cpu) {
                PageHero {
                    BigValue(value: Format.percent(s.cpu.total), size: 40, color: Theme.cpu)
                    HStack(spacing: 14) {
                        KeyValue(label: L10n.Panel.user, value: Format.percent(s.cpu.user), key: Theme.cpu)
                        KeyValue(label: L10n.Panel.system, value: Format.percent(s.cpu.system), key: Theme.sys)
                        KeyValue(label: L10n.Monitor.idle, value: Format.percent(max(0, 1 - s.cpu.total)), key: Theme.track)
                    }
                } trailing: {
                    if lookback {
                        WellButton(title: L10n.Monitor.backToNow, height: 24, radius: 6, fontSize: 12) { range = .m5 }
                    } else if let top = peaks.first {
                        peakLink(top)
                    }
                }
                ConsoleChart(
                    kind: lookback ? .area : .bars,
                    series: lookback
                        ? [ChartSeries(id: "total", points: history.points(.cpu, range: range), color: Theme.cpu, fill: 0.16, lineWidth: 1.5)]
                        : [ChartSeries(id: "total", points: history.points(.cpu, range: range), color: Theme.cpu),
                           ChartSeries(id: "system", points: history.points(.cpuSystem, range: range), color: Theme.sys)],
                    range: range, maxValue: 100, height: lookback ? 150 : 114, yLabels: ChartScale.percent,
                    rules: AlertRules.chartRule(.cpu, fraction: settings.prefs.alerts.cpuThreshold / 100, settings.prefs),
                    markers: lookback ? peaks : [], selectedMarker: lookback ? selected?.date : nil, markerColor: Theme.cpu,
                    hoverText: { hoverLines($0) },
                    onTap: { date in
                        guard lookback else { return }
                        if let nearest = peaks.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }),
                           abs(nearest.date.timeIntervalSince(date)) < range.seconds / 30 { selectedPeak = nearest.date }
                    },
                    pinnedTip: lookback ? selected.map { peakTip($0) } : nil
                )
                .accessibilityLabel(L10n.Monitor.cpuChartA11y(range.title))
            }

            if lookback {
                ListPanel(title: L10n.Monitor.peaks24h) {
                    VStack(spacing: 0) {
                        if peaks.isEmpty {
                            Text(L10n.Monitor.noPeaks).ui(14).foregroundStyle(Theme.sub)
                                .frame(maxWidth: .infinity, alignment: .leading).frame(height: 28)
                        }
                        ForEach(peaks) { peak in
                            PeakRow(peak: peak, selected: peak.date == selected?.date) { selectedPeak = peak.date }
                        }
                    }
                    .slidingThumb(selected?.date) { RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.selection) }
                }
                ListPanel(title: selected.map { L10n.Monitor.peakTop(Format.dayAndTime($0.date)) } ?? L10n.Monitor.peakTopNone) {
                    PeakProcessList(processes: selected?.top ?? [])
                }
            } else {
                KPIStrip {
                    KPICell(label: L10n.Monitor.loadAverage1) {
                        BigValue(value: Format.load(s.cpu.load.0))
                    } extra: {
                        KeyValue(label: L10n.Monitor.load5, value: Format.load(s.cpu.load.1))
                        KeyValue(label: L10n.Monitor.load15, value: Format.load(s.cpu.load.2))
                    }
                    KPICell(label: L10n.Monitor.frequencyAll) {
                        let f = Format.parts(s.cpu.frequencyMHz.map(Format.frequency) ?? L10n.Common.dash)
                        BigValue(value: f.0, unit: f.1)
                    } extra: {
                        if SystemInfo.efficiencyCores > 0 {
                            KeyValue(label: L10n.Monitor.performanceCores, value: s.cpu.performanceMHz.map { Format.parts(Format.frequency($0)).0 } ?? L10n.Common.dash)
                            KeyValue(label: L10n.Monitor.efficiencyCores, value: s.cpu.efficiencyMHz.map { Format.parts(Format.frequency($0)).0 } ?? L10n.Common.dash)
                        }
                    }
                    KPICell(label: L10n.Panel.temperature) {
                        BigValue(value: s.sensors.cpuAverage.map { Format.temperatureNumber($0, unit: unit) } ?? L10n.Common.dash,
                                 unit: s.sensors.cpuAverage == nil ? nil : Format.temperatureSymbol(unit))
                    } extra: {
                        if let w = s.sensors.cpuPower { KeyValue(label: L10n.Panel.power, value: Format.watts(w)) }
                    }
                }
                ConsolePanel {
                    PanelTitle(title: L10n.Panel.cores) { Text(L10n.Monitor.coreTotal(s.cpu.perCore.count)) }
                    CoreCharts(cpu: s.cpu, recent: history.recentCores).padding(.top, 10)
                }
                ListPanel(title: L10n.Monitor.topCPU, note: L10n.Monitor.processThreads(grouped(s.processes.processCount), grouped(s.processes.threadCount)), link: .cpu) {
                    let list = Array(s.processes.byCPU.prefix(4))
                    ProcessTable(processes: list, fraction: { $0.cpu / 40 }, color: Theme.cpu,
                                 value: { Format.percentValue($0.cpu) }, valueWidth: 52)
                }
            }
        }
    }

    private func peakLink(_ peak: PeakMarker) -> some View {
        Button {
            selectedPeak = peak.date
            range = .h24
        } label: {
            ViewThatFits(in: .horizontal) {
                peakLabel(peak, when: true)
                peakLabel(peak, when: false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func peakLabel(_ peak: PeakMarker, when: Bool) -> some View {
        HStack(spacing: 6) {
            Text(L10n.Monitor.peak24h).foregroundStyle(Theme.sub)
            Text(Format.percent(peak.value / 100)).ui(12, 500).foregroundStyle(Theme.text)
            if when { Text(L10n.Monitor.peakWhen(Format.dayAndTime(peak.date))).foregroundStyle(Theme.sub) }
            LineIcon(d: "M1 1l4 4-4 4", width: 6, height: 10, viewBox: CGSize(width: 6, height: 10), lineWidth: 1.5)
                .foregroundStyle(Theme.sub)
        }
        .ui(12)
        .fixedSize()
    }

    private func peakTip(_ p: PeakMarker) -> [String] {
        [Format.dayAndTime(p.date) + "\t" + Format.percent(p.value / 100)] + p.top.prefix(2).map { "\($0.name)\t\(Format.percent($0.cpu / 100))" }
    }

    private func hoverLines(_ date: Date) -> [String] {
        let history = monitor.history
        if range == .h24 || range == .d7, let b = history.bucket(near: date), !b.max[Metric.cpu.rawValue].isNaN {
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

/// Every core's last dozen readings as small stacked bars (system under user) with its current
/// share underneath; performance and efficiency cores in two groups split by a rule.
struct CoreCharts: View {
    var cpu: CPUSample
    var recent: [[(total: Double, system: Double)]]

    var body: some View {
        let groups = groupsOf(cpu)
        ShareRow(spacing: 16) {
            ForEach(groups.indices, id: \.self) { g in
                if g > 0 { Rectangle().fill(Theme.grid).frame(width: 1) }
                VStack(alignment: .leading, spacing: 8) {
                    KeyValue(label: groups[g].label, value: Format.percent(groups[g].average)).frame(height: 16)
                    HStack(spacing: 4) {
                        ForEach(groups[g].indices, id: \.self) { i in
                            core(i).help(groups[g].tip(groups[g].indices.firstIndex(of: i)! + 1, Format.percent(cpu.perCore[i]), Format.percent(system(i))))
                        }
                    }
                }
                .share(CGFloat(groups[g].indices.count))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(groups.map { g in
            L10n.Monitor.coresA11y(g.label, g.indices.map { Format.percent(cpu.perCore[$0]) }.joined(separator: L10n.A11y.separator))
        }.joined(separator: L10n.A11y.separator))
    }

    private func system(_ i: Int) -> Double { i < cpu.perCoreSystem.count ? cpu.perCoreSystem[i] : 0 }

    private func core(_ i: Int) -> some View {
        let samples = recent.compactMap { i < $0.count ? $0[i] : nil }
        return VStack(spacing: 6) {
            Canvas { ctx, size in
                let n = 12
                let w = size.width / CGFloat(n)
                for (k, v) in samples.suffix(n).enumerated() {
                    let x = CGFloat(n - min(samples.count, n) + k) * w + w * 0.14
                    let total = min(1, max(0, v.total)) * size.height
                    let sys = min(total, min(1, max(0, v.system)) * size.height)
                    ctx.fill(Path(CGRect(x: x, y: size.height - total, width: w * 0.72, height: total - sys)), with: .color(Theme.cpu))
                    ctx.fill(Path(CGRect(x: x, y: size.height - sys, width: w * 0.72, height: sys)), with: .color(Theme.sys))
                }
                ctx.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)), with: .color(Theme.grid))
            }
            .frame(height: 28)
            Text(Format.percent(cpu.perCore[i])).ui(14, 500).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
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

struct PeakRow: View {
    var peak: PeakMarker
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Format.dayAndTime(peak.date)).ui(14, 500)
                    Text(peak.top.first?.name ?? L10n.Common.dash).ui(12).foregroundStyle(Theme.sub)
                }
                Spacer()
                Text(Format.percent(peak.value / 100)).ui(16, 500)
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
                Text(L10n.Panel.noProcesses).ui(14).foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 34)
            }
            ForEach(processes, id: \.self) { p in
                HStack(spacing: 10) {
                    LetterTile(name: p.name)
                    Text(p.name).lineLimit(1).frame(width: 130, alignment: .leading)
                    MeterBar(fraction: p.cpu / maxValue, color: Theme.cpu)
                    Text(Format.percentValue(p.cpu)).ui(14, 500).frame(width: 60, alignment: .trailing)
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
        let unit = settings.prefs.general.temperatureUnit
        let vram = g.memoryLimit > 0 ? Double(g.memoryUsed) / Double(g.memoryLimit) : 0
        let ghz = { (mhz: Double?) in mhz.map { String(format: "%.2f", $0 / 1000) } ?? L10n.Common.dash }
        MonitorPageLayout(module: .gpu, range: $range) {
            ConsolePanel(tint: Theme.gpu) {
                PageHero {
                    BigValue(value: Format.percent(g.utilization), size: 40, color: Theme.gpu)
                    HStack(spacing: 14) {
                        if let r = g.renderer { KeyValue(label: L10n.Monitor.renderer, value: Format.percent(r)) }
                        if let t = g.tiler { KeyValue(label: L10n.Monitor.tiler, value: Format.percent(t)) }
                    }
                } trailing: {
                    if g.cores > 0 { Text(L10n.Monitor.gpuCores(g.cores)) }
                }
                ConsoleChart(kind: .bars, series: [ChartSeries(id: "gpu", points: history.points(.gpu, range: range), color: Theme.gpu)],
                             range: range, maxValue: 100, height: 145, yLabels: ChartScale.percent,
                             rules: AlertRules.chartRule(.gpu, fraction: settings.prefs.alerts.gpuThreshold / 100, settings.prefs),
                             hoverText: { hover($0) })
                    .alertBell(.gpu)
                    .accessibilityLabel(L10n.Monitor.gpuChartA11y(range.title))
            }
            KPIStrip {
                KPICell(label: L10n.Monitor.vramUnified) {
                    let used = Format.parts(Format.memory(g.memoryUsed))
                    BigValue(value: used.0, unit: g.memoryLimit > 0 ? L10n.Monitor.ofTotal(Format.memory(g.memoryLimit)) : used.1)
                } extra: {
                    if g.memoryLimit > 0 {
                        LevelBar(fraction: vram, color: Theme.gpu)
                        Text(Format.percent(vram)).ui(14, 500)
                    }
                }
                KPICell(label: L10n.Panel.temperature) {
                    BigValue(value: g.temperature.map { Format.temperatureNumber($0, unit: unit) } ?? L10n.Common.dash,
                             unit: g.temperature == nil ? nil : Format.temperatureSymbol(unit))
                } extra: {
                    if let w = g.power { KeyValue(label: L10n.Panel.power, value: Format.watts(w)) }
                }
                KPICell(label: L10n.Panel.frequency) {
                    BigValue(value: ghz(g.frequencyMHz), unit: g.frequencyMHz == nil ? nil : L10n.Monitor.ghz)
                } extra: {
                    KeyValue(label: L10n.Monitor.average, value: ghz(g.averageMHz))
                    KeyValue(label: L10n.Monitor.highest, value: ghz(g.maxMHz))
                }
            }
            KPIStrip {
                media(L10n.Monitor.videoDecode, watts: g.decodeWatts)
                media(L10n.Monitor.videoEncode, watts: g.encodeWatts)
                KPICell(label: L10n.Monitor.frameRate) {
                    BigValue(value: g.fps.map { "\(Int($0.rounded()))" } ?? L10n.Common.dash, unit: L10n.Monitor.fps)
                } extra: {
                    if g.maxFPS > 60 { Text(L10n.Monitor.proMotion).ui(14).foregroundStyle(Theme.sub) }
                }
            }
            ListPanel(title: L10n.Monitor.topGPU, link: .gpu) {
                let list = Array(monitor.snapshot.processes.byGPU.prefix(4))
                let peak = max(list.map(\.gpu).max() ?? 1, 15)
                ProcessTable(processes: list, fraction: { $0.gpu / peak }, color: Theme.gpu, value: { Format.percentValue($0.gpu) }, valueWidth: 52)
            }
        }
    }

    /// Media engines report energy, not load or codec: the power and whether it is working.
    private func media(_ title: String, watts: Double?) -> some View {
        let active = (watts ?? 0) >= 0.01
        let w = Format.parts(watts.map(Format.watts) ?? L10n.Common.dash)
        return KPICell(label: title) {
            BigValue(value: w.0, unit: w.1)
        } extra: {
            Text(active ? L10n.Monitor.activeState : L10n.Monitor.idleState).ui(14).foregroundStyle(Theme.sub)
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
    var settings = SettingsStore.shared
    @State private var range: TimeRange = .m5

    var body: some View {
        let s = monitor.snapshot
        let m = s.memory
        let _ = monitor.tick
        let pr = PanelText.pressure(m.pressure)
        let alertAt = settings.prefs.alerts.memoryLevel == .critical ? 0.8 : 0.5
        MonitorPageLayout(module: .memory, range: $range) {
            ConsolePanel(tint: Theme.mem) {
                PageHero {
                    BigValue(value: Format.percent(m.usedFraction), size: 40, color: Theme.mem)
                    Text(L10n.Monitor.usedOfTotal(Format.memory(m.used), Format.memory(m.total))).ui(12).foregroundStyle(Theme.sub)
                }
                SegmentBar(parts: MemoryParts.of(m).map { ($0.bytes, $0.color) }, height: 12)
                    .accessibilityElement()
                    .accessibilityLabel(L10n.Monitor.compositionA11y(Format.memory(m.app), Format.memory(m.wired), Format.memory(m.compressed), Format.memory(m.cached), Format.memory(m.free)))
                StackLegend(items: MemoryParts.of(m).map { .init(label: $0.label, value: Format.memory(UInt64($0.bytes)), color: $0.color) })
                    .padding(.top, 10)
                    .accessibilityHidden(true)
            }
            ConsolePanel {
                PanelTitle(title: L10n.Monitor.memoryPressure) {
                    StatusText(text: pr.0, color: pr.1)
                    Text(Format.percent(m.pressureLevel)).ui(14, 500).foregroundStyle(Theme.text)
                    KeyValue(label: L10n.Memory.swap, value: Format.memory(m.swapUsed))
                    if m.swapTotal > 0 { Text(L10n.Monitor.swapFile(Format.memory(m.swapTotal))) }
                }
                ConsoleChart(kind: .area, series: [ChartSeries(id: "pressure", points: monitor.history.points(.memoryPressure, range: range), color: Theme.mem, fill: 0.18, lineWidth: 1.5)],
                             range: range, maxValue: 100, height: 210, yLabels: ChartScale.percent, grid: [0.25, 0.75],
                             rules: [ChartRule(fraction: 0.5, color: Theme.warn)] + AlertRules.chartRule(.memory, fraction: alertAt, settings.prefs),
                             hoverText: { date in hoverLine(.memoryPressure, range, date) { Format.percent($0 / 100) } })
                    .alertBell(.memory)
                    .padding(.top, 12)
                    .accessibilityLabel(L10n.Monitor.memoryChartA11y(range.title))
            }
            ListPanel(title: L10n.Monitor.topMemory, link: .memory) {
                let list = Array(s.processes.byMemory.prefix(5))
                let peak = max(Double(list.map(\.memory).max() ?? 1), 1) * 1.1
                ProcessTable(processes: list, fraction: { Double($0.memory) / peak }, color: Theme.mem, value: { Format.memory($0.memory) }, valueWidth: 60)
            }
        }
    }
}

/// Memory by kind, in the order and colors the bar and its legend use.
enum MemoryParts {
    struct Part {
        var label: String
        var bytes: Double
        var color: Color
    }

    static func of(_ m: MemorySample) -> [Part] {
        [Part(label: L10n.Monitor.appMemory, bytes: Double(m.app), color: Theme.mem),
         Part(label: L10n.Memory.wired, bytes: Double(m.wired), color: Theme.memWired),
         Part(label: L10n.Monitor.compressed, bytes: Double(m.compressed), color: Theme.memCompressed),
         Part(label: L10n.Monitor.cache, bytes: Double(m.cached), color: Theme.memCache),
         Part(label: L10n.Memory.free, bytes: Double(m.free), color: Theme.track)]
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
        let history = monitor.history
        let down = history.points(.netDown, range: range)
        let up = history.points(.netUp, range: range)
        let dMax = ConsoleChart.niceMax(max(down.map(\.value).max() ?? 0, 10_000) * 1.1)
        let uMax = ConsoleChart.niceMax(max(up.map(\.value).max() ?? 0, 10_000) * 1.1)
        MonitorPageLayout(module: .network, range: $range) {
            ConsolePanel(tint: Theme.down) {
                HStack(alignment: .top, spacing: 16) {
                    flow(L10n.Panel.download, MenuBarText.downArrow, n.down, unit: unit, color: Theme.down, session: n.sessionDown, today: n.todayDown)
                    flow(L10n.Panel.upload, MenuBarText.upArrow, n.up, unit: unit, color: Theme.up, session: n.sessionUp, today: n.todayUp)
                }
                .padding(.bottom, 12)
                ConsoleChart(kind: .mirrored, series: [ChartSeries(id: "down", points: down, color: Theme.down), ChartSeries(id: "up", points: up, color: Theme.up)],
                             range: range, maxValue: dMax, bottomMax: uMax, height: 109,
                             yLabels: [(1, Format.rate(dMax, unit: unit)), (0.5, "0"), (0, Format.rate(uMax, unit: unit))],
                             gutter: 64, grid: [0.25, 0.75], baseline: false, hoverText: { hover($0) })
                    .overlay(alignment: .topTrailing) { ChartAlertBadge(rule: .network).padding(.trailing, 70).padding(.top, 4) }
                    .accessibilityLabel(L10n.Monitor.networkChartA11y(range.title))
            }
            KPIStrip {
                KPICell(label: L10n.Monitor.connection) {
                    Text(n.interface.isEmpty ? PanelText.kindName(n.kind) : L10n.Settings.interfaceOption(PanelText.kindName(n.kind), n.interface)).ui(16, 500).minimumScaleFactor(0.7)
                } extra: {
                    StatusText(text: n.connected ? L10n.Overview.connected : L10n.Panel.notConnected, color: n.connected ? Theme.ok : Theme.sub)
                }
                KPICell(label: L10n.Monitor.localIPTitle) {
                    Text(n.localIP.isEmpty ? L10n.Common.dash : n.localIP).ui(16, 500).minimumScaleFactor(0.7)
                } extra: {
                    if !n.router.isEmpty { KeyValue(label: L10n.Network.router, value: n.router) }
                }
                if settings.prefs.network.showPublicIP {
                    KPICell(label: L10n.Monitor.publicIPTitle) {
                        Text(n.connected ? (monitor.publicIP ?? L10n.Common.dash) : L10n.Common.dash).ui(16, 500).minimumScaleFactor(0.7)
                    }
                }
                if settings.prefs.network.showLatency {
                    KPICell(label: L10n.Monitor.latency) {
                        BigValue(value: n.latencyMS.map { "\(Int($0.rounded()))" } ?? L10n.Common.dash, unit: n.latencyMS == nil ? nil : L10n.Monitor.ms)
                    } extra: {
                        LatencyLine(values: n.latencies, color: Theme.down).frame(width: 120, height: 16)
                    }
                }
            }
            if settings.prefs.network.showLatency {
                ConsolePanel {
                    PanelTitle(title: L10n.Monitor.connectionLog)
                    ConnectionLog(checks: n.checks).padding(.top, 10)
                    HStack(spacing: 0) {
                        ForEach(Array(([24, 18, 12, 6].map { L10n.Chart.minutesShort($0) } + [L10n.Range.now]).enumerated()), id: \.offset) { i, t in
                            if i > 0 { Spacer(minLength: 4) }
                            Text(t)
                        }
                    }
                    .ui(12).foregroundStyle(Theme.sub)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
                }
            }
            ListPanel(title: L10n.Monitor.topNetwork, link: .network) {
                let list = Array(s.processes.byNetwork.prefix(4))
                let peak = max(list.map(\.netDown).max() ?? 1, 0.0001) * 1.1
                ProcessTable(processes: list, fraction: { $0.netDown / peak }, color: Theme.down,
                             value: { MenuBarText.downArrow + " " + Format.rate($0.netDown, unit: unit) }, valueWidth: 84,
                             secondary: { MenuBarText.upArrow + " " + Format.rate($0.netUp, unit: unit) }, secondaryWidth: 76, nameWidth: 100, minRows: 4)
            }
        }
    }

    private func flow(_ label: String, _ arrow: String, _ rate: Double, unit: SpeedUnit, color: Color, session: UInt64, today: UInt64) -> some View {
        let parts = Format.rateParts(rate, unit: unit)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 8, height: 8)
                Text(arrow + " " + label).ui(14).foregroundStyle(Theme.sub)
            }
            // Both directions of the one reading wear the network's color.
            BigValue(value: parts.0, unit: parts.1, size: 40, color: Theme.down)
            Text(L10n.Monitor.sessionToday(Format.storage(session), Format.storage(today))).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func hover(_ date: Date) -> [String] {
        let d = monitor.history.points(.netDown, range: range)
        let u = monitor.history.points(.netUp, range: range)
        guard let i = nearest(d, date) else { return [] }
        return [timeLabel(d[i].date, range), L10n.Panel.download + "\t" + Format.rate(d[i].value), L10n.Panel.upload + "\t" + Format.rate(i < u.count ? u[i].value : 0)]
    }
}

/// A small line of recent readings, gaps where nothing was measured.
struct LatencyLine: View {
    var values: [Double?]
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let vs = values.compactMap { $0 }
            guard vs.count > 1, let lo = vs.min(), let hi = vs.max() else { return }
            let span = max(hi - lo, 1)
            let step = size.width / CGFloat(max(values.count - 1, 1))
            var path = Path()
            var drawing = false
            for (i, v) in values.enumerated() {
                guard let v else { drawing = false; continue }
                let p = CGPoint(x: CGFloat(i) * step, y: size.height - 1 - CGFloat((v - lo) / span) * (size.height - 2))
                if drawing { path.addLine(to: p) } else { path.move(to: p); drawing = true }
            }
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// The last 48 connection checks (one every 30 seconds) as cells: ok, slow, failed.
struct ConnectionLog: View {
    var checks: [ConnectionCheck]

    var body: some View {
        let slots = Array(repeating: ConnectionCheck?.none, count: max(0, 48 - checks.count)) + checks.suffix(48).map { Optional($0) }
        HStack(spacing: 1) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, c in
                RoundedRectangle(cornerRadius: 1, style: .continuous).fill(color(c))
            }
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityLabel(L10n.Monitor.checksA11y(checks.count, checks.filter { $0 == .ok }.count,
                                                    checks.filter { $0 == .slow }.count, checks.filter { $0 == .failed }.count))
    }

    private func color(_ c: ConnectionCheck?) -> Color {
        switch c {
        case .ok: return Theme.ok
        case .slow: return Theme.warn
        case .failed: return Theme.danger
        case .unmeasured, nil: return Theme.track
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
        let reads = monitor.history.points(.diskRead, range: range)
        let writes = monitor.history.points(.diskWrite, range: range)
        let rMax = ConsoleChart.niceMax(max(reads.map(\.value).max() ?? 0, 1_000_000) * 1.1)
        let wMax = ConsoleChart.niceMax(max(writes.map(\.value).max() ?? 0, 1_000_000) * 1.1)
        MonitorPageLayout(module: .disk, range: $range) {
            if !d.volumes.isEmpty {
                ConsolePanel(tint: Theme.disk) {
                    ForEach(Array(d.volumes.enumerated()), id: \.element.id) { i, v in
                        if i > 0 { ConsoleRule().padding(.vertical, 12) }
                        VolumeRow(volume: v, alert: v.isRoot && Alerts.Rule.disk.isOn(settings.prefs) ? AlertText.pill(.disk, settings.prefs) : nil)
                    }
                }
            }
            ConsolePanel {
                PageHero {
                    rate(L10n.Disk.read, d.read, Theme.read)
                    rate(L10n.Disk.write, d.write, Theme.write)
                } trailing: {
                    KeyValue(label: L10n.Disk.writeSinceBoot, value: Format.storage(d.totalWritten))
                    KeyValue(label: L10n.Monitor.readTotal, value: Format.storage(d.totalRead))
                }
                ConsoleChart(kind: .mirrored, series: [ChartSeries(id: "read", points: reads, color: Theme.read), ChartSeries(id: "write", points: writes, color: Theme.write)],
                             range: range, maxValue: rMax, bottomMax: wMax, height: 114,
                             yLabels: [(1, Format.rate(rMax)), (0.5, "0"), (0, Format.rate(wMax))],
                             gutter: 64, grid: [0.25, 0.75], baseline: false, hoverText: { hover($0) })
                    .accessibilityLabel(L10n.Monitor.diskChartA11y(range.title))
            }
            if let h = d.health, let root = d.root {
                KPIStrip {
                    KPICell(label: L10n.Monitor.smart) {
                        BigValue(value: h.ok ? L10n.Monitor.good : L10n.Monitor.failing, color: h.ok ? Theme.ok : Theme.danger)
                    } extra: {
                        Text(L10n.Monitor.diskHealth(root.name)).ui(12).foregroundStyle(Theme.sub)
                    }
                    KPICell(label: L10n.Monitor.lifeRemaining) {
                        BigValue(value: Format.percent(h.lifeRemaining))
                    } extra: {
                        LevelBar(fraction: h.lifeRemaining, color: h.lifeRemaining >= 0.1 ? Theme.disk : Theme.danger)
                    }
                    KPICell(label: L10n.Monitor.totalWritten) {
                        let w = Format.parts(Format.storage(h.totalWritten))
                        BigValue(value: w.0, unit: w.1)
                    }
                    KPICell(label: L10n.Panel.temperature) {
                        BigValue(value: h.temperature.map { Format.temperatureNumber($0, unit: unit) } ?? L10n.Common.dash,
                                 unit: h.temperature == nil ? nil : Format.temperatureSymbol(unit))
                    }
                }
            }
            ListPanel(title: L10n.Monitor.topReadWrite, link: .disk) {
                let list = Array(s.processes.byDisk.prefix(4))
                let peak = max(list.map(\.diskTotal).max() ?? 1, 0.0001) * 1.1
                ProcessTable(processes: list, fraction: { $0.diskTotal / peak }, color: Theme.read,
                             value: { L10n.Monitor.readRate(Format.rate($0.diskRead)) }, valueWidth: 92,
                             secondary: { L10n.Monitor.writeRate(Format.rate($0.diskWrite)) }, secondaryWidth: 84, nameWidth: 110)
            }
        }
    }

    private func rate(_ label: String, _ value: Double, _ color: Color) -> some View {
        let p = Format.parts(Format.rate(value))
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 8, height: 8)
            Text(label).ui(14).foregroundStyle(Theme.sub)
            BigValue(value: p.0, unit: p.1)
        }
        // The hero row has room; without this the spacer beside it squeezes the unit to "K".
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private func hover(_ date: Date) -> [String] {
        let r = monitor.history.points(.diskRead, range: range)
        let w = monitor.history.points(.diskWrite, range: range)
        guard let i = nearest(r, date) else { return [] }
        return [timeLabel(r[i].date, range), L10n.Disk.read + "\t" + Format.rate(r[i].value), L10n.Disk.write + "\t" + Format.rate(i < w.count ? w[i].value : 0)]
    }
}

/// A volume: name, internal / external tag, eject, free space; its capacity as a row of cells
/// (used, purgeable, free); the details and how full it is.
struct VolumeRow: View {
    var volume: Volume
    /// The free-space rule's tag, on the volume it watches.
    var alert: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(volume.name).ui(16, 600).lineLimit(1)
                TagText(text: volume.isInternal ? L10n.Disk.internalDrive : L10n.Disk.external)
                if volume.isEjectable && !volume.isRoot { EjectButton(volume: volume, size: 20) }
                Spacer(minLength: 0)
                let free = Format.parts(Format.storage(volume.available))
                BigValue(value: free.0, unit: L10n.Monitor.unitFree(free.1), size: 22, color: Theme.disk)
            }
            .frame(height: 22)
            CapacityCells(used: Double(max(0, volume.used - volume.purgeable)), purgeable: Double(volume.purgeable), total: Double(max(volume.total, 1)))
            HStack(spacing: 10) {
                Text(detail).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
                Spacer(minLength: 0)
                if let alert {
                    Button { MainWindowController.shared.showAlerts(focus: .disk) } label: {
                        HStack(spacing: 4) {
                            LineIcon(d: Icons.bell, size: 11, lineWidth: 1.5)
                            Text(alert).ui(12)
                        }
                        .foregroundStyle(Theme.danger)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.danger, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.Alerts.edit)
                }
                Text(Format.percent(volume.usedFraction)).ui(14, 500)
            }
            .frame(height: 18)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        volume.purgeable > 0
            ? L10n.Monitor.volumeUsedPurgeable(Format.storage(volume.used), Format.storage(volume.purgeable), Format.storage(volume.total))
            : L10n.Monitor.volumeUsed(Format.storage(volume.used), Format.storage(volume.total))
    }
}

/// A volume's capacity as cells: used, then purgeable in a lighter shade, then free.
struct CapacityCells: View {
    var used: Double
    var purgeable: Double
    var total: Double
    var height: CGFloat = 8

    var body: some View {
        Canvas { ctx, size in
            let n = max(16, Int(size.width / 9.5))
            let w = (size.width - 2 * CGFloat(n - 1)) / CGFloat(n)
            for i in 0..<n {
                let x = (Double(i) + 0.5) / Double(n) * total
                let color = x < used ? Theme.disk : (x < used + purgeable ? Theme.purgeable : Theme.track)
                ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i) * (w + 2), y: 0, width: w, height: size.height), cornerRadius: 1), with: .color(color))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
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
        let unit = settings.prefs.general.temperatureUnit
        MonitorPageLayout(module: .battery, range: b.hasBattery ? $range : nil, ranges: [.h24, .d7]) {
            if b.hasBattery {
                ConsolePanel {
                    PageHero {
                        BigValue(value: Format.percent(b.level), size: 40)
                        StatusText(text: status(b), color: statusColor(b))
                    } trailing: {
                        KeyValue(label: L10n.Battery.level, value: "", key: Theme.bat)
                        KeyValue(label: L10n.Monitor.chargingLegend, value: "", key: Theme.bat.opacity(0.3))
                    }
                    ConsoleChart(kind: .area, series: [ChartSeries(id: "battery", points: monitor.history.points(.battery, range: range), color: Theme.bat, fill: 0.16, lineWidth: 1.5)],
                                 range: range, maxValue: 100, height: 104, yLabels: ChartScale.percent,
                                 rules: AlertRules.chartRule(.battery, fraction: settings.prefs.alerts.batteryPercent / 100, settings.prefs),
                                 bands: ChargingBands.of(range), hoverText: { hover($0) })
                        .alertBell(.battery)
                        .accessibilityLabel(L10n.Monitor.batteryChartA11y(range.title))
                }
                powerPanel(b)
                KPIStrip {
                    let healthy = (b.health ?? 1) >= 0.8
                    KPICell(label: L10n.Monitor.batteryHealth) {
                        BigValue(value: b.health.map(Format.percent) ?? L10n.Common.dash, unit: L10n.Battery.health)
                    } extra: {
                        StatusText(text: healthy ? L10n.Monitor.healthNormal : L10n.Monitor.healthService, color: healthy ? Theme.ok : Theme.warn)
                    }
                    KPICell(label: L10n.Battery.cycles) {
                        let design = b.designCycles ?? 1000
                        BigValue(value: b.cycles.map { grouped($0) } ?? L10n.Common.dash, unit: L10n.Monitor.ofTotal(grouped(design)))
                    } extra: {
                        LevelBar(fraction: Double(b.cycles ?? 0) / Double(max(b.designCycles ?? 1000, 1)), color: Theme.bat)
                    }
                    KPICell(label: L10n.Battery.temperature) {
                        let t = b.temperature ?? s.sensors.value(.battery)
                        BigValue(value: t.map { Format.temperatureNumber($0, unit: unit) } ?? L10n.Common.dash, unit: t == nil ? nil : Format.temperatureSymbol(unit))
                    }
                    if let full = b.maxCapacity, let designCap = b.designCapacity {
                        KPICell(label: L10n.Monitor.capacity) {
                            BigValue(value: grouped(full), unit: L10n.Monitor.ofTotal(grouped(designCap)))
                        } extra: {
                            Text(L10n.Monitor.mAh).ui(12).foregroundStyle(Theme.sub)
                        }
                    }
                }
                energySection(s, wholeMac: b.onAC ? max(0, (b.systemPowerIn ?? 0) - max(0, b.power ?? 0)) : abs(b.power ?? 0))
            } else {
                ConsolePanel {
                    HStack(spacing: 12) {
                        LineIcon(d: Icons.batteryOff, size: 16, lineWidth: 1.5).foregroundStyle(Theme.sub)
                        Text(L10n.Battery.noBattery).ui(16, 500)
                    }
                }
            }
            if !b.ups.isEmpty {
                ListPanel(title: L10n.Battery.ups) {
                    VStack(spacing: 0) { DividedRows { ForEach(b.ups) { UPSRow(source: $0) } } }
                }
            }
            if !b.hasBattery { energySection(s, wholeMac: s.sensors.systemPower) }
        }
    }

    /// The apps drawing the most power, with the whole Mac's draw on the right.
    private func energySection(_ s: Snapshot, wholeMac: Double?) -> some View {
        let list = Array(s.processes.byEnergy.prefix(5))
        let peak = max(list.map(\.energy).max() ?? 1, 0.0001) * 1.1
        return ListPanel(title: L10n.Processes.topEnergy, note: wholeMac.map { L10n.Processes.wholeMac(Format.watts($0)) }, link: .energy) {
            ProcessTable(processes: list, fraction: { $0.energy / peak }, color: Theme.temp, value: { Format.appWatts($0.energy) }, valueWidth: 52)
        }
    }

    private func status(_ b: BatterySample) -> String {
        if b.isCharging, let m = b.minutesToFull { return L10n.Battery.charging + " · " + L10n.Battery.untilFull(BatteryTime.text(m)) }
        if b.isCharging { return L10n.Battery.charging }
        if b.onAC { return b.isCharged || b.level >= 0.99 ? L10n.Battery.charged : L10n.Battery.onAC }
        if let m = b.minutesToEmpty { return L10n.Battery.onBattery + " · " + L10n.Battery.remaining(BatteryTime.text(m)) }
        return L10n.Battery.onBattery
    }

    private func statusColor(_ b: BatterySample) -> Color {
        if b.isCharging || b.onAC { return Theme.ok }
        return b.level <= 0.2 ? Theme.danger : Theme.sub
    }

    /// Where the power goes: the Mac's draw, what charges the battery, what the adapter has left.
    private func powerPanel(_ b: BatterySample) -> some View {
        let charge = max(0, b.power ?? 0)
        let system = b.onAC ? max(0, (b.systemPowerIn ?? 0) - charge) : abs(b.power ?? 0)
        let adapter = Double(b.adapterWatts ?? 0)
        let headroom = max(0, adapter - system - charge)
        let items: [StackLegend.Item] = b.onAC
            ? [.init(label: L10n.Monitor.systemDraw, value: Format.watts(system), color: Theme.temp),
               .init(label: L10n.Monitor.chargePower, value: Format.watts(charge), color: Theme.bat),
               .init(label: L10n.Monitor.headroom, value: Format.watts(headroom), color: Theme.track)]
            : [.init(label: L10n.Monitor.systemDraw, value: Format.watts(system), color: Theme.temp)]
        return ConsolePanel {
            PanelTitle(title: L10n.Monitor.powerSource) {
                if b.onAC { KeyValue(label: L10n.Monitor.adapter, value: b.adapterWatts.map { "\($0) W" } ?? L10n.Common.dash) } else { Text(L10n.Battery.onBattery) }
            }
            SegmentBar(parts: b.onAC ? [(system, Theme.temp), (charge, Theme.bat), (headroom, Theme.track)] : [(1, Theme.temp)])
                .padding(.top, 10)
            StackLegend(items: items, columns: 3).padding(.top, 10)
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
            Text(Format.percent(source.level)).ui(14, 500).frame(width: 40, alignment: .trailing)
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
        let t = { (c: Double) in Format.temperature(c, unit: unit, showUnit: true) }
        MonitorPageLayout(module: .sensors, range: $range) {
            ConsolePanel(tint: Theme.temp) {
                PageHero {
                    BigValue(value: s.cpuAverage.map { Format.temperatureNumber($0, unit: unit) } ?? L10n.Common.dash, unit: Format.temperatureSymbol(unit), size: 40, color: Theme.temp)
                    Text(s.cpuMax.map { L10n.Monitor.cpuAverageMax(t($0)) } ?? L10n.Monitor.cpuAverageShort).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
                } trailing: {
                    KeyValue(label: L10n.Sensors.thermalState, value: PanelText.thermal(s.thermal).0, valueColor: ThermalText.color(s.thermal))
                }
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { i in
                        let on = i == s.thermal.rawValue
                        VStack(alignment: .leading, spacing: 4) {
                            Capsule().fill(on ? ThermalText.color(s.thermal) : Theme.track).frame(height: 4)
                            Text(L10n.Monitor.thermalLevel(i)).ui(14).foregroundStyle(on ? Theme.text : Theme.sub)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.bottom, 14)
                .accessibilityHidden(true)
                PanelTitle(title: L10n.Monitor.cpuAverageTitle) {
                    KeyValue(label: L10n.Monitor.zoneLow(t(70)), value: "", key: Theme.ok)
                    KeyValue(label: L10n.Monitor.zoneMid(Format.temperatureNumber(70, unit: unit), t(90)), value: "", key: Theme.warn)
                    KeyValue(label: L10n.Monitor.zoneHigh(t(90)), value: "", key: Theme.danger)
                }
                ConsoleChart(kind: .area, series: [ChartSeries(id: "cpu", points: monitor.history.points(.cpuTemp, range: range), color: Theme.temp, fill: 0.16, lineWidth: 1.5)],
                             range: range, maxValue: 100, height: 170,
                             yLabels: [(0.9, Format.temperatureNumber(90, unit: unit)), (0.7, Format.temperatureNumber(70, unit: unit)), (0, Format.temperatureNumber(0, unit: unit))],
                             grid: [0.5],
                             rules: [ChartRule(fraction: 0.7, color: Theme.warn), ChartRule(fraction: 0.9, color: Theme.danger)]
                                + AlertRules.chartRule(.temperature, fraction: settings.prefs.alerts.tempThreshold / 100, settings.prefs),
                             hoverText: { date in hoverLine(.cpuTemp, range, date) { t($0) } })
                    .alertBell(.temperature)
                    .padding(.top, 10)
                    .accessibilityLabel(L10n.Monitor.tempChartA11y(range.title))
            }
            if !s.temps.isEmpty {
                ConsolePanel {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .leading), count: 4), alignment: .leading, spacing: 12) {
                        ForEach(s.temps) { r in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(PanelText.tempName(r.group)).ui(14).foregroundStyle(Theme.sub).lineLimit(1)
                                BigValue(value: Format.temperatureNumber(r.value, unit: unit), unit: Format.temperatureSymbol(unit), size: 20)
                                LevelBar(fraction: r.value / 100, color: TempZone.meter(r.value))
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: 10) {
                ConsolePanel {
                    PanelTitle(title: L10n.Sensors.fans) {
                        if !s.fans.isEmpty { TagText(text: s.fansAuto ? L10n.Monitor.fanAuto : L10n.Monitor.fanManual, color: Theme.text) }
                    }
                    if s.fans.isEmpty {
                        Text(L10n.Sensors.fanless).ui(14).foregroundStyle(Theme.sub).padding(.top, 6)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(s.fans.enumerated()), id: \.offset) { _, f in
                                HStack(spacing: 10) {
                                    Text(PanelText.fanName(f.id, count: s.fans.count)).ui(14).foregroundStyle(Theme.sub).lineLimit(1).frame(width: 52, alignment: .leading)
                                    LevelBar(fraction: f.max > f.min ? (f.rpm - f.min) / (f.max - f.min) : 0, color: Theme.temp)
                                    Text(Format.rpm(f.rpm)).ui(14, 500).frame(width: 80, alignment: .trailing)
                                }
                                .frame(height: 26)
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .padding(.top, 6)
                        if let f = s.fans.first, f.max > 0 {
                            Text(L10n.Monitor.fanRange(Int(f.min.rounded()), Int(f.max.rounded()))).ui(12).foregroundStyle(Theme.sub).padding(.top, 4)
                        }
                    }
                }
                powerPanel(s)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func powerPanel(_ s: SensorsSample) -> some View {
        let cpu = s.cpuPower ?? 0, gpu = s.gpuPower ?? 0
        let total = s.systemPower ?? (cpu + gpu)
        let other = max(0, total - cpu - gpu)
        return ConsolePanel {
            PanelTitle(title: L10n.Sensors.power) {
                KeyValue(label: L10n.Monitor.system, value: s.systemPower.map(Format.watts) ?? L10n.Common.dash)
            }
            SegmentBar(parts: [(cpu, Theme.cpu), (gpu, Theme.gpu), (other, Theme.neutral.opacity(0.4))]).padding(.top, 10)
            StackLegend(items: [.init(label: L10n.Module.cpu, value: s.cpuPower.map(Format.watts) ?? L10n.Common.dash, color: Theme.cpu),
                                .init(label: L10n.Module.gpu, value: s.gpuPower.map(Format.watts) ?? L10n.Common.dash, color: Theme.gpu),
                                .init(label: L10n.Monitor.other, value: s.systemPower == nil ? L10n.Common.dash : Format.watts(other), color: Theme.neutral.opacity(0.4))],
                        columns: 3)
                .padding(.top, 10)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

enum TempZone {
    static func color(_ celsius: Double) -> Color {
        celsius >= 90 ? Theme.danger : celsius >= 70 ? Theme.warn : Theme.ok
    }

    /// A sensor's meter: the module's orange until it runs hot.
    static func meter(_ celsius: Double) -> Color {
        celsius >= 90 ? Theme.danger : celsius >= 70 ? Theme.warn : Theme.temp
    }
}
