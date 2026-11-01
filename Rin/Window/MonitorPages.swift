import SwiftUI

func nearest(_ points: [ChartPoint], _ date: Date) -> Int? {
    points.indices.min { abs(points[$0].date.timeIntervalSince(date)) < abs(points[$1].date.timeIntervalSince(date)) }
}

func timeLabel(_ date: Date, _ range: TimeRange) -> String {
    range.seconds > 3600 ? Format.dayAndTime(date) : Format.time(date)
}

func grouped(_ n: Int) -> String { n.formatted(.number.grouping(.automatic)) }

/// One-line hover readout for a single metric.
func hoverLine(_ metric: Metric, _ range: TimeRange, _ date: Date, _ text: (Double) -> String) -> [String] {
    let pts = Monitor.shared.history.points(metric, range: range)
    guard let i = nearest(pts, date) else { return [] }
    return [timeLabel(pts[i].date, range) + "\t" + text(pts[i].value)]
}

/// Two columns side by side, the given widths (nil takes a share of the rest), `gap` apart.
struct Columns<A: View, B: View>: View {
    var left: CGFloat? = nil
    var right: CGFloat? = nil
    var ratio: CGFloat = 1
    var gap: CGFloat = 36
    var alignment: VerticalAlignment = .top
    @ViewBuilder var a: A
    @ViewBuilder var b: B

    var body: some View {
        ShareRow(spacing: gap) {
            a.frame(width: left, alignment: .topLeading).frame(maxWidth: left == nil ? .infinity : nil, alignment: .topLeading).share(left == nil ? 1 : 0)
            b.frame(width: right, alignment: .topLeading).frame(maxWidth: right == nil ? .infinity : nil, alignment: .topLeading).share(right == nil ? ratio : 0)
        }
    }
}

/// The chart's alert line: dashed red with "提醒 90%" above it, opening the rule; nothing while the rule is off.
enum AlertMarks {
    static func mark(_ rule: Alerts.Rule, fraction: Double, label: String? = nil, _ p: Preferences) -> [ChartRule] {
        guard rule.isOn(p) else { return [] }
        return [ChartRule(fraction: fraction, color: Theme.danger, label: label ?? AlertText.pill(rule, p), bell: true, help: L10n.Alerts.edit,
                          action: { MainWindowController.shared.showAlerts(focus: rule) })]
    }
}

extension View {
    /// While the rule is off, a small bell at the chart's top right (left of its scale) offers to add it.
    func alertBell(_ rule: Alerts.Rule, gutter: CGFloat = 36, settings: SettingsStore = .shared) -> some View {
        overlay(alignment: .topTrailing) {
            if !rule.isOn(settings.prefs) { ChartAlertBadge(rule: rule).padding(.trailing, gutter + 4).padding(.top, 2) }
        }
    }
}

enum ThermalText {
    static func color(_ t: ThermalLevel) -> Color {
        switch t {
        case .nominal: return Theme.sub
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

enum TempZone {
    static func color(_ celsius: Double) -> Color {
        celsius >= 90 ? Theme.danger : celsius >= 70 ? Theme.warn : Theme.text
    }
}

extension TimeRange {
    /// "最近 5 分钟", the main chart's head.
    var recent: String { L10n.Monitor.recent(title) }
}

/// The chip and its cores, the CPU and GPU pages' spec ("Apple M4 Pro · 14 核").
private func chipSpec(_ cores: Int) -> String {
    cores > 0 ? L10n.Monitor.chipSpec(SystemInfo.chipName, cores) : SystemInfo.chipName
}

// MARK: - CPU

struct CPUPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    var navigator = Navigator.shared
    @State private var selectedPeak: Date?

    /// Set before opening the page to start on another range (the overview's peaks).
    static var requestedRange: TimeRange? {
        get { nil }
        set { if let newValue { Navigator.shared.ranges[.cpu] = newValue } }
    }

    var body: some View {
        let s = monitor.snapshot
        let history = monitor.history
        let _ = monitor.tick
        let range = navigator.range(.cpu)
        let lookback = range.seconds > 3600
        let peaks = history.cpuPeaks()
        let selected = selectedPeak.flatMap { d in peaks.first { $0.date == d } } ?? peaks.first
        let unit = settings.prefs.general.temperatureUnit
        let idle = max(0, 1 - s.cpu.total)

        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: L10n.Module.cpu, spec: chipSpec(SystemInfo.coreCount)) {
                KeyValue(label: L10n.Monitor.processesLabel, value: grouped(s.processes.processCount), size: 13)
                KeyValue(label: L10n.Monitor.threadsLabel, value: grouped(s.processes.threadCount), size: 13)
            }
            Columns(right: 232) {
                VStack(alignment: .leading, spacing: 0) {
                    SmallLabel(text: L10n.Panel.utilization)
                    BigValue(value: Format.percentNumber(s.cpu.total), unit: "%", size: 56, color: Theme.accent).padding(.top, 8)
                    StackedBar(parts: [.init(label: L10n.Monitor.userShare(Format.percent(s.cpu.user)), value: s.cpu.user, color: Theme.accent),
                                       .init(label: L10n.Monitor.systemShare(Format.percent(s.cpu.system)), value: s.cpu.system, color: Theme.faint),
                                       .init(label: L10n.Monitor.idleShare(Format.percent(idle)), value: idle, color: Theme.raise, ring: true)],
                               keySize: 12)
                        .padding(.top, 14)
                    ChartHead(title: range.recent) {
                        if lookback {
                            Button(L10n.Monitor.backToNow) { navigator.ranges[.cpu] = .m5 }.buttonStyle(.plain)
                        } else if let top = peaks.first {
                            Button {
                                selectedPeak = top.date
                                navigator.ranges[.cpu] = .h24
                            } label: {
                                Text(L10n.Monitor.peakLink(Format.percent(top.value / 100))).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 24)
                    ConsoleChart(
                        kind: .area, series: ChartSeries.cpuStack(total: history.points(.cpu, range: range), system: history.points(.cpuSystem, range: range)),
                        range: range, maxValue: 100, height: 159, yLabels: ChartScale.percent,
                        rules: AlertMarks.mark(.cpu, fraction: settings.prefs.alerts.cpuThreshold / 100, settings.prefs),
                        markers: lookback ? peaks : [], selectedMarker: lookback ? selected?.date : nil, markerColor: Theme.accent,
                        hoverText: { hoverLines($0, range) },
                        onTap: { date in
                            guard lookback else { return }
                            if let nearest = peaks.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }),
                               abs(nearest.date.timeIntervalSince(date)) < range.seconds / 30 { selectedPeak = nearest.date }
                        },
                        pinnedTip: lookback ? selected.map { peakTip($0) } : nil)
                        .alertBell(.cpu)
                        .padding(.top, 12)
                        .accessibilityLabel(L10n.Monitor.cpuChartA11y(range.title))
                }
            } b: {
                VStack(alignment: .leading, spacing: 0) {
                    if lookback {
                        HeadRow(title: L10n.Monitor.peaks24h)
                        PeakList(peaks: peaks, selected: selected?.date) { selectedPeak = $0 }
                    } else {
                        HeadRow(title: L10n.Monitor.topCPU) { AllProcessesLink(sort: .cpu) }
                        ProcessTable(processes: Array(s.processes.byCPU.prefix(3)), value: { Format.percentValue($0.cpu) }, rowHeight: 30, minRows: 3)
                    }
                    Stat(name: L10n.Monitor.loadAverageTitle, tight: true) {
                        BigValue(value: Format.load(s.cpu.load.0), size: 22)
                    } foot: {
                        KeyValues(pairs: [(L10n.Monitor.load5, Format.load(s.cpu.load.1)), (L10n.Monitor.load15, Format.load(s.cpu.load.2))])
                    }
                    .padding(.top, 14)
                    Stat(name: L10n.Panel.frequency, tight: true) {
                        BigValue(value: ghz(s.cpu.frequencyMHz), unit: s.cpu.frequencyMHz == nil ? nil : L10n.Monitor.ghz, size: 22)
                    } foot: {
                        if SystemInfo.efficiencyCores > 0 {
                            KeyValues(pairs: [(L10n.Monitor.performanceCores, ghz(s.cpu.performanceMHz)), (L10n.Monitor.efficiencyCores, ghz(s.cpu.efficiencyMHz))])
                        }
                    }
                    .padding(.top, 12)
                    Stat(name: L10n.Panel.temperature, tight: true) {
                        BigValue(value: s.sensors.cpuAverage.map { Format.temperatureNumber($0, unit: unit) } ?? L10n.Common.dash,
                                 unit: s.sensors.cpuAverage == nil ? nil : Format.temperatureSymbol(unit), size: 22)
                    } foot: {
                        if let w = s.sensors.cpuPower { KeyValue(label: L10n.Panel.power, value: Format.watts(w)) }
                    }
                    .padding(.top, 12)
                }
            }
            .padding(.top, 22)
            HeadRow(title: L10n.Panel.cores).padding(.top, 26)
            CoreStrip(cpu: s.cpu, height: 72).padding(.top, 8)
        }
    }

