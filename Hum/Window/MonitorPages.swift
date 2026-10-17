import SwiftUI

// MARK: - Overview

struct OverviewPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    var alerts = Alerts.shared
    @State private var sortByMemory = false

    var body: some View {
        let s = monitor.snapshot
        let unit = settings.prefs.general.temperatureUnit
        let _ = monitor.tick
        let issues = alerts.active.filter { $0.value != .dim || $0.key == .network }.count
        HStack(spacing: 12) {
            Text(L10n.Overview.title).font(.system(size: 22, weight: .bold)).kerning(-0.4).accessibilityAddTraits(.isHeader)
            Spacer()
            Text(Format.uptime(since: SystemInfo.bootTime)).font(.system(size: 12)).foregroundStyle(Theme.sub)
            HStack(spacing: 6) {
                Circle().frame(width: 7, height: 7)
                Text(issues == 0 ? L10n.Overview.allGood : L10n.Overview.issues(issues))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(issues == 0 ? Theme.ok : Theme.warnText)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(issues == 0 ? Theme.okBg : Theme.warnBg))
        }
        .frame(height: 34)

        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                card(.cpu) {
                    BigValue(number: "\(Int((s.cpu.total * 100).rounded()))", unit: "%", color: Theme.cpu, size: 30, unitSize: 15)
                    Sparkline(values: monitor.history.latest(.cpu, seconds: 120).map { $0 / 100 }, color: Theme.cpu, lineWidth: 1.5, fillOpacity: 0.14, minCount: 60)
                        .frame(height: 36)
                    Text(L10n.Overview.cpuDetail(Format.percent(s.cpu.user), Format.percent(s.cpu.system))).font(.system(size: 11)).foregroundStyle(Theme.sub)
                }
                card(.gpu) {
                    BigValue(number: "\(Int((s.gpu.utilization * 100).rounded()))", unit: "%", color: Theme.gpu, size: 30, unitSize: 15)
                    Sparkline(values: monitor.history.latest(.gpu, seconds: 120).map { $0 / 100 }, color: Theme.gpu, lineWidth: 1.5, fillOpacity: 0.14, minCount: 60)
                        .frame(height: 36)
                    Text(s.gpu.temperature.map { L10n.Overview.gpuDetail(Format.memory(s.gpu.memoryUsed), Format.temperature($0, unit: unit, showUnit: true)) }
                         ?? L10n.Overview.gpuDetailNoTemp(Format.memory(s.gpu.memoryUsed)))
                        .font(.system(size: 11)).foregroundStyle(Theme.sub)
                }
                card(.memory) {
                    let pr = s.memory.pressure
                    HStack(spacing: 14) {
                        RingGauge(fraction: s.memory.usedFraction, color: Theme.mem, label: Format.percent(s.memory.usedFraction))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Format.memory(s.memory.used)).font(Fonts.big(20))
                            Text(L10n.Overview.memoryOf(Format.memory(s.memory.total))).font(.system(size: 11)).foregroundStyle(Theme.sub)
                            Text(pr == .normal ? L10n.Overview.pressureNormal : pr == .warning ? L10n.Overview.pressureWarning : L10n.Overview.pressureCritical)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(PanelText.pressure(pr).1)
                        }
                    }
                }
            }
            GridRow {
                card(.network) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(MenuBarText.downArrow + " " + Format.rate(s.network.down)).font(Fonts.big(18)).foregroundStyle(Theme.down)
                        Text(MenuBarText.upArrow + " " + Format.rate(s.network.up)).font(Fonts.big(14)).foregroundStyle(Theme.up)
                    }
                    .lineLimit(1).minimumScaleFactor(0.7)
                    let d = monitor.history.latest(.netDown, seconds: 120)
                    let u = monitor.history.latest(.netUp, seconds: 120)
                    let peak = max(d.max() ?? 0, u.max() ?? 0, 10_000)
                    MiniChart(series: [.init(values: d.map { $0 / peak }, color: Theme.down), .init(values: u.map { $0 / peak }, color: Theme.up, fill: 0)], gridLines: 0, minCount: 60)
                        .frame(height: 36)
                    Text(networkLine(s.network)).font(.system(size: 11)).foregroundStyle(Theme.sub)
                }
                card(.disk) {
                    let root = s.disk.root
                    HStack(spacing: 14) {
                        RingGauge(fraction: root?.usedFraction ?? 0, color: Theme.disk, label: Format.percent(root?.usedFraction ?? 0))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Format.storage(root?.available ?? 0)).font(Fonts.big(20))
                            Text(L10n.Overview.diskOf(Format.storage(root?.total ?? 0))).font(.system(size: 11)).foregroundStyle(Theme.sub)
                        }
                    }
                }
                card(.battery) {
                    let b = s.battery
                    if b.hasBattery {
                        HStack(spacing: 14) {
                            RingGauge(fraction: b.level, color: b.level <= 0.2 && !b.onAC ? Theme.low : Theme.bat, label: Format.percent(b.level))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.isCharging ? L10n.Battery.charging : b.onAC ? L10n.Battery.onAC : L10n.Battery.onBattery)
                                    .font(.system(size: 15, weight: .semibold))
                                if let line = batteryLine(b) { Text(line).font(.system(size: 11)).foregroundStyle(Theme.sub) }
                            }
                        }
                    } else {
                        Text(L10n.Overview.noBattery).font(.system(size: 13, weight: .semibold))
                        Text(L10n.Battery.deviceCount(monitor.bluetooth.count)).font(.system(size: 11)).foregroundStyle(Theme.sub)
                    }
                }
            }
            GridRow {
                card(.sensors) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(s.sensors.cpuAverage.map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash).font(Fonts.big(30)).foregroundStyle(Theme.temp)
                        Text(L10n.Overview.cpuTemp).font(.system(size: 11)).foregroundStyle(Theme.sub)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 4) {
                        HStack {
                            Text(L10n.Overview.fan).foregroundStyle(Theme.sub)
                            Spacer()
                            Text(s.sensors.fans.first.map { Format.rpm($0.rpm) } ?? L10n.Overview.noFan).fontWeight(.semibold)
                        }
                        if let w = s.sensors.systemPower {
                            HStack {
                                Text(L10n.Overview.power).foregroundStyle(Theme.sub)
                                Spacer()
                                Text(Format.watts(w)).fontWeight(.semibold)
                            }
                        }
                    }
                    .font(.system(size: 12))
                    .monospacedDigit()
                }
                topCard(s).gridCellColumns(2)
            }
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

    private func batteryLine(_ b: BatterySample) -> String? {
        if b.isCharging, let m = b.minutesToFull { return L10n.Battery.untilFull(Format.clockDuration(minutes: m)) }
        if !b.onAC, let m = b.minutesToEmpty { return L10n.Battery.remaining(Format.clockDuration(minutes: m)) }
        return b.health.map { L10n.Panel.healthShort(Format.percent($0)) }
    }

    private func card<Content: View>(_ m: Module, @ViewBuilder content: () -> Content) -> some View {
        Button {
            Navigator.shared.page = .monitor(m)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    LineIcon(d: Icons.module(m), size: 13, lineWidth: 1.6).foregroundStyle(Theme.color(for: m))
                    Text(m.title)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.sub)
                content()
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 158)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.group))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.groupRim, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.Panel.openMonitor(m.title))
    }

    private func topCard(_ s: Snapshot) -> some View {
        let list = Array((sortByMemory ? s.processes.byMemory : s.processes.byCPU).prefix(3))
        let maxValue = max(list.map { sortByMemory ? Double($0.memory) : $0.cpu }.max() ?? 1, 0.0001)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.Overview.topUsage).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.sub)
                Spacer()
                SegmentedPicker(label: L10n.Overview.sortBy, options: [(false, L10n.Module.cpu), (true, L10n.Module.memory)], selection: $sortByMemory, height: 20, fontSize: 11)
            }
            .frame(height: 34)
            ForEach(list) { p in
                HStack(spacing: 10) {
                    ProcessIcon(process: p, size: 22)
                    Text(p.name).lineLimit(1).frame(width: 130, alignment: .leading)
                    MeterBar(fraction: (sortByMemory ? Double(p.memory) : p.cpu) / maxValue, color: sortByMemory ? Theme.mem : Theme.cpu)
                    Text(sortByMemory ? Format.memory(p.memory) : Format.percentValue(p.cpu)).fontWeight(.semibold).monospacedDigit().frame(width: 64, alignment: .trailing)
                }
                .frame(height: 36)
                .overlay(alignment: .top) { Hairline() }
                .contentShape(Rectangle())
                .contextMenu { ProcessContextMenu(process: p) }
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 4, leading: 14, bottom: 6, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 158)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.group))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.groupRim, lineWidth: 0.5))
    }
}