    private func ghz(_ mhz: Double?) -> String { mhz.map { String(format: "%.2f", $0 / 1000) } ?? L10n.Common.dash }

    private func peakTip(_ p: PeakMarker) -> [String] {
        [Format.dayAndTime(p.date) + "\t" + Format.percent(p.value / 100)] + p.top.prefix(2).map { "\($0.name)\t\(Format.percent($0.cpu / 100))" }
    }

    private func hoverLines(_ date: Date, _ range: TimeRange) -> [String] {
        let history = monitor.history
        if range.seconds > 3600, let b = history.bucket(near: date), !b.max[Metric.cpu.rawValue].isNaN {
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

/// The last 24 hours' busiest moments; picking one pins its readout on the chart.
private struct PeakList: View {
    var peaks: [PeakMarker]
    var selected: Date?
    var pick: (Date) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if peaks.isEmpty {
                Text(L10n.Monitor.noPeaks).ui(14).foregroundStyle(Theme.sub).frame(maxWidth: .infinity, alignment: .leading).frame(height: 30)
            }
            DividedRows {
                ForEach(peaks) { p in
                    Button { pick(p.date) } label: {
                        HStack(spacing: 8) {
                            Text(Format.dayAndTime(p.date)).ui(14).lineLimit(1)
                            Text(p.top.first?.name ?? "").ui(12).foregroundStyle(Theme.sub).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(Format.percent(p.value / 100)).ui(14, 500).fixedSize()
                        }
                        .frame(height: 30)
                        .padding(.horizontal, 8)
                        .background { if p.date == selected { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.raise) } }
                        .padding(.horizontal, -8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(p.date == selected ? [.isSelected] : [])
                }
            }
        }
    }
}

/// Every core as a thin upright bar with its share under it: performance cores in the accent,
/// efficiency cores grey after a rule, and each group's average along the bottom.
struct CoreStrip: View {
    var cpu: CPUSample
    var height: CGFloat = 72
    /// The dropdown's version: 3 pt bars, no numbers or averages.
    var compact = false

    var body: some View {
        let isE = { (i: Int) in i < cpu.coreKinds.count && cpu.coreKinds[i] == .efficiency }
        let p = cpu.perCore.indices.filter { !isE($0) }
        let e = cpu.perCore.indices.filter { isE($0) }
        let avg = { (ix: [Int]) in ix.isEmpty ? 0 : ix.map { cpu.perCore[$0] }.reduce(0, +) / Double(ix.count) }
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(p, id: \.self) { bar($0, Theme.accent) }
                if !e.isEmpty {
                    Rectangle().fill(Theme.line).frame(width: 1, height: compact ? height : height + 20)
                        .padding(.horizontal, compact ? 0 : 6)
                        .frame(maxHeight: .infinity, alignment: .top)
                    ForEach(e, id: \.self) { bar($0, Theme.faint) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if !compact {
                HStack {
                    KeyValue(label: e.isEmpty ? L10n.Monitor.coreAverage : L10n.Monitor.pAverage, value: Format.percent(avg(p)))
                    Spacer(minLength: 0)
                    if !e.isEmpty { KeyValue(label: L10n.Monitor.eAverage, value: Format.percent(avg(e))) }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.Monitor.coresA11y(L10n.Panel.cores, cpu.perCore.map(Format.percent).joined(separator: L10n.A11y.separator)))
    }

    private func bar(_ i: Int, _ color: Color) -> some View {
        let v = min(max(cpu.perCore[i], 0), 1)
        return VStack(spacing: 8) {
            Capsule().fill(Theme.track)
                .frame(width: compact ? 3 : 4, height: height)
                .overlay(alignment: .bottom) { Capsule().fill(color).frame(height: max(compact ? 2 : 3, height * v)) }
            if !compact { Text(Format.percentNumber(v)).ui(12).foregroundStyle(Theme.sub).lineLimit(1).fixedSize() }
        }
        .frame(maxWidth: compact ? nil : .infinity)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - GPU

struct GPUPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    var navigator = Navigator.shared

    var body: some View {
        let g = monitor.snapshot.gpu
        let history = monitor.history
        let _ = monitor.tick
        let range = navigator.range(.gpu)
        let unit = settings.prefs.general.temperatureUnit
        let vram = g.memoryLimit > 0 ? Double(g.memoryUsed) / Double(g.memoryLimit) : 0
        let ghz = { (mhz: Double?) in mhz.map { String(format: "%.2f", $0 / 1000) } ?? L10n.Common.dash }
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: L10n.Module.gpu, spec: chipSpec(g.cores)) {
                if let fps = g.fps { KeyValue(label: L10n.Monitor.frameRate, value: L10n.Monitor.fpsValue(Int(fps.rounded())), size: 13) }
                if g.maxFPS > 60 { Text(L10n.Monitor.proMotion).foregroundStyle(Theme.sub) }
            }
            Columns(left: 200, gap: 48) {
                VStack(alignment: .leading, spacing: 0) {
                    SmallLabel(text: L10n.Panel.utilization)
                    BigValue(value: Format.percentNumber(g.utilization), unit: "%", size: 56, color: Theme.accent).padding(.top, 8)
                    Stat(name: L10n.Panel.vram) {
                        let used = Format.parts(Format.memory(g.memoryUsed))
                        BigValue(value: used.0, unit: g.memoryLimit > 0 ? L10n.Monitor.ofTotalUnit(used.1, Format.memory(g.memoryLimit)) : used.1, size: 28)
                    } foot: {
                        if g.memoryLimit > 0 {
                            HStack(spacing: 10) {
                                LevelBar(fraction: vram, color: Theme.mid)
                                KeyValue(label: L10n.Monitor.share, value: Format.percent(vram))
                            }
                        }
                    }
                    .padding(.top, 22)
                }
            } b: {
                VStack(alignment: .leading, spacing: 0) {
                    HeadRow(title: L10n.Monitor.engines)
                    engine(L10n.Monitor.renderer, g.renderer ?? 0, value: g.renderer.map(Format.percent) ?? L10n.Common.dash, color: Theme.accent)
                    engine(L10n.Monitor.tiler, g.tiler ?? 0, value: g.tiler.map(Format.percent) ?? L10n.Common.dash)
                    media(L10n.Monitor.videoDecode, g.decodeWatts)
                    media(L10n.Monitor.videoEncode, g.encodeWatts)
                }
            }
            .padding(.top, 22)
            ChartHead(title: range.recent) {
                KeyDot(text: L10n.Panel.utilization, color: Theme.accent, size: 12)
                KeyDot(text: L10n.Monitor.tiler, color: Theme.faint, size: 12)
            }
            .padding(.top, 26)
            ConsoleChart(kind: .area,
                         series: [ChartSeries(id: "t", points: history.points(.gpuTiler, range: range), color: Theme.faint, fill: 0, lineWidth: 1.5),
                                  ChartSeries(id: "g", points: history.points(.gpu, range: range), color: Theme.accent, fill: 1, lineWidth: 2)],
                         range: range, maxValue: 100, height: 94, yLabels: ChartScale.percent,
                         rules: AlertMarks.mark(.gpu, fraction: settings.prefs.alerts.gpuThreshold / 100, settings.prefs),
                         hoverText: { hover($0, range) })
                .alertBell(.gpu)
                .padding(.top, 12)
                .accessibilityLabel(L10n.Monitor.gpuChartA11y(range.title))
            Columns(left: 200, gap: 48) {
                VStack(alignment: .leading, spacing: 16) {
                    Stat(name: L10n.Panel.frequency, tight: true) {
                        BigValue(value: ghz(g.frequencyMHz), unit: g.frequencyMHz == nil ? nil : L10n.Monitor.ghz, size: 24)
                    } foot: {
                        KeyValues(pairs: [(L10n.Monitor.average, ghz(g.averageMHz)), (L10n.Monitor.highest, ghz(g.maxMHz))])
                    }
                    Stat(name: L10n.Panel.temperature, tight: true) {
                        BigValue(value: g.temperature.map { Format.temperatureNumber($0, unit: unit) } ?? L10n.Common.dash,
                                 unit: g.temperature == nil ? nil : Format.temperatureSymbol(unit), size: 24)
                    } foot: {
                        if let w = g.power { KeyValue(label: L10n.Panel.power, value: Format.watts(w)) }
                    }
                }
            } b: {
                VStack(alignment: .leading, spacing: 0) {
                    HeadRow(title: L10n.Monitor.topGPU) { AllProcessesLink(sort: .gpu) }
                    ProcessTable(processes: Array(monitor.snapshot.processes.byGPU.prefix(4)), value: { Format.percentValue($0.gpu) }, minRows: 4)
                }
            }
            .padding(.top, 26)
        }
    }

    private func engine(_ name: String, _ fraction: Double, value: String, detail: String = "", color: Color = Theme.mid) -> some View {
        HStack(spacing: 12) {
            Text(name).ui(14).foregroundStyle(Theme.sub).lineLimit(1).frame(width: 64, alignment: .leading)
            LevelBar(fraction: fraction, color: color)
            Text(detail).ui(12).foregroundStyle(Theme.sub).lineLimit(1).frame(width: 64, alignment: .trailing)
            Text(value).ui(14, 500).lineLimit(1).fixedSize().frame(minWidth: 40, alignment: .trailing)
        }
        .frame(height: 34)
        .accessibilityElement(children: .combine)
    }

    /// Media engines report energy, not load or codec: whether one is working and its power.
    private func media(_ name: String, _ watts: Double?) -> some View {
        let w = watts ?? 0
        return engine(name, min(w / 2, 1), value: watts.map(Format.watts) ?? L10n.Common.dash,
                      detail: watts == nil ? "" : w >= 0.01 ? L10n.Monitor.activeState : L10n.Monitor.idleState)
    }

    private func hover(_ date: Date, _ range: TimeRange) -> [String] {
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
    var navigator = Navigator.shared

    var body: some View {
        let s = monitor.snapshot
        let m = s.memory
        let _ = monitor.tick
        let range = navigator.range(.memory)
        let pr = PanelText.pressure(m.pressure)
        let alertAt = settings.prefs.alerts.memoryLevel == .critical ? 0.8 : 0.5
        let parts = MemoryParts.of(m)
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: L10n.Module.memory, spec: L10n.Monitor.unifiedSpec(Format.memoryTotal(m.total)))
            SmallLabel(text: L10n.Monitor.usedLabel).padding(.top, 22)
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                BigValue(value: Format.percentNumber(m.usedFraction), unit: "%", size: 56, color: Theme.accent)
                Text(L10n.Monitor.usedSlash(Format.memory(m.used), Format.memoryTotal(m.total))).ui(12).foregroundStyle(Theme.sub)
            }
            .padding(.top, 8)
            SegmentBar(parts: parts.map { ($0.bytes, $0.color) }, height: 8)
                .padding(.top, 16)
                .accessibilityElement()
                .accessibilityLabel(L10n.Monitor.compositionA11y(Format.memory(m.app), Format.memory(m.wired), Format.memory(m.compressed), Format.memory(m.cached), Format.memory(m.free)))
            PartLabels(parts: parts.map { ($0.label, Format.memory(UInt64($0.bytes)), $0.bytes) }).padding(.top, 10)
            Columns(left: 170) {
                VStack(alignment: .leading, spacing: 24) {
                    Stat(name: L10n.Monitor.memoryPressure) {
                        BigValue(value: Format.percentNumber(m.pressureLevel), unit: "%", size: 36)
                    } foot: {
                        Text(pr.0).ui(12).foregroundStyle(m.pressure == .normal ? Theme.sub : pr.1)
                    }
                    Stat(name: L10n.Memory.swap) {
                        let swap = Format.parts(Format.memory(m.swapUsed))
                        BigValue(value: swap.0, unit: swap.1, size: 36)
                    } foot: {
                        if m.swapTotal > 0 { KeyValue(label: L10n.Monitor.swapFileLabel, value: Format.memory(m.swapTotal)) }
                    }
                }
            } b: {
                VStack(alignment: .leading, spacing: 12) {
                    ChartHead(title: L10n.Monitor.titled(L10n.Monitor.memoryPressure, range.recent))
                    ConsoleChart(kind: .area, series: ChartSeries.line(monitor.history.points(.memoryPressure, range: range)),
                                 range: range, maxValue: 100, height: 155, yLabels: ChartScale.percent,
                                 rules: AlertMarks.mark(.memory, fraction: alertAt, label: L10n.Alerts.memoryMarkShort, settings.prefs),
                                 hoverText: { date in hoverLine(.memoryPressure, range, date) { Format.percent($0 / 100) } })
                        .alertBell(.memory)
                        .accessibilityLabel(L10n.Monitor.memoryChartA11y(range.title))
                }
            }
            .padding(.top, 30)
            HeadRow(title: L10n.Monitor.topMemory) { AllProcessesLink(sort: .memory) }.padding(.top, 26)
            let top = Array(s.processes.byMemory.prefix(6))
            Columns(gap: 44) {
                ProcessTable(processes: Array(top.prefix(3)), value: { Format.memory($0.memory) }, minRows: 3)
            } b: {
                ProcessTable(processes: Array(top.dropFirst(3)), value: { Format.memory($0.memory) }, minRows: 3, showsEmpty: false)
            }
        }
    }
}

/// Labels under a composition bar, each starting where its part starts, pushed right where a
/// small part leaves no room: the name 12 grey, the amount 14 / 500 under it.
struct PartLabels: View {
    var parts: [(String, String, Double)]

    var body: some View {
        GeometryReader { geo in
            let total = max(parts.map(\.2).reduce(0, +), 0.0001)
            let xs = positions(width: geo.size.width, total: total)
            ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.0).ui(12).foregroundStyle(Theme.sub)
                    Text(p.1).ui(14, 500)
                }
                .lineLimit(1)
                .fixedSize()
                .offset(x: xs[i])
            }
        }
        .frame(height: 38)
        .accessibilityHidden(true)
    }

    private func positions(width: CGFloat, total: Double) -> [CGFloat] {
        var out: [CGFloat] = []
        var start: CGFloat = 0, floor: CGFloat = 0
        for p in parts {
            let x = max(start, floor)
            out.append(x)
            floor = x + 72
            start += width * CGFloat(p.2 / total) + 2
        }
        // Keep the last labels inside the row.
        if let last = out.last, last > width - 60 {
            var limit = width - 60
            for i in stride(from: out.count - 1, through: 0, by: -1) {
                out[i] = min(out[i], limit)
                limit = out[i] - 72
            }
        }
        return out
    }
}