// MARK: - CPU

struct CPUPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    @State private var range: TimeRange = .m5
    @State private var selectedPeak: Date?

    var body: some View {
        let s = monitor.snapshot
        let unit = settings.prefs.general.temperatureUnit
        let history = monitor.history
        let _ = monitor.tick
        let lookback = range == .h24
        let peaks = lookback ? history.cpuPeaks() : []
        let selected = selectedPeak.flatMap { d in peaks.first { $0.date == d } } ?? peaks.first

        PageHeader(icon: Icons.cpu, title: L10n.Module.cpu) {
            BigValue(number: "\(Int((s.cpu.total * 100).rounded()))", unit: "%", color: Theme.cpu)
        }
        HStack {
            RangePicker(range: $range)
            Spacer()
            if lookback { WellButton(title: L10n.Monitor.backToNow) { range = .m5 } }
        }
        Card(padding: EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14)) {
            MonitorChart(
                series: [
                    ChartSeries(id: "total", points: history.points(.cpu, range: range), color: Theme.cpu),
                    ChartSeries(id: "system", points: history.points(.cpuSystem, range: range), color: Theme.sys, fill: 0.22, lineWidth: 1.25),
                ],
                range: range, maxValue: 100, markers: peaks, selectedMarker: selected?.date, markerColor: Theme.cpu,
                hoverText: { date in hoverLines(date) },
                onTap: { date in
                    if let nearest = peaks.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }),
                       abs(nearest.date.timeIntervalSince(date)) < range.seconds / 30 { selectedPeak = nearest.date }
                }
            )
            .frame(height: lookback ? 180 : 150)
            .accessibilityLabel(L10n.Monitor.cpuChartA11y(range.title))
            HStack(spacing: 14) {
                LegendDot(color: Theme.cpu, label: L10n.Monitor.totalUsage)
                LegendDot(color: Theme.sys, label: L10n.Panel.system)
            }
            .padding(.top, 8)
        }

        if lookback {
            HStack(alignment: .top, spacing: 12) {
                PeakProcessList(title: selected.map { L10n.Monitor.peakTop(Format.dayAndTime($0.date)) } ?? L10n.Monitor.peakTopNone,
                                processes: selected?.top ?? [])
                    .frame(maxWidth: .infinity)
                peakCard(peaks, selected: selected?.date)
                    .frame(width: 230)
            }
        } else {
            StatsRow(items: [
                (Format.percent(s.cpu.user), L10n.Panel.user),
                (Format.percent(s.cpu.system), L10n.Panel.system),
                ("\(SystemInfo.coreCount)", L10n.Panel.cores),
                (s.sensors.cpuAverage.map { Format.temperature($0, unit: unit, showUnit: true) } ?? L10n.Common.dash, L10n.Panel.temperature),
            ])
            HStack(alignment: .top, spacing: 12) {
                Card {
                    CardTitle(text: L10n.Panel.cores, right: PanelText.coreSplit())
                    CoreBars(cpu: s.cpu, split: true, height: 52).padding(.top, 10)
                }
                .frame(maxWidth: .infinity)
                Card {
                    CardTitle(text: L10n.Panel.loadAverage)
                    VStack(spacing: 0) {
                        loadRow(L10n.Monitor.load1, s.cpu.load.0)
                        loadRow(L10n.Monitor.load5, s.cpu.load.1)
                        loadRow(L10n.Monitor.load15, s.cpu.load.2)
                    }
                    .padding(.top, 6)
                }
                .frame(width: 210)
            }
            WindowProcessList(title: L10n.Monitor.topCPU, processes: Array(s.processes.byCPU.prefix(8)), metric: .cpu, color: Theme.cpu)
        }
    }

    private func loadRow(_ label: String, _ v: Double) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.sub)
            Spacer()
            Text(Format.load(v)).fontWeight(.semibold).monospacedDigit()
        }
        .frame(height: 22)
    }

    private func hoverLines(_ date: Date) -> [String] {
        let history = monitor.history
        if range == .h24 || range == .d7, let b = history.bucket(near: date) {
            let cpu = Double(b.max[Metric.cpu.rawValue])
            return [Format.dayAndTime(Date(timeIntervalSince1970: b.start)), L10n.Monitor.peakValue(Format.percentValue(cpu))]
                + b.top.prefix(3).map { "\($0.name)  \(Format.percentValue($0.cpu))" }
        }
        let pts = history.points(.cpu, range: range)
        guard let p = pts.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) else { return [] }
        return [Format.time(p.date), L10n.Monitor.totalValue(Format.percentValue(p.value))]
    }

    private func peakCard(_ peaks: [PeakMarker], selected: Date?) -> some View {
        Card(padding: EdgeInsets(top: 4, leading: 14, bottom: 8, trailing: 14)) {
            Text(L10n.Monitor.peaks24h).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.sub).frame(height: 30)
            if peaks.isEmpty {
                Text(L10n.Monitor.noPeaks).font(.system(size: 12)).foregroundStyle(Theme.faint).padding(.vertical, 8)
            }
            ForEach(peaks) { peak in
                PeakRow(peak: peak, selected: peak.date == selected) { selectedPeak = peak.date }
            }
        }
    }
}

struct PeakRow: View {
    var peak: PeakMarker
    var selected: Bool
    var action: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Format.dayAndTime(peak.date)).fontWeight(.semibold)
                    Text(peak.top.first?.name ?? L10n.Common.dash).font(.system(size: 11))
                        .foregroundStyle(selected ? accent.tintText : Theme.sub)
                }
                Spacer()
                Text(Format.percent(peak.value / 100)).font(Fonts.big(16))
            }
            .foregroundStyle(selected ? accent.tintText : Theme.text)
            .padding(.horizontal, 6)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? accent.tint : .clear))
            .padding(.horizontal, -6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Busiest processes recorded at a past moment (no quit controls — they may be long gone).
struct PeakProcessList: View {
    var title: String
    var processes: [PeakProcess]

    var body: some View {
        Card(padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.sub).frame(height: 30)
            if processes.isEmpty {
                Text(L10n.Panel.noProcesses).foregroundStyle(Theme.faint).frame(height: 32)
            }
            let maxValue = max(processes.map(\.cpu).max() ?? 1, 0.0001)
            ForEach(processes, id: \.self) { p in
                HStack(spacing: 10) {
                    Text(String(p.name.prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.sub)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.chip))
                    Text(p.name).lineLimit(1).frame(width: 130, alignment: .leading)
                    MeterBar(fraction: p.cpu / maxValue, color: Theme.cpu)
                    Text(Format.percentValue(p.cpu)).fontWeight(.semibold).monospacedDigit().frame(width: 56, alignment: .trailing)
                }
                .frame(height: 32)
                .overlay(alignment: .top) { Hairline() }
            }
        }
    }
}