/// Memory by kind, in the order and colors the bar and its labels use.
enum MemoryParts {
    struct Part {
        var label: String
        var bytes: Double
        var color: Color
    }

    static func of(_ m: MemorySample) -> [Part] {
        [Part(label: L10n.Monitor.appMemory, bytes: Double(m.app), color: Theme.accent),
         Part(label: L10n.Memory.wired, bytes: Double(m.wired), color: Theme.accentSoft),
         Part(label: L10n.Monitor.compressed, bytes: Double(m.compressed), color: Theme.mid),
         Part(label: L10n.Monitor.cache, bytes: Double(m.cached), color: Theme.low),
         Part(label: L10n.Memory.free, bytes: Double(m.free), color: Theme.raise)]
    }
}

// MARK: - Network

struct NetworkPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    var navigator = Navigator.shared

    var body: some View {
        let s = monitor.snapshot
        let n = s.network
        let unit = settings.prefs.network.speedUnit
        let _ = monitor.tick
        let range = navigator.range(.network)
        let history = monitor.history
        let down = history.points(.netDown, range: range)
        let up = history.points(.netUp, range: range)
        let dMax = ConsoleChart.niceMax(max(down.map(\.value).max() ?? 0, 10_000) * 1.1)
        let uMax = ConsoleChart.niceMax(max(up.map(\.value).max() ?? 0, 10_000) * 1.1)
        let failures = n.checks.filter { $0 == .failed }.count
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: L10n.Module.network, spec: n.connected ? interfaceName(n) : L10n.Panel.notConnected)
            Columns(left: 200) {
                VStack(alignment: .leading, spacing: 34) {
                    flow(MenuBarText.downArrow + " " + L10n.Panel.download, n.down, unit: unit, session: n.sessionDown, today: n.todayDown)
                    flow(MenuBarText.upArrow + " " + L10n.Panel.upload, n.up, unit: unit, session: n.sessionUp, today: n.todayUp)
                    if settings.prefs.network.showLatency {
                        Stat(name: L10n.Monitor.latency) {
                            BigValue(value: n.latencyMS.map { "\(Int($0.rounded()))" } ?? L10n.Common.dash, unit: n.latencyMS == nil ? nil : L10n.Monitor.ms, size: 32)
                        } foot: {
                            VStack(alignment: .leading, spacing: 8) {
                                ConnectionLog(checks: n.checks)
                                if failures > 0 { Text(L10n.Monitor.dropped(failures)).ui(12).foregroundStyle(Theme.danger) }
                            }
                        }
                    }
                }
            } b: {
                VStack(alignment: .leading, spacing: 12) {
                    ChartHead(title: range.recent)
                    ConsoleChart(kind: .mirroredArea, series: ChartSeries.mirrored(down, Theme.accent, up, Theme.accent),
                                 range: range, maxValue: dMax, bottomMax: uMax, height: 297,
                                 yLabels: [(1, MenuBarText.downArrow + " " + Format.rate(dMax, unit: unit)), (0.5, "0"), (0, MenuBarText.upArrow + " " + Format.rate(uMax, unit: unit))],
                                 gutter: 72, hoverText: { hover($0, range) })
                        .overlay(alignment: .topTrailing) { ChartAlertBadge(rule: .network).padding(.trailing, 76).padding(.top, 2) }
                        .accessibilityLabel(L10n.Monitor.networkChartA11y(range.title))
                }
            }
            .padding(.top, 22)
            Columns(ratio: 1.5, gap: 44) {
                VStack(alignment: .leading, spacing: 0) {
                    HeadRow(title: L10n.Monitor.connection)
                    VStack(spacing: 0) {
                        DividedRows {
                            ValueRow(label: n.interface.isEmpty ? PanelText.kindName(n.kind) : PanelText.kindName(n.adapterKind ?? n.kind), labelColor: Theme.sub) {
                                Text(n.connected ? (n.interface.isEmpty ? L10n.Overview.connected : L10n.Monitor.connectedVia(n.interface)) : L10n.Panel.notConnected)
                            }
                            ValueRow(label: L10n.Monitor.localIPTitle, value: n.localIP.isEmpty ? L10n.Common.dash : n.localIP, labelColor: Theme.sub)
                            ValueRow(label: L10n.Network.router, value: n.router.isEmpty ? L10n.Common.dash : n.router, labelColor: Theme.sub)
                            if settings.prefs.network.showPublicIP {
                                ValueRow(label: L10n.Monitor.publicIPTitle, value: n.connected ? (monitor.publicIP ?? L10n.Common.dash) : L10n.Common.dash, labelColor: Theme.sub)
                            }
                        }
                    }
                }
            } b: {
                VStack(alignment: .leading, spacing: 0) {
                    HeadRow(title: L10n.Monitor.topNetwork) { AllProcessesLink(sort: .network) }
                    ProcessTable(processes: Array(s.processes.byNetwork.prefix(4)),
                                 value: { MenuBarText.downArrow + " " + Format.rate($0.netDown, unit: unit) }, valueWidth: 96,
                                 secondary: { MenuBarText.upArrow + " " + Format.rate($0.netUp, unit: unit) }, rowHeight: 34, minRows: 4)
                }
            }
            .padding(.top, 26)
        }
    }

    private func interfaceName(_ n: NetworkSample) -> String {
        n.interface.isEmpty ? PanelText.kindName(n.kind) : L10n.Settings.interfaceOption(PanelText.kindName(n.adapterKind ?? n.kind), n.interface)
    }

    private func flow(_ label: String, _ rate: Double, unit: SpeedUnit, session: UInt64, today: UInt64) -> some View {
        let parts = Format.rateParts(rate, unit: unit)
        return Stat(name: label) {
            BigValue(value: parts.0, unit: parts.1, size: 44, color: Theme.accent)
        } foot: {
            KeyValues(pairs: [(L10n.Monitor.session, Format.storage(session)), (L10n.Monitor.today, Format.storage(today))])
        }
    }

    private func hover(_ date: Date, _ range: TimeRange) -> [String] {
        let d = monitor.history.points(.netDown, range: range)
        let u = monitor.history.points(.netUp, range: range)
        guard let i = nearest(d, date) else { return [] }
        return [timeLabel(d[i].date, range), L10n.Panel.download + "\t" + Format.rate(d[i].value), L10n.Panel.upload + "\t" + Format.rate(i < u.count ? u[i].value : 0)]
    }
}

/// The last 48 connection checks (one every 30 seconds) as cells: grey when fine, amber slow, red failed.
struct ConnectionLog: View {
    var checks: [ConnectionCheck]

    var body: some View {
        let slots = Array(repeating: ConnectionCheck?.none, count: max(0, 48 - checks.count)) + checks.suffix(48).map { Optional($0) }
        HStack(spacing: 1) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, c in
                RoundedRectangle(cornerRadius: 1, style: .continuous).fill(color(c))
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel(L10n.Monitor.checksA11y(checks.count, checks.filter { $0 == .ok }.count,
                                                    checks.filter { $0 == .slow }.count, checks.filter { $0 == .failed }.count))
    }

    private func color(_ c: ConnectionCheck?) -> Color {
        switch c {
        case .ok: return Theme.low
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
    var navigator = Navigator.shared

    var body: some View {
        let s = monitor.snapshot
        let d = s.disk
        let unit = settings.prefs.general.temperatureUnit
        let _ = monitor.tick
        let range = navigator.range(.disk)
        let reads = monitor.history.points(.diskRead, range: range)
        let writes = monitor.history.points(.diskWrite, range: range)
        let rMax = ConsoleChart.niceMax(max(reads.map(\.value).max() ?? 0, 1_000_000) * 1.1)
        let wMax = ConsoleChart.niceMax(max(writes.map(\.value).max() ?? 0, 1_000_000) * 1.1)
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: L10n.Module.disk, spec: L10n.Monitor.volumeCount(d.volumes.count))
            if !d.volumes.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 44, alignment: .topLeading), GridItem(.flexible(), spacing: 44, alignment: .topLeading)],
                          alignment: .leading, spacing: 24) {
                    ForEach(d.volumes) { v in
                        VolumeBlock(volume: v, size: 36, alert: v.isRoot ? diskAlert : nil)
                    }
                }
                .padding(.top, 30)
            }
            ChartHead(title: L10n.Monitor.titled(L10n.Monitor.readWriteTitle, range.recent)) {
                Text(MenuBarText.downArrow + " " + L10n.Monitor.readValue(Format.rate(d.read)))
                Text(MenuBarText.upArrow + " " + L10n.Monitor.writeValue(Format.rate(d.write)))
            }
            .padding(.top, 28)
            ConsoleChart(kind: .mirroredArea, series: ChartSeries.mirrored(reads, Theme.text, writes, Theme.text, lineWidth: 1.5),
                         range: range, maxValue: rMax, bottomMax: wMax, height: 147,
                         yLabels: [(1, Format.rate(rMax)), (0.5, "0"), (0, Format.rate(wMax))],
                         gutter: 64, hoverText: { hover($0, range) })
                .padding(.top, 12)
                .accessibilityLabel(L10n.Monitor.diskChartA11y(range.title))
            Columns(gap: 44) {
                VStack(alignment: .leading, spacing: 0) {
                    HeadRow(title: L10n.Monitor.health)
                    if let h = d.health {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 16) {
                            GridRow {
                                Figure(name: L10n.Monitor.lifeRemaining, value: Format.percentNumber(h.lifeRemaining), unit: "%", color: h.lifeRemaining >= 0.1 ? Theme.text : Theme.danger)
                                Figure(name: L10n.Monitor.smart, value: h.ok ? L10n.Monitor.good : L10n.Monitor.failing, color: h.ok ? Theme.text : Theme.danger)
                            }
                            GridRow {
                                let w = Format.parts(Format.storage(h.totalWritten))
                                Figure(name: L10n.Monitor.totalWritten, value: w.0, unit: w.1)
                                Figure(name: L10n.Panel.temperature, value: h.temperature.map { Format.temperatureNumber($0, unit: unit) } ?? L10n.Common.dash,
                                       unit: h.temperature == nil ? nil : Format.temperatureSymbol(unit))
                            }
                        }
                        .padding(.top, 10)
                    }
                    HStack(spacing: 14) {
                        Text(L10n.Monitor.sinceBoot).ui(12).foregroundStyle(Theme.sub)
                        KeyValues(pairs: [(L10n.Monitor.readShort, Format.storage(d.totalRead)), (L10n.Monitor.writeShort, Format.storage(d.totalWritten))])
                    }
                    .padding(.top, 14)
                }
            } b: {
                VStack(alignment: .leading, spacing: 0) {
                    HeadRow(title: L10n.Monitor.topReadWrite) { AllProcessesLink(sort: .disk) }
                    ProcessTable(processes: Array(s.processes.byDisk.prefix(3)),
                                 value: { L10n.Monitor.readRate(Format.rate($0.diskRead)) }, valueWidth: 92,
                                 secondary: { L10n.Monitor.writeRate(Format.rate($0.diskWrite)) }, secondaryWidth: 92, minRows: 3)
                }
            }
            .padding(.top, 24)
        }
    }

    /// The free-space rule on the startup volume: where it sits on the bar and its words.
    private var diskAlert: (Double, String)? {
        let p = settings.prefs
        guard Alerts.Rule.disk.isOn(p), let root = monitor.snapshot.disk.root, root.total > 0 else { return nil }
        let limit = p.alerts.diskFreeGB * 1_000_000_000
        return (1 - limit / Double(root.total), L10n.Alerts.belowValue(L10n.Settings.gigabytes(Int(p.alerts.diskFreeGB))))
    }

    private func hover(_ date: Date, _ range: TimeRange) -> [String] {
        let r = monitor.history.points(.diskRead, range: range)
        let w = monitor.history.points(.diskWrite, range: range)
        guard let i = nearest(r, date) else { return [] }
        return [timeLabel(r[i].date, range), L10n.Disk.read + "\t" + Format.rate(r[i].value), L10n.Disk.write + "\t" + Format.rate(i < w.count ? w[i].value : 0)]
    }
}