// MARK: - GPU

struct GPUPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    @State private var range: TimeRange = .m5

    var body: some View {
        let g = monitor.snapshot.gpu
        let unit = settings.prefs.general.temperatureUnit
        let _ = monitor.tick
        PageHeader(icon: Icons.gpu, title: L10n.Module.gpu) {
            BigValue(number: "\(Int((g.utilization * 100).rounded()))", unit: "%", color: Theme.gpu)
        }
        RangePicker(range: $range)
        Card(padding: EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14)) {
            MonitorChart(series: [ChartSeries(id: "gpu", points: monitor.history.points(.gpu, range: range), color: Theme.gpu, lineWidth: 2)],
                         range: range, maxValue: 100, hoverText: { simpleHover(.gpu, $0) })
                .frame(height: 130)
                .accessibilityLabel(L10n.Monitor.gpuChartA11y(range.title))
            HStack { LegendDot(color: Theme.gpu, label: L10n.Panel.utilization) }.padding(.top, 8)
        }
        StatsRow(items: [
            ("\(g.cores)", L10n.Panel.cores),
            (g.frequencyMHz.map(Format.frequency) ?? L10n.Common.dash, L10n.Panel.frequency),
            (g.temperature.map { Format.temperature($0, unit: unit, showUnit: true) } ?? L10n.Common.dash, L10n.Panel.temperature),
            (g.power.map(Format.watts) ?? L10n.Common.dash, L10n.Panel.power),
        ])
        HStack(alignment: .top, spacing: 12) {
            Card {
                CardTitle(text: L10n.Panel.vram, right: L10n.Monitor.unifiedMemory)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Format.memory(g.memoryUsed)).font(.system(size: 20, weight: .semibold)).monospacedDigit()
                    if g.memoryLimit > 0 {
                        Text(L10n.Monitor.usedOfLimit(Format.memory(g.memoryLimit))).foregroundStyle(Theme.sub)
                    }
                }
                .padding(.top, 10)
                MeterBar(fraction: g.memoryLimit > 0 ? Double(g.memoryUsed) / Double(g.memoryLimit) : 0, color: Theme.gpu, height: 6)
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity)
            Card {
                CardTitle(text: L10n.Panel.frequency)
                VStack(spacing: 0) {
                    kv(L10n.Monitor.current, g.frequencyMHz.map(Format.frequency))
                    kv(L10n.Monitor.average, g.averageMHz.map(Format.frequency))
                    kv(L10n.Monitor.highest, g.maxMHz.map(Format.frequency))
                }
                .padding(.top, 6)
            }
            .frame(width: 210)
        }
        WindowProcessList(title: L10n.Monitor.topGPU, processes: Array(monitor.snapshot.processes.byGPU.prefix(8)), metric: .gpu, color: Theme.gpu)
    }

    private func kv(_ k: String, _ v: String?) -> some View {
        HStack {
            Text(k).foregroundStyle(Theme.sub)
            Spacer()
            Text(v ?? L10n.Common.dash).fontWeight(.semibold).monospacedDigit()
        }
        .frame(height: 22)
    }

    private func simpleHover(_ metric: Metric, _ date: Date) -> [String] {
        let pts = monitor.history.points(metric, range: range)
        guard let p = pts.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) else { return [] }
        return [range.seconds > 3600 ? Format.dayAndTime(p.date) : Format.time(p.date), Format.percentValue(p.value)]
    }
}