/// A volume: name and internal / external (eject for removable ones), free space in the accent,
/// used / purgeable / free on one thin bar (a red tick where the free-space rule fires), then the details.
struct VolumeBlock: View {
    var volume: Volume
    var size: CGFloat = 36
    /// The free-space rule: its place on the bar (0...1 used) and its words.
    var alert: (Double, String)? = nil
    var barHeight: CGFloat = 6

    var body: some View {
        let free = Format.parts(Format.storage(volume.available))
        let total = Double(max(volume.total, 1))
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(volume.name).ui(13, 500).foregroundStyle(Theme.text).lineLimit(1)
                Text(volume.isInternal ? L10n.Disk.internalDrive : L10n.Disk.external).ui(12).foregroundStyle(Theme.sub).fixedSize()
                if volume.isEjectable && !volume.isRoot { EjectButton(volume: volume, size: 18) }
                Spacer(minLength: 0)
                if let alert { BellLabel(text: alert.1).ui(12).foregroundStyle(Theme.danger).lineLimit(1).fixedSize() }
            }
            BigValue(value: free.0, unit: L10n.Monitor.unitFree(free.1), size: size, color: Theme.accent).padding(.top, 6)
            SegmentBar(parts: [(Double(max(0, volume.used - volume.purgeable)) / total, Theme.accent),
                               (Double(volume.purgeable) / total, Theme.accentSoft),
                               (Double(volume.available) / total, Theme.track)], height: barHeight)
                .overlay {
                    if let alert {
                        GeometryReader { geo in
                            Capsule().fill(Theme.danger).frame(width: 2, height: barHeight + 6)
                                .offset(x: geo.size.width * min(max(alert.0, 0), 1) - 1, y: -3)
                        }
                    }
                }
                .padding(.top, 12)
            KeyValues(pairs: [(L10n.Monitor.usedLabel, Format.storage(volume.used))]
                      + (volume.purgeable > 0 ? [(L10n.Monitor.purgeableLabel, Format.storage(volume.purgeable))] : [])
                      + [(L10n.Monitor.totalLabel, Format.storage(volume.total))])
                .padding(.top, 10)
        }
        .accessibilityElement(children: .combine)
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
                .fill(Theme.sub)
                .frame(width: 9, height: 9)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.raise))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.Disk.eject(volume.name))
        .accessibilityLabel(L10n.Disk.eject(volume.name))
    }
}