// MARK: - Memory

struct MemoryPage: View {
    var monitor = Monitor.shared
    @State private var range: TimeRange = .m5

    var body: some View {
        let m = monitor.snapshot.memory
        let _ = monitor.tick
        PageHeader(icon: Icons.memory, title: L10n.Module.memory) {
            BigValue(number: "\(Int((m.usedFraction * 100).rounded()))", unit: "%", color: Theme.mem)
        }
        Card {
            MemoryComposition(m: m, height: 14)
                .accessibilityElement()
                .accessibilityLabel(L10n.Monitor.compositionA11y(Format.memory(m.app), Format.memory(m.wired), Format.memory(m.compressed), Format.memory(m.cached), Format.memory(m.free)))
            HStack(spacing: 16) {
                legend(Theme.mem, L10n.Monitor.appMemory, m.app)
                legend(Theme.mem.opacity(0.6), L10n.Memory.wired, m.wired)
                legend(Theme.mem.opacity(0.35), L10n.Monitor.compressed, m.compressed)
                legend(Theme.cache, L10n.Monitor.cache, m.cached)
                legend(Theme.track, L10n.Memory.free, m.free)
            }
            .padding(.top, 10)
        }
        RangePicker(range: $range)
        Card(padding: EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14)) {
            MonitorChart(series: [
                ChartSeries(id: "used", points: monitor.history.points(.memory, range: range), color: Theme.mem),
                ChartSeries(id: "pressure", points: monitor.history.points(.memoryPressure, range: range), color: Theme.ok, fill: 0, lineWidth: 1.25),
            ], range: range, maxValue: 100, hoverText: { hover($0) })
            .frame(height: 130)
            .accessibilityLabel(L10n.Monitor.memoryChartA11y(range.title))
            HStack(spacing: 14) {
                LegendDot(color: Theme.mem, label: L10n.Memory.used)
                LegendDot(color: Theme.ok, label: L10n.Panel.pressure)
            }
            .padding(.top, 8)
        }
        StatsRow(items: [
            (Format.memory(m.used), L10n.Memory.used),
            (Format.memory(m.total), L10n.Memory.total),
            (Format.memory(m.swapUsed), L10n.Memory.swap),
            (PanelText.pressure(m.pressure).0, L10n.Panel.pressure),
        ])
        WindowProcessList(title: L10n.Monitor.topMemory, processes: Array(monitor.snapshot.processes.byMemory.prefix(8)), metric: .memory, color: Theme.mem)
    }

    private func legend(_ c: Color, _ label: String, _ v: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Circle().fill(c).frame(width: 7, height: 7)
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.sub)
            }
            Text(Format.memory(v)).font(.system(size: 13, weight: .semibold)).monospacedDigit().padding(.leading, 12)
        }
    }

    private func hover(_ date: Date) -> [String] {
        let pts = monitor.history.points(.memory, range: range)
        guard let p = pts.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) else { return [] }
        return [range.seconds > 3600 ? Format.dayAndTime(p.date) : Format.time(p.date), L10n.Monitor.usedValue(Format.percentValue(p.value))]
    }
}

// MARK: - Network