// MARK: - Battery

struct BatteryPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    var navigator = Navigator.shared

    var body: some View {
        let s = monitor.snapshot
        let b = s.battery
        let _ = monitor.tick
        let range = navigator.range(.battery)
        let unit = settings.prefs.general.temperatureUnit
        let wholeMac = b.hasBattery ? (b.onAC ? max(0, (b.systemPowerIn ?? 0) - max(0, b.power ?? 0)) : abs(b.power ?? 0)) : s.sensors.systemPower
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: L10n.Module.battery, spec: b.onAC ? b.adapterWatts.map { L10n.Monitor.adapterSpec($0) } : (b.hasBattery ? L10n.Battery.onBattery : nil))
            if b.hasBattery {
                Columns(left: 150) {
                    VStack(alignment: .leading, spacing: 0) {
                        SmallLabel(text: L10n.Battery.level)
                        BigValue(value: Format.percentNumber(b.level), unit: "%", size: 64, color: b.level <= 0.2 && !b.onAC ? Theme.danger : Theme.accent).padding(.top, 8)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(statusLines(b), id: \.self) { Text($0) }
                        }
                        .ui(12).foregroundStyle(Theme.sub)
                        .padding(.top, 12)
                    }
                } b: {
                    VStack(alignment: .leading, spacing: 12) {
                        ChartHead(title: L10n.Monitor.titled(L10n.Battery.level, range.recent)) {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Theme.chargeBand)
                                    .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                                    .frame(width: 10, height: 10)
                                Text(L10n.Monitor.chargingLegend)
                            }
                        }
                        ConsoleChart(kind: .area, series: ChartSeries.line(monitor.history.points(.battery, range: range)),
                                     range: range, maxValue: 100, height: 132, yLabels: ChartScale.percent,
                                     rules: AlertMarks.mark(.battery, fraction: settings.prefs.alerts.batteryPercent / 100, settings.prefs),
                                     bands: ChargingBands.of(range), hoverText: { hover($0, range) })
                            .alertBell(.battery)
                            .accessibilityLabel(L10n.Monitor.batteryChartA11y(range.title))
                    }
                }
                .padding(.top, 22)
                HStack(alignment: .top, spacing: 36) {
                    VStack(alignment: .leading, spacing: 10) {
                        Figure(name: L10n.Monitor.batteryHealth, value: b.health.map(Format.percentNumber) ?? L10n.Common.dash, unit: b.health == nil ? nil : "%", size: 28)
                        LevelBar(fraction: b.health ?? 0, color: (b.health ?? 1) >= 0.8 ? Theme.mid : Theme.warn)
                        if let full = b.maxCapacity, let design = b.designCapacity {
                            KeyValues(pairs: [(L10n.Monitor.fullCharge, grouped(full)), (L10n.Monitor.designCapacity, grouped(design) + " " + L10n.Monitor.mAh)])
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 10) {
                        let design = b.designCycles ?? 1000
                        Figure(name: L10n.Battery.cycles, value: b.cycles.map { grouped($0) } ?? L10n.Common.dash, unit: L10n.Monitor.ofTotal(grouped(design)), size: 28)
                        LevelBar(fraction: Double(b.cycles ?? 0) / Double(max(design, 1)), color: Theme.mid)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    let t = b.temperature ?? s.sensors.value(.battery)
                    Figure(name: L10n.Battery.temperature, value: t.map { Format.temperatureNumber($0, unit: unit) } ?? L10n.Common.dash,
                           unit: t == nil ? nil : Format.temperatureSymbol(unit), size: 28)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 28)
                powerSection(b).padding(.top, 26)
            } else {
                HStack(spacing: 10) {
                    LineIcon(d: Icons.batteryOff, size: 16, lineWidth: 1.5).foregroundStyle(Theme.sub)
                    Text(L10n.Battery.noBattery).ui(16, 500)
                }
                .padding(.top, 22)
            }
            if !b.ups.isEmpty {
                HeadRow(title: L10n.Battery.ups).padding(.top, 26)
                VStack(spacing: 0) { DividedRows { ForEach(b.ups) { UPSRow(source: $0) } } }
            }
            HeadRow(title: L10n.Processes.topEnergy) {
                if let wholeMac { Text(L10n.Processes.wholeMac(Format.watts(wholeMac))) }
                AllProcessesLink(sort: .energy)
            }
            .padding(.top, 24)
            let top = Array(s.processes.byEnergy.prefix(6))
            Columns(gap: 44) {
                ProcessTable(processes: Array(top.prefix(3)), value: { Format.appWatts($0.energy) }, minRows: 3)
            } b: {
                ProcessTable(processes: Array(top.dropFirst(3)), value: { Format.appWatts($0.energy) }, showsEmpty: false)
            }
        }
    }

    private func statusLines(_ b: BatterySample) -> [String] {
        if b.isCharging { return [L10n.Battery.charging] + (b.minutesToFull.map { [L10n.Battery.untilFull(BatteryTime.text($0))] } ?? []) }
        if b.onAC { return [b.isCharged || b.level >= 0.99 ? L10n.Battery.charged : L10n.Battery.onAC] }
        return [L10n.Battery.onBattery] + (b.minutesToEmpty.map { [L10n.Battery.remaining(BatteryTime.text($0))] } ?? [])
    }

    /// Where the power goes: the Mac's draw, what charges the battery, what the adapter has left.
    private func powerSection(_ b: BatterySample) -> some View {
        let charge = max(0, b.power ?? 0)
        let system = b.onAC ? max(0, (b.systemPowerIn ?? 0) - charge) : abs(b.power ?? 0)
        let adapter = Double(b.adapterWatts ?? 0)
        let headroom = max(0, adapter - system - charge)
        let parts: [StackedBar.Part] = b.onAC
            ? [.init(label: L10n.Monitor.systemDrawValue(Format.watts(system)), value: system, color: Theme.mid),
               .init(label: L10n.Monitor.chargeValue(Format.watts(charge)), value: charge, color: Theme.accent),
               .init(label: L10n.Monitor.headroomValue(Format.watts(headroom)), value: headroom, color: Theme.raise, ring: true)]
            : [.init(label: L10n.Monitor.systemDrawValue(Format.watts(system)), value: max(system, 0.01), color: Theme.mid)]
        return VStack(alignment: .leading, spacing: 8) {
            HeadRow(title: L10n.Monitor.powerSource)
            StackedBar(parts: parts)
        }
    }

    private func hover(_ date: Date, _ range: TimeRange) -> [String] {
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
        HStack(spacing: 10) {
            LineIcon(d: Icons.ups, size: 16, lineWidth: 1.4).foregroundStyle(Theme.sub)
            Text(source.name).ui(14).lineLimit(1)
            Text(source.onAC ? (source.minutesLeft.map { L10n.Battery.upsDetail($0) } ?? L10n.Battery.upsOnAC) : L10n.Battery.onBattery)
                .ui(12).foregroundStyle(Theme.sub).lineLimit(1)
            Spacer(minLength: 8)
            Text(Format.percent(source.level)).ui(14, 500)
        }
        .frame(height: 34)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sensors

struct SensorsPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    var navigator = Navigator.shared

    var body: some View {
        let s = monitor.snapshot.sensors
        let unit = settings.prefs.general.temperatureUnit
        let _ = monitor.tick
        let range = navigator.range(.sensors)
        let t = { (c: Double) in Format.temperature(c, unit: unit, showUnit: true) }
        let rowHeight: CGFloat = s.temps.count > 7 ? 40 : 52
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: L10n.Module.sensors) {
                Text(L10n.Sensors.thermalState).foregroundStyle(Theme.sub)
                ThermalSteps(level: s.thermal)
                Text(s.thermal == .nominal ? L10n.Monitor.notThrottled : L10n.Monitor.throttled)
                    .ui(12).foregroundStyle(s.thermal == .nominal ? Theme.sub : ThermalText.color(s.thermal))
            }
            Columns(right: 220, gap: 44) {
                VStack(alignment: .leading, spacing: 0) {
                    HeadRow(title: L10n.Monitor.allTemps) {
                        KeyDot(text: L10n.Monitor.zoneLow(t(70)), color: Theme.mid, size: 12)
                        KeyDot(text: L10n.Monitor.zoneMid(Format.temperatureNumber(70, unit: unit), t(90)), color: Theme.warn, size: 12)
                        KeyDot(text: L10n.Monitor.zoneHigh(t(90)), color: Theme.danger, size: 12)
                    }
                    if s.temps.isEmpty {
                        Text(L10n.Common.dash).ui(14).foregroundStyle(Theme.sub).frame(height: rowHeight)
                    }
                    ForEach(s.temps) { r in
                        HStack(spacing: 14) {
                            Text(PanelText.tempName(r.group)).ui(14).foregroundStyle(Theme.sub).lineLimit(1).frame(width: 84, alignment: .leading)
                            TempBar(celsius: r.value)
                            Text(t(r.value)).ui(14, 500).foregroundStyle(TempZone.color(r.value)).lineLimit(1).frame(width: 60, alignment: .trailing)
                        }
                        .frame(height: rowHeight)
                        .accessibilityElement(children: .combine)
                    }
                }
            } b: {
                VStack(alignment: .leading, spacing: 0) {
                    SmallLabel(text: L10n.Monitor.cpuTempTitle)
                    BigValue(value: s.cpuAverage.map { Format.temperatureNumber($0, unit: unit) } ?? L10n.Common.dash,
                             unit: Format.temperatureSymbol(unit), size: 52, color: Theme.accent)
                        .padding(.top, 8)
                    if let mx = s.cpuMax { KeyValue(label: L10n.Monitor.highest, value: t(mx)).padding(.top, 10) }
                    ChartHead(title: range.recent).padding(.top, 26)
                    ConsoleChart(kind: .area, series: ChartSeries.line(monitor.history.points(.cpuTemp, range: range)),
                                 range: range, maxValue: 100, height: 198,
                                 yLabels: [(0.9, Format.temperatureNumber(90, unit: unit)), (0.7, Format.temperatureNumber(70, unit: unit)), (0, Format.temperatureNumber(0, unit: unit))],
                                 showTimes: false,
                                 rules: [ChartRule(fraction: 0.7, color: Theme.warn), ChartRule(fraction: 0.9, color: Theme.danger)]
                                    + AlertMarks.mark(.temperature, fraction: settings.prefs.alerts.tempThreshold / 100, settings.prefs),
                                 hoverText: { date in hoverLine(.cpuTemp, range, date) { t($0) } })
                        .alertBell(.temperature)
                        .padding(.top, 12)
                        .accessibilityLabel(L10n.Monitor.tempChartA11y(range.title))
                    HStack {
                        Text(range.axisLabels.first ?? "")
                        Spacer(minLength: 0)
                        Text(L10n.Range.now)
                    }
                    .ui(12).foregroundStyle(Theme.sub)
                    .padding(.trailing, 36)
                    .padding(.top, 8)
                }
            }
            .padding(.top, 22)
            Columns(gap: 44) {
                VStack(alignment: .leading, spacing: 0) {
                    HeadRow(title: s.fansAuto ? L10n.Monitor.fansAuto : L10n.Monitor.fansManual) {
                        if let f = s.fans.first, f.max > 0 { Text(L10n.Monitor.fanRange(Int(f.min.rounded()), Int(f.max.rounded()))) }
                    }
                    if s.fans.isEmpty {
                        Text(L10n.Sensors.fanless).ui(14).foregroundStyle(Theme.sub).frame(height: 44)
                    }
                    ForEach(Array(s.fans.enumerated()), id: \.offset) { _, f in
                        HStack(spacing: 12) {
                            Text(PanelText.fanName(f.id, count: s.fans.count)).ui(14).foregroundStyle(Theme.sub).lineLimit(1).frame(width: 64, alignment: .leading)
                            LevelBar(fraction: f.max > f.min ? (f.rpm - f.min) / (f.max - f.min) : 0, color: Theme.mid)
                            Text(Format.rpm(f.rpm)).ui(14, 500).lineLimit(1).frame(width: 84, alignment: .trailing)
                        }
                        .frame(height: 44)
                        .accessibilityElement(children: .combine)
                    }
                }
            } b: {
                VStack(alignment: .leading, spacing: 10) {
                    HeadRow(title: L10n.Sensors.power) {
                        if let w = s.systemPower { Text(L10n.Processes.wholeMac(Format.watts(w))) }
                    }
                    let cpu = s.cpuPower ?? 0, gpu = s.gpuPower ?? 0
                    let other = max(0, (s.systemPower ?? (cpu + gpu)) - cpu - gpu)
                    StackedBar(parts: [.init(label: L10n.Monitor.partValue(L10n.Module.cpu, s.cpuPower.map(Format.watts) ?? L10n.Common.dash), value: cpu, color: Theme.mid),
                                       .init(label: L10n.Monitor.partValue(L10n.Module.gpu, s.gpuPower.map(Format.watts) ?? L10n.Common.dash), value: gpu, color: Theme.faint),
                                       .init(label: L10n.Monitor.partValue(L10n.Monitor.other, s.systemPower == nil ? L10n.Common.dash : Format.watts(other)), value: other, color: Theme.low)],
                               keySize: 12)
                }
            }
            .padding(.top, 36)
        }
    }
}

/// A temperature on a 0–100 °C track with amber and red ticks at 70 and 90.
private struct TempBar: View {
    var celsius: Double

    var body: some View {
        LevelBar(fraction: celsius / 100, color: celsius >= 90 ? Theme.danger : celsius >= 70 ? Theme.warn : Theme.mid)
            .overlay {
                GeometryReader { geo in
                    ForEach([(0.7, Theme.warn), (0.9, Theme.danger)], id: \.0) { x, c in
                        Rectangle().fill(c).frame(width: 1, height: 10).offset(x: geo.size.width * x, y: -3)
                    }
                }
            }
    }
}

/// The thermal pressure's four steps, the current one dark.
struct ThermalSteps: View {
    var level: ThermalLevel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { i in
                let on = i == level.rawValue
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(on ? (level == .nominal ? Theme.text : ThermalText.color(level)) : Theme.low).frame(width: 28, height: 3)
                    Text(L10n.Monitor.thermalLevel(i)).ui(12).foregroundStyle(on ? Theme.text : Theme.sub).fixedSize()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.Monitor.thermalLevel(level.rawValue))
    }
}