struct NetworkPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    @State private var range: TimeRange = .m5

    var body: some View {
        let n = monitor.snapshot.network
        let unit = settings.prefs.network.speedUnit
        let _ = monitor.tick
        PageHeader(icon: Icons.network, title: L10n.Module.network) {
            if n.connected {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(MenuBarText.downArrow + " " + Format.rate(n.down, unit: unit)).font(Fonts.big(20)).foregroundStyle(Theme.down)
                    Text(MenuBarText.upArrow + " " + Format.rate(n.up, unit: unit)).font(Fonts.big(15)).foregroundStyle(Theme.up)
                }
                .monospacedDigit()
            } else {
                Text(L10n.Panel.notConnected).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.faint)
            }
        }
        RangePicker(range: $range)
        Card(padding: EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14)) {
            MonitorChart(series: [
                ChartSeries(id: "down", points: monitor.history.points(.netDown, range: range), color: Theme.down),
                ChartSeries(id: "up", points: monitor.history.points(.netUp, range: range), color: Theme.up, fill: 0),
            ], range: range, maxValue: nil, hoverText: { hover($0) })
            .frame(height: 150)
            .accessibilityLabel(L10n.Monitor.networkChartA11y(range.title))
            HStack(spacing: 14) {
                LegendDot(color: Theme.down, label: L10n.Panel.download)
                LegendDot(color: Theme.up, label: L10n.Panel.upload)
            }
            .padding(.top, 8)
        }
        StatsRow(items: [
            (L10n.Network.downUp(Format.storage(n.sessionDown), Format.storage(n.sessionUp)), L10n.Network.session),
            (L10n.Network.downUp(Format.storage(n.todayDown), Format.storage(n.todayUp)), L10n.Network.today),
            (n.interface.isEmpty ? L10n.Common.dash : PanelText.interface(n), L10n.Network.interface),
            (n.localIP.isEmpty ? L10n.Common.dash : n.localIP, L10n.Network.localIP),
        ])
        WindowProcessList(title: L10n.Monitor.topNetwork, processes: Array(monitor.snapshot.processes.byNetwork.prefix(8)), metric: .network, color: Theme.down)
    }

    private func hover(_ date: Date) -> [String] {
        let d = monitor.history.points(.netDown, range: range)
        let u = monitor.history.points(.netUp, range: range)
        guard let i = d.indices.min(by: { abs(d[$0].date.timeIntervalSince(date)) < abs(d[$1].date.timeIntervalSince(date)) }) else { return [] }
        let up = i < u.count ? u[i].value : 0
        return [range.seconds > 3600 ? Format.dayAndTime(d[i].date) : Format.time(d[i].date),
                MenuBarText.downArrow + " " + Format.rate(d[i].value), MenuBarText.upArrow + " " + Format.rate(up)]
    }
}

// MARK: - Disk

struct DiskPage: View {
    var monitor = Monitor.shared
    @State private var range: TimeRange = .m5

    var body: some View {
        let d = monitor.snapshot.disk
        let root = d.root
        let _ = monitor.tick
        PageHeader(icon: Icons.disk, title: L10n.Module.disk) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                let parts = Format.storage(root?.available ?? 0).split(separator: " ").map(String.init)
                Text(parts.first ?? "").font(Fonts.big(30)).foregroundStyle(Theme.disk)
                Text((parts.count > 1 ? parts[1] : "") + " " + L10n.Disk.free).font(Fonts.big(14)).foregroundStyle(Theme.disk)
            }
        }
        Card {
            if let root {
                HStack(spacing: 18) {
                    RingGauge(fraction: root.usedFraction, color: Theme.disk, size: 72, lineWidth: 8, label: Format.percent(root.usedFraction))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(root.name).font(.system(size: 15, weight: .semibold))
                        HStack(spacing: 24) {
                            StatBlock(value: Format.storage(root.used), label: L10n.Disk.used).fixedSize()
                            StatBlock(value: Format.storage(root.available), label: L10n.Disk.free).fixedSize()
                            StatBlock(value: Format.storage(root.total), label: L10n.Disk.total).fixedSize()
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            let others = d.volumes.filter { !$0.isRoot }
            if !others.isEmpty {
                Hairline().padding(.top, 12)
                DividedRows { ForEach(others) { VolumeBlock(volume: $0) } }
            }
        }
        HStack(spacing: 24) {
            StatBlock(value: Format.rate(d.read), label: L10n.Disk.read).fixedSize()
            StatBlock(value: Format.rate(d.write), label: L10n.Disk.write).fixedSize()
            Spacer()
            RangePicker(range: $range, options: [.m5, .m30, .h1, .h24])
        }
        .padding(.horizontal, 4)
        Card(padding: EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14)) {
            MonitorChart(series: [
                ChartSeries(id: "read", points: monitor.history.points(.diskRead, range: range), color: Theme.read),
                ChartSeries(id: "write", points: monitor.history.points(.diskWrite, range: range), color: Theme.write, fill: 0),
            ], range: range, maxValue: nil, hoverText: { hover($0) })
            .frame(height: 120)
            .accessibilityLabel(L10n.Monitor.diskChartA11y(range.title))
            HStack(spacing: 14) {
                LegendDot(color: Theme.read, label: L10n.Disk.read)
                LegendDot(color: Theme.write, label: L10n.Disk.write)
            }
            .padding(.top, 8)
        }
        StatsRow(items: [
            (Format.storage(d.totalRead), L10n.Disk.readSinceBoot),
            (Format.storage(d.totalWritten), L10n.Disk.writeSinceBoot),
        ])
        WindowProcessList(title: L10n.Panel.topDisk, processes: Array(monitor.snapshot.processes.byDisk.prefix(8)), metric: .disk, color: Theme.disk)
    }

    private func hover(_ date: Date) -> [String] {
        let r = monitor.history.points(.diskRead, range: range)
        let w = monitor.history.points(.diskWrite, range: range)
        guard let i = r.indices.min(by: { abs(r[$0].date.timeIntervalSince(date)) < abs(r[$1].date.timeIntervalSince(date)) }) else { return [] }
        return [range.seconds > 3600 ? Format.dayAndTime(r[i].date) : Format.time(r[i].date),
                L10n.Disk.read + " " + Format.rate(r[i].value), L10n.Disk.write + " " + Format.rate(i < w.count ? w[i].value : 0)]
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
        let unit = settings.prefs.general.temperatureUnit
        let _ = monitor.tick
        if b.hasBattery {
            PageHeader(icon: Icons.battery, title: L10n.Module.battery) {
                BigValue(number: "\(Int((b.level * 100).rounded()))", unit: "%", color: b.level <= 0.2 && !b.onAC ? Theme.low : Theme.bat)
            }
            Card {
                HStack(spacing: 12) {
                    IconChip(d: Icons.battery, size: 36, iconSize: 20, radius: 9, color: Theme.bat)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(b.isCharging ? L10n.Battery.charging : b.onAC ? (b.isCharged ? L10n.Battery.charged : L10n.Battery.onAC) : L10n.Battery.onBattery)
                            .font(.system(size: 14, weight: .semibold))
                        if let line = statusLine(b) { Text(line).font(.system(size: 12)).foregroundStyle(Theme.sub) }
                    }
                    Spacer(minLength: 0)
                }
            }
            StatsRow(items: [
                (b.health.map(Format.percent) ?? L10n.Common.dash, L10n.Battery.health),
                (b.cycles.map { "\($0)" } ?? L10n.Common.dash, L10n.Battery.cycles),
                ((b.temperature ?? s.sensors.value(.battery)).map { Format.temperature($0, unit: unit, showUnit: true) } ?? L10n.Common.dash, L10n.Battery.temperature),
                (currentPower(b).map(Format.watts) ?? L10n.Common.dash, L10n.Battery.power),
            ])
            Card(padding: EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14)) {
                HStack {
                    CardTitle(text: L10n.Battery.levelHistory)
                    RangePicker(range: $range, options: [.h24, .d7])
                }
                MonitorChart(series: [ChartSeries(id: "battery", points: monitor.history.points(.battery, range: range), color: Theme.bat)],
                             range: range, maxValue: 100, hoverText: { hover($0) })
                    .frame(height: 120)
                    .padding(.top, 10)
                    .accessibilityLabel(L10n.Panel.batteryChartA11y)
            }
        } else {
            PageHeader(icon: Icons.battery, title: L10n.Module.battery)
            Card {
                HStack(spacing: 12) {
                    IconChip(d: Icons.batteryOff, size: 36, iconSize: 20, radius: 9, color: Theme.faint, lineWidth: 1.3)
                    Text(L10n.Battery.noBattery).font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 0)
                }
            }
        }
        Card(padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
            HStack {
                Text(L10n.Battery.bluetooth).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.sub)
                Spacer()
                Text(L10n.Battery.deviceCount(monitor.bluetooth.count)).font(.system(size: 11)).foregroundStyle(Theme.faint)
            }
            .frame(height: 30)
            if monitor.bluetooth.isEmpty {
                Text(L10n.Battery.noDevices).foregroundStyle(Theme.faint).frame(height: 36)
            }
            ForEach(monitor.bluetooth) { DeviceRow(device: $0).overlay(alignment: .top) { Hairline() } }
        }
        if !b.ups.isEmpty {
            Card(padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
                Text(L10n.Battery.ups).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.sub).frame(height: 30)
                ForEach(b.ups) { UPSRow(source: $0).overlay(alignment: .top) { Hairline() } }
            }
        }
    }

    private func statusLine(_ b: BatterySample) -> String? {
        var parts: [String] = []
        if b.isCharging, let m = b.minutesToFull { parts.append(L10n.Battery.untilFull(Format.clockDuration(minutes: m))) }
        if !b.onAC, let m = b.minutesToEmpty { parts.append(L10n.Battery.remaining(Format.clockDuration(minutes: m))) }
        if b.onAC, let w = b.adapterWatts { parts.append(L10n.Battery.adapter(w)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func currentPower(_ b: BatterySample) -> Double? {
        if b.onAC { return b.systemPowerIn ?? b.power.map(abs) }
        return b.power.map(abs)
    }

    private func hover(_ date: Date) -> [String] {
        let pts = monitor.history.points(.battery, range: range)
        guard let p = pts.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) else { return [] }
        return [Format.dayAndTime(p.date), Format.percent(p.value / 100)]
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
        PageHeader(icon: Icons.sensors, title: L10n.Module.sensors) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(s.cpuAverage.map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash).font(Fonts.big(30)).foregroundStyle(Theme.temp)
                Text(L10n.Monitor.cpuAverageShort).font(.system(size: 12)).foregroundStyle(Theme.sub)
            }
        }
        RangePicker(range: $range, options: [.m5, .m30, .h1, .h24])
        Card(padding: EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14)) {
            MonitorChart(series: [
                ChartSeries(id: "cpu", points: monitor.history.points(.cpuTemp, range: range), color: Theme.temp),
                ChartSeries(id: "gpu", points: monitor.history.points(.gpuTemp, range: range), color: Theme.gpu, fill: 0, lineWidth: 1.25),
            ], range: range, maxValue: 110, hoverText: { hover($0, unit) })
            .frame(height: 130)
            .accessibilityLabel(L10n.Monitor.tempChartA11y(range.title))
            HStack(spacing: 14) {
                LegendDot(color: Theme.temp, label: L10n.Module.cpu)
                LegendDot(color: Theme.gpu, label: L10n.Module.gpu)
            }
            .padding(.top, 8)
        }
        HStack(alignment: .top, spacing: 12) {
            Card(padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
                Text(L10n.Sensors.temperatures).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.sub).frame(height: 30)
                ForEach(s.temps) { t in
                    MeterRow(name: PanelText.tempName(t.group), fraction: t.value / 110, value: Format.temperature(t.value, unit: unit, showUnit: true), color: Theme.temp)
                        .frame(height: 32)
                        .overlay(alignment: .top) { Hairline() }
                }
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 12) {
                let th = PanelText.thermal(s.thermal)
                Card {
                    CardTitle(text: L10n.Sensors.thermalState)
                    StatusBadge(text: th.0, fg: th.1, bg: th.2).padding(.top, 8)
                }
                Card {
                    CardTitle(text: L10n.Sensors.fans)
                    if s.fans.isEmpty {
                        Text(L10n.Sensors.fanless).foregroundStyle(Theme.faint).padding(.top, 8)
                    }
                    ForEach(s.fans) { f in
                        HStack {
                            Text(PanelText.fanName(f.id, count: s.fans.count)).foregroundStyle(Theme.sub)
                            Spacer()
                            Text(Format.rpm(f.rpm)).fontWeight(.semibold).monospacedDigit()
                        }
                        .frame(height: 24)
                    }
                }
                Card {
                    CardTitle(text: L10n.Sensors.power)
                    VStack(spacing: 0) {
                        powerRow(L10n.Monitor.system, s.systemPower)
                        powerRow(L10n.Module.cpu, s.cpuPower)
                        powerRow(L10n.Module.gpu, s.gpuPower)
                    }
                    .padding(.top, 6)
                }
            }
            .frame(width: 210)
        }
    }

    private func powerRow(_ label: String, _ w: Double?) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.sub)
            Spacer()
            Text(w.map(Format.watts) ?? L10n.Common.dash).fontWeight(.semibold).monospacedDigit()
        }
        .frame(height: 22)
    }

    private func hover(_ date: Date, _ unit: TemperatureUnit) -> [String] {
        let c = monitor.history.points(.cpuTemp, range: range)
        let g = monitor.history.points(.gpuTemp, range: range)
        guard let i = c.indices.min(by: { abs(c[$0].date.timeIntervalSince(date)) < abs(c[$1].date.timeIntervalSince(date)) }) else { return [] }
        var lines = [range.seconds > 3600 ? Format.dayAndTime(c[i].date) : Format.time(c[i].date),
                     L10n.Module.cpu + " " + Format.temperature(c[i].value, unit: unit, showUnit: true)]
        if i < g.count { lines.append(L10n.Module.gpu + " " + Format.temperature(g[i].value, unit: unit, showUnit: true)) }
        return lines
    }
}
