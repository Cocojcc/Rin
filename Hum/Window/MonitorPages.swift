import SwiftUI

private func nearest(_ points: [ChartPoint], _ date: Date) -> Int? {
    points.indices.min { abs(points[$0].date.timeIntervalSince(date)) < abs(points[$1].date.timeIntervalSince(date)) }
}

private func timeLabel(_ date: Date, _ range: TimeRange) -> String {
    range.seconds > 3600 ? Format.dayAndTime(date) : Format.time(date)
}

private func percentNumber(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))" }

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
        let issues = alerts.active.count
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: L10n.Overview.title) {
                Text(Format.uptime(since: SystemInfo.bootTime)).ui(12).foregroundStyle(Theme.sub)
                StatusPill(text: issues == 0 ? L10n.Overview.allGood : L10n.Overview.issues(issues),
                           fg: issues == 0 ? Theme.ok : Theme.warn, bg: issues == 0 ? Theme.okBg : Theme.warnBg,
                           dot: true, fontSize: 12, height: 24, radius: 12)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 176), spacing: 12)], spacing: 12) {
                card(.cpu, value: percentNumber(s.cpu.total), unit: "%",
                     footer: L10n.Overview.cpuDetail(Format.percent(s.cpu.user), Format.percent(s.cpu.system))) {
                    Sparkline(values: monitor.history.latest(.cpu, seconds: 120).map { $0 / 100 }, color: Theme.cpu, lineWidth: 1.5, fillOpacity: 0.12, minCount: 60)
                        .frame(height: 28)
                }
                card(.gpu, value: percentNumber(s.gpu.utilization), unit: "%",
                     footer: s.gpu.temperature.map { L10n.Overview.gpuDetail(Format.memory(s.gpu.memoryUsed), Format.temperature($0, unit: unit, showUnit: true)) }
                        ?? L10n.Overview.gpuDetailNoTemp(Format.memory(s.gpu.memoryUsed))) {
                    Sparkline(values: monitor.history.latest(.gpu, seconds: 120).map { $0 / 100 }, color: Theme.gpu, lineWidth: 1.5, fillOpacity: 0.12, minCount: 60)
                        .frame(height: 28)
                }
                let usedGB = Format.memory(s.memory.used).split(separator: " ").map(String.init)
                card(.memory, value: usedGB.first ?? "", unit: usedGB.count > 1 ? " " + usedGB[1] : "",
                     ring: (s.memory.usedFraction, Theme.mem, Format.percent(s.memory.usedFraction), false)) {
                    Text(L10n.Overview.memoryOf(Format.memory(s.memory.total))).ui(12).foregroundStyle(Theme.sub)
                    Spacer(minLength: 0)
                    let pr = PanelText.pressure(s.memory.pressure)
                    Text(s.memory.pressure == .normal ? L10n.Overview.pressureNormal : s.memory.pressure == .warning ? L10n.Overview.pressureWarning : L10n.Overview.pressureCritical)
                        .ui(12, 500).foregroundStyle(pr.1)
                }
                let downParts = Format.rateParts(s.network.down)
                card(.network, value: s.network.connected ? MenuBarText.downArrow + " " + downParts.0 : L10n.Common.dash,
                     unit: s.network.connected ? " " + downParts.1 : "",
                     footer: s.network.connected ? MenuBarText.upArrow + " " + Format.rate(s.network.up) + " · " + networkLine(s.network) : networkLine(s.network)) {
                    let d = monitor.history.latest(.netDown, seconds: 120)
                    let peak = max(d.max() ?? 0, 10_000)
                    Sparkline(values: d.map { $0 / peak }, color: Theme.down, lineWidth: 1.5, fillOpacity: 0.12, minCount: 60)
                        .frame(height: 28)
                }
                let root = s.disk.root
                let free = Format.storage(root?.available ?? 0).split(separator: " ").map(String.init)
                card(.disk, value: free.first ?? "", unit: free.count > 1 ? " " + free[1] : "",
                     footer: L10n.Overview.diskOf(Format.storage(root?.total ?? 0)),
                     ring: (root?.usedFraction ?? 0, Theme.disk, Format.percent(root?.usedFraction ?? 0), false)) { EmptyView() }
                let b = s.battery
                if b.hasBattery {
                    card(.battery, value: percentNumber(b.level), unit: "%", footer: batteryLine(b),
                         ring: (b.level, b.level <= 0.2 && !b.onAC ? Theme.danger : Theme.bat, Format.percent(b.level), b.isCharging)) { EmptyView() }
                } else {
                    card(.battery, value: L10n.Common.dash, unit: "", footer: L10n.Battery.deviceCount(monitor.bluetooth.count)) { EmptyView() }
                }
            }
            sensorsCard(s, unit)
            topCard(s)
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

    private func batteryLine(_ b: BatterySample) -> String {
        if b.isCharging, let m = b.minutesToFull { return L10n.Battery.charging + " · " + L10n.Battery.untilFull(Format.clockDuration(minutes: m)) }
        if b.isCharging { return L10n.Battery.charging }
        if !b.onAC, let m = b.minutesToEmpty { return L10n.Battery.remaining(Format.clockDuration(minutes: m)) }
        return b.onAC ? L10n.Battery.onAC : L10n.Battery.onBattery
    }

    private func card<Extra: View>(_ m: Module, value: String, unit: String, footer: String? = nil,
                                   ring: (Double, Color, String, Bool)? = nil, @ViewBuilder extra: () -> Extra) -> some View {
        Button {
            Navigator.shared.page = .monitor(m)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(m.title).ui(13, 500).foregroundStyle(Theme.sub).frame(height: 18)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(value).ui(24, 500).kerning(-0.48)
                    Text(unit).ui(15).foregroundStyle(Theme.sub)
                }
                .lineLimit(1)
                .frame(height: 30)
                extra()
                Spacer(minLength: 0)
                if let footer { Text(footer).ui(12).foregroundStyle(Theme.sub).lineLimit(1) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 150)
            .overlay(alignment: .topTrailing) {
                if let ring {
                    ZStack {
                        Ring(fraction: ring.0, color: ring.1, size: 44, lineWidth: 3)
                        if ring.3 {
                            SVGShape(d: Icons.bolt, viewBox: CGSize(width: 12, height: 12)).fill(ring.1).frame(width: 12, height: 12)
                        } else {
                            Text(ring.2).ui(12, 500)
                        }
                    }
                    .padding(.top, 42)
                    .padding(.trailing, 14)
                }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.Panel.openMonitor(m.title))
    }

    private func sensorsCard(_ s: Snapshot, _ unit: TemperatureUnit) -> some View {
        Button {
            Navigator.shared.page = .monitor(.sensors)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                Text(L10n.Module.sensors).ui(13, 500).foregroundStyle(Theme.sub)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(s.sensors.cpuAverage.map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash).ui(24, 500).kerning(-0.48)
                    Text(L10n.Overview.cpuTemp).ui(12).foregroundStyle(Theme.sub)
                }
                Spacer(minLength: 0)
                HStack(spacing: 24) {
                    pair(L10n.Overview.fan, s.sensors.fans.first.map { Format.rpm($0.rpm) } ?? L10n.Overview.noFan)
                    if let w = s.sensors.systemPower { pair(L10n.Overview.power, Format.watts(w)) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pair(_ k: String, _ v: String) -> some View {
        HStack(spacing: 4) {
            Text(k).foregroundStyle(Theme.sub)
            Text(v).fontWeight(.medium)
        }
        .ui(12)
    }

    private func topCard(_ s: Snapshot) -> some View {
        let list = Array((sortByMemory ? s.processes.byMemory : s.processes.byCPU).prefix(3))
        let maxValue = max(list.map { sortByMemory ? Double($0.memory) : $0.cpu }.max() ?? 1, 0.0001)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.Overview.topUsage).ui(13, 500).foregroundStyle(Theme.sub)
                Spacer()
                Segmented(label: L10n.Overview.sortBy, options: [(false, L10n.Module.cpu), (true, L10n.Module.memory)], selection: $sortByMemory, style: .tab)
            }
            .frame(height: 28)
            .padding(.bottom, 4)
            ForEach(list) { p in
                HStack(spacing: 10) {
                    ProcessIcon(process: p, size: 18)
                    Text(p.name).lineLimit(1).frame(width: 120, alignment: .leading)
                    MeterBar(fraction: (sortByMemory ? Double(p.memory) : p.cpu) / maxValue, color: sortByMemory ? Theme.mem : Theme.cpu)
                    Text(sortByMemory ? Format.memory(p.memory) : Format.percentValue(p.cpu)).ui(13, 500).frame(width: 56, alignment: .trailing)
                }
                .frame(height: 30)
                .contentShape(Rectangle())
                .contextMenu { ProcessContextMenu(process: p) }
            }
            if list.isEmpty { Text(L10n.Panel.noProcesses).foregroundStyle(Theme.faint).frame(height: 30) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
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

        VStack(alignment: .leading, spacing: 16) {
            MonitorHeader(title: L10n.Module.cpu, value: percentNumber(s.cpu.total), unit: "%") {
                HStack(spacing: 8) {
                    RangeControl(range: $range, width: lookback ? 300 : 320)
                    if lookback { WellButton(title: L10n.Monitor.backToNow, height: 34, radius: 11) { range = .m5 } }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                ChartBlock(height: lookback ? 150 : 100, legend: lookback ? [] : [(Theme.cpu, L10n.Monitor.totalUsage, nil), (Theme.sys, L10n.Panel.system, nil)]) {
                    MonitorChart(
                        series: [
                            ChartSeries(id: "total", points: history.points(.cpu, range: range), color: Theme.cpu, lineWidth: lookback ? 1.5 : 2),
                            ChartSeries(id: "system", points: lookback ? [] : history.points(.cpuSystem, range: range), color: Theme.sys, fill: 0, lineWidth: 1.5),
                        ],
                        range: range, maxValue: 100, markers: peaks, selectedMarker: selected?.date, markerColor: Theme.cpu,
                        hoverText: { hoverLines($0) },
                        onTap: { date in
                            if let nearest = peaks.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }),
                               abs(nearest.date.timeIntervalSince(date)) < range.seconds / 30 { selectedPeak = nearest.date }
                        },
                        pinnedTip: selected.map { peakTip($0) }
                    )
                    .accessibilityLabel(L10n.Monitor.cpuChartA11y(range.title))
                }
                if lookback || range == .d7 { TimeAxisLabels(range: range).padding(.top, 8) }
            }

            if lookback {
                TitledSection(title: L10n.Monitor.peaks24h) {
                    VStack(spacing: 0) {
                        if peaks.isEmpty {
                            Text(L10n.Monitor.noPeaks).ui(13).foregroundStyle(Theme.faint)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 46)
                        }
                        ForEach(peaks) { peak in
                            PeakRow(peak: peak, selected: peak.date == selected?.date) { selectedPeak = peak.date }
                        }
                    }
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
                }
                TitledSection(title: selected.map { L10n.Monitor.peakTop(Format.dayAndTime($0.date)) } ?? L10n.Monitor.peakTopNone) {
                    PeakProcessList(processes: selected?.top ?? [])
                }
            } else {
                StatsGrid(items: [
                    (Format.percent(s.cpu.user), L10n.Panel.user, nil),
                    (Format.percent(s.cpu.system), L10n.Panel.system, nil),
                    ("\(SystemInfo.coreCount)", L10n.Panel.cores, nil),
                    (s.sensors.cpuAverage.map { Format.temperature($0, unit: unit, showUnit: true) } ?? L10n.Common.dash, L10n.Panel.temperature, nil),
                ])
                TitledSection(title: L10n.Panel.cores, right: PanelText.coreSplit()) {
                    Panel {
                        CoreBars(cpu: s.cpu, split: true, height: 44, gap: 14)
                    }
                }
                TitledSection(title: L10n.Panel.loadAverage) {
                    CellStrip(cells: [(Format.load(s.cpu.load.0), L10n.Monitor.load1), (Format.load(s.cpu.load.1), L10n.Monitor.load5), (Format.load(s.cpu.load.2), L10n.Monitor.load15)])
                }
                TitledSection(title: L10n.Monitor.topCPU) {
                    ProcessListPanel(processes: Array(s.processes.byCPU.prefix(8)), metric: .cpu, color: Theme.cpu)
                }
            }
        }
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
        guard let i = nearest(pts, date) else { return [] }
        return [Format.time(pts[i].date) + "\t" + Format.percent(pts[i].value / 100)]
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
                bar(cpu.perCore[i], dim: false)
            }
            if !eff.isEmpty {
                Spacer(minLength: gap)
                ForEach(Array(eff.enumerated()), id: \.offset) { n, i in
                    if n > 0 { Spacer(minLength: 0) }
                    bar(cpu.perCore[i], dim: true)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func bar(_ v: Double, dim: Bool) -> some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(Theme.track)
            Capsule().fill(color.opacity(dim ? 0.5 : 1)).frame(height: height * min(1, max(0, v)))
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
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Theme.raised : .clear).raisedShadow(selected))
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
        let unit = settings.prefs.general.temperatureUnit
        let _ = monitor.tick
        VStack(alignment: .leading, spacing: 16) {
            MonitorHeader(title: L10n.Module.gpu, value: percentNumber(g.utilization), unit: "%") {
                RangeControl(range: $range)
            }
            ChartBlock(height: 100, legend: [(Theme.gpu, L10n.Panel.utilization, nil)]) {
                MonitorChart(series: [ChartSeries(id: "gpu", points: monitor.history.points(.gpu, range: range), color: Theme.gpu)],
                             range: range, maxValue: 100, hoverText: { simpleHover(.gpu, $0) })
                    .accessibilityLabel(L10n.Monitor.gpuChartA11y(range.title))
            }
            StatsGrid(items: [
                ("\(g.cores)", L10n.Panel.cores, nil),
                (g.frequencyMHz.map(Format.frequency) ?? L10n.Common.dash, L10n.Panel.frequency, nil),
                (g.temperature.map { Format.temperature($0, unit: unit, showUnit: true) } ?? L10n.Common.dash, L10n.Panel.temperature, nil),
                (g.power.map(Format.watts) ?? L10n.Common.dash, L10n.Panel.power, nil),
            ])
            TitledSection(title: L10n.Panel.vram, right: L10n.Monitor.unifiedMemory) {
                Panel {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Format.memory(g.memoryUsed)).ui(18, 500)
                        if g.memoryLimit > 0 { Text(L10n.Monitor.usedOfLimit(Format.memory(g.memoryLimit))).foregroundStyle(Theme.sub) }
                    }
                    MeterBar(fraction: g.memoryLimit > 0 ? Double(g.memoryUsed) / Double(g.memoryLimit) : 0, color: Theme.gpu, height: 4)
                        .padding(.top, 12)
                }
            }
            TitledSection(title: L10n.Panel.frequency) {
                CellStrip(cells: [
                    (g.frequencyMHz.map(Format.frequency) ?? L10n.Common.dash, L10n.Monitor.current),
                    (g.averageMHz.map(Format.frequency) ?? L10n.Common.dash, L10n.Monitor.average),
                    (g.maxMHz.map(Format.frequency) ?? L10n.Common.dash, L10n.Monitor.highest),
                ])
            }
            TitledSection(title: L10n.Monitor.topGPU) {
                ProcessListPanel(processes: Array(monitor.snapshot.processes.byGPU.prefix(8)), metric: .gpu, color: Theme.gpu)
            }
        }
    }

    private func simpleHover(_ metric: Metric, _ date: Date) -> [String] {
        let pts = monitor.history.points(metric, range: range)
        guard let i = nearest(pts, date) else { return [] }
        return [timeLabel(pts[i].date, range) + "\t" + Format.percent(pts[i].value / 100)]
    }
}

// MARK: - Memory

struct MemoryPage: View {
    var monitor = Monitor.shared
    @State private var range: TimeRange = .m5

    var body: some View {
        let m = monitor.snapshot.memory
        let _ = monitor.tick
        let pr = PanelText.pressure(m.pressure)
        VStack(alignment: .leading, spacing: 16) {
            MonitorHeader(title: L10n.Module.memory, value: percentNumber(m.usedFraction), unit: "%") {
                RangeControl(range: $range)
            }
            ChartBlock(height: 120) {
                MonitorChart(series: [ChartSeries(id: "used", points: monitor.history.points(.memory, range: range), color: Theme.mem)],
                             range: range, maxValue: 100, hoverText: { hover($0) })
                    .accessibilityLabel(L10n.Monitor.memoryChartA11y(range.title))
            }
            StatsGrid(items: [
                (Format.memory(m.used), L10n.Memory.used, nil),
                (Format.memory(m.total), L10n.Memory.total, nil),
                (Format.memory(m.swapUsed), L10n.Memory.swap, nil),
                (pr.0, L10n.Panel.pressure, pr.1),
            ])
            TitledSection(title: L10n.Panel.composition) {
                Panel {
                    MemoryComposition(m: m, height: 5)
                        .accessibilityElement()
                        .accessibilityLabel(L10n.Monitor.compositionA11y(Format.memory(m.app), Format.memory(m.wired), Format.memory(m.compressed), Format.memory(m.cached), Format.memory(m.free)))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 20)], alignment: .leading, spacing: 6) {
                        MemoryLegend(color: Theme.mem, label: L10n.Monitor.appMemory, bytes: m.app, size: 7)
                        MemoryLegend(color: Theme.mem.opacity(0.6), label: L10n.Memory.wired, bytes: m.wired, size: 7)
                        MemoryLegend(color: Theme.mem.opacity(0.35), label: L10n.Monitor.compressed, bytes: m.compressed, size: 7)
                        MemoryLegend(color: Theme.cache, label: L10n.Monitor.cache, bytes: m.cached, size: 7)
                        MemoryLegend(color: Theme.track, label: L10n.Memory.free, bytes: m.free, size: 7, ring: true)
                    }
                    .padding(.top, 12)
                }
            }
            TitledSection(title: L10n.Monitor.topMemory) {
                ProcessListPanel(processes: Array(monitor.snapshot.processes.byMemory.prefix(8)), metric: .memory, color: Theme.mem)
            }
        }
    }

    private func hover(_ date: Date) -> [String] {
        let pts = monitor.history.points(.memory, range: range)
        guard let i = nearest(pts, date) else { return [] }
        return [timeLabel(pts[i].date, range) + "\t" + Format.percent(pts[i].value / 100)]
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

// MARK: - Network

struct NetworkPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    @State private var range: TimeRange = .m5

    var body: some View {
        let n = monitor.snapshot.network
        let unit = settings.prefs.network.speedUnit
        let _ = monitor.tick
        let down = Format.rateParts(n.down, unit: unit)
        VStack(alignment: .leading, spacing: 20) {
            MonitorHeader(title: L10n.Module.network,
                          value: n.connected ? MenuBarText.downArrow + " " + down.0 : L10n.Panel.notConnected,
                          unit: n.connected ? down.1 : "",
                          secondLine: n.connected ? MenuBarText.upArrow + " " + Format.rate(n.up, unit: unit) : nil) {
                RangeControl(range: $range)
            }
            ChartBlock(height: 120, legend: [(Theme.down, L10n.Panel.download, nil), (Theme.up, L10n.Panel.upload, nil)]) {
                MonitorChart(series: [
                    ChartSeries(id: "down", points: monitor.history.points(.netDown, range: range), color: Theme.down),
                    ChartSeries(id: "up", points: monitor.history.points(.netUp, range: range), color: Theme.up, fill: 0, lineWidth: 1.5),
                ], range: range, maxValue: nil, hoverText: { hover($0) })
                .accessibilityLabel(L10n.Monitor.networkChartA11y(range.title))
            }
            StatsGrid(items: [
                (L10n.Network.downUpCompact(Format.storage(n.sessionDown), Format.storage(n.sessionUp)), L10n.Network.session, nil),
                (L10n.Network.downUpCompact(Format.storage(n.todayDown), Format.storage(n.todayUp)), L10n.Network.today, nil),
                (n.interface.isEmpty ? L10n.Common.dash : PanelText.interface(n), L10n.Network.interface, nil),
                (n.localIP.isEmpty ? L10n.Common.dash : n.localIP, L10n.Network.localIP, nil),
            ], valueSize: 15)
            TitledSection(title: L10n.Monitor.topNetwork) {
                ProcessListPanel(processes: Array(monitor.snapshot.processes.byNetwork.prefix(8)), metric: .network, color: Theme.down, valueWidth: 80)
            }
        }
    }

    private func hover(_ date: Date) -> [String] {
        let d = monitor.history.points(.netDown, range: range)
        let u = monitor.history.points(.netUp, range: range)
        guard let i = nearest(d, date) else { return [] }
        return [timeLabel(d[i].date, range), L10n.Panel.download + "\t" + Format.rate(d[i].value), L10n.Panel.upload + "\t" + Format.rate(i < u.count ? u[i].value : 0)]
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
        let free = Format.storage(root?.available ?? 0).split(separator: " ").map(String.init)
        VStack(alignment: .leading, spacing: 20) {
            MonitorHeader(title: L10n.Module.disk, value: free.first ?? "", unit: L10n.Disk.unitFree(free.count > 1 ? free[1] : "")) {
                RangeControl(range: $range, options: [.m5, .m30, .h1], width: 192)
            }
            Panel {
                VStack(spacing: 0) {
                    DividedRows {
                        ForEach(d.volumes) { v in
                            VolumeSummary(volume: v).padding(.vertical, v.isRoot ? 0 : 14)
                        }
                    }
                }
            }
            ChartBlock(height: 110, legend: [(Theme.read, L10n.Disk.read, Format.rate(d.read)), (Theme.write, L10n.Disk.write, Format.rate(d.write))]) {
                MonitorChart(series: [
                    ChartSeries(id: "read", points: monitor.history.points(.diskRead, range: range), color: Theme.read),
                    ChartSeries(id: "write", points: monitor.history.points(.diskWrite, range: range), color: Theme.write, fill: 0, lineWidth: 1.5),
                ], range: range, maxValue: nil, hoverText: { hover($0) })
                .accessibilityLabel(L10n.Monitor.diskChartA11y(range.title))
            }
            StatsGrid(items: [
                (Format.storage(d.totalRead), L10n.Disk.readSinceBoot, nil),
                (Format.storage(d.totalWritten), L10n.Disk.writeSinceBoot, nil),
            ])
            TitledSection(title: L10n.Panel.topDisk) {
                ProcessListPanel(processes: Array(monitor.snapshot.processes.byDisk.prefix(8)), metric: .disk, color: Theme.read, valueWidth: 72)
            }
        }
    }

    private func hover(_ date: Date) -> [String] {
        let r = monitor.history.points(.diskRead, range: range)
        let w = monitor.history.points(.diskWrite, range: range)
        guard let i = nearest(r, date) else { return [] }
        return [timeLabel(r[i].date, range), L10n.Disk.read + "\t" + Format.rate(r[i].value), L10n.Disk.write + "\t" + Format.rate(i < w.count ? w[i].value : 0)]
    }
}

/// Ring + name + used / free / total for one volume.
struct VolumeSummary: View {
    var volume: Volume

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Ring(fraction: volume.usedFraction, color: Theme.disk, size: 60, lineWidth: 3)
                Text(Format.percent(volume.usedFraction)).ui(12, 500)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(volume.name).ui(15, 500)
                    if !volume.isInternal { StatusPill(text: L10n.Disk.external, fg: Theme.sub, bg: Theme.well, fontSize: 11, height: 16, radius: 5) }
                    if volume.isEjectable && !volume.isRoot { EjectButton(volume: volume) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 12, alignment: .leading)], alignment: .leading, spacing: 12) {
                    StatBlock(value: Format.storage(volume.used), label: L10n.Disk.used, valueSize: 15)
                    StatBlock(value: Format.storage(volume.available), label: L10n.Disk.free, valueSize: 15)
                    StatBlock(value: Format.storage(volume.total), label: L10n.Disk.total, valueSize: 15)
                }
            }
        }
    }
}

struct EjectButton: View {
    var volume: Volume

    var body: some View {
        Button {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
        } label: {
            SVGShape(d: "M6 1.5L10.5 7h-9zM1.5 8.5h9v1.6h-9z", viewBox: CGSize(width: 12, height: 12))
                .fill(Theme.text)
                .frame(width: 9, height: 9)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.raised).raisedShadow())
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
        let unit = settings.prefs.general.temperatureUnit
        let _ = monitor.tick
        VStack(alignment: .leading, spacing: 20) {
            if b.hasBattery {
                MonitorHeader(title: L10n.Module.battery, value: percentNumber(b.level), unit: "%")
                Panel {
                    HStack(spacing: 16) {
                        BatteryOutline(level: b.level, color: b.level <= 0.2 && !b.onAC ? Theme.danger : Theme.bat)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(statusTitle(b)).ui(15, 500)
                            if let line = statusLine(b) { Text(line).ui(12).foregroundStyle(Theme.sub) }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                StatsGrid(items: [
                    (b.health.map(Format.percent) ?? L10n.Common.dash, L10n.Battery.health, b.health.map { $0 >= 0.8 ? Theme.ok : Theme.warn }),
                    (b.cycles.map { "\($0)" } ?? L10n.Common.dash, L10n.Battery.cycles, nil),
                    ((b.temperature ?? s.sensors.value(.battery)).map { Format.temperature($0, unit: unit, showUnit: true) } ?? L10n.Common.dash, L10n.Battery.temperature, nil),
                    (currentPower(b).map(Format.watts) ?? L10n.Common.dash, L10n.Battery.power, nil),
                ])
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.Battery.levelHistory).ui(13, 500).foregroundStyle(Theme.sub)
                        Spacer()
                        Segmented(label: L10n.Range.label, options: [(TimeRange.h24, TimeRange.h24.title), (.d7, TimeRange.d7.title)], selection: $range)
                    }
                    .padding(.horizontal, 14)
                    ChartBlock(height: 100) {
                        MonitorChart(series: [ChartSeries(id: "battery", points: monitor.history.points(.battery, range: range), color: Theme.bat)],
                                     range: range, maxValue: 100, hoverText: { hover($0) })
                            .accessibilityLabel(L10n.Panel.batteryChartA11y)
                    }
                }
                TitledSection(title: L10n.Battery.bluetooth) {
                    VStack(spacing: 0) {
                        if monitor.bluetooth.isEmpty {
                            Text(L10n.Battery.noDevices).ui(13).foregroundStyle(Theme.faint)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 32)
                        }
                        ForEach(monitor.bluetooth) { d in
                            HStack(spacing: 12) {
                                Text(d.name).lineLimit(1)
                                Spacer(minLength: 0)
                                MeterBar(fraction: d.level, color: d.level <= 0.2 ? Theme.danger : Theme.bat).frame(width: 120)
                                Text(Format.percent(d.level)).ui(13, 500).frame(width: 44, alignment: .trailing)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
                }
            } else {
                PageTitle(title: L10n.Module.battery)
                Panel {
                    HStack(spacing: 14) {
                        LineIcon(d: Icons.batteryOff, size: 16, lineWidth: 1.4)
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.well))
                        Text(L10n.Battery.noBattery).ui(15, 500)
                    }
                }
                TitledSection(title: L10n.Battery.bluetooth, right: L10n.Battery.deviceCount(monitor.bluetooth.count)) {
                    VStack(spacing: 0) {
                        if monitor.bluetooth.isEmpty {
                            Text(L10n.Battery.noDevices).ui(13).foregroundStyle(Theme.faint).frame(maxWidth: .infinity, alignment: .leading).frame(height: 54)
                        }
                        DividedRows { ForEach(monitor.bluetooth) { DeviceRow(device: $0) } }
                    }
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
                }
            }
            if !b.ups.isEmpty {
                TitledSection(title: L10n.Battery.ups) {
                    VStack(spacing: 0) { DividedRows { ForEach(b.ups) { UPSRow(source: $0) } } }
                        .padding(.horizontal, 14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
                }
            }
        }
    }

    private func statusTitle(_ b: BatterySample) -> String {
        if b.isCharging { return L10n.Battery.charging }
        if b.onAC { return b.isCharged ? L10n.Battery.charged : L10n.Battery.onAC }
        return L10n.Battery.onBattery
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
        guard let i = nearest(pts, date) else { return [] }
        return [Format.dayAndTime(pts[i].date) + "\t" + Format.percent(pts[i].value / 100)]
    }
}

/// Large battery outline (46 × 22) used on the battery page.
struct BatteryOutline: View {
    var level: Double
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 46
            ctx.stroke(Path(roundedRect: CGRect(x: 0.75 * s, y: 0.75 * s, width: 40.5 * s, height: 20.5 * s), cornerRadius: 5.5 * s),
                       with: .color(Theme.faint), lineWidth: 1.5 * s)
            ctx.fill(Path(roundedRect: CGRect(x: 4 * s, y: 4 * s, width: max(1, 34 * min(1, max(0, level))) * s, height: 14 * s), cornerRadius: 3 * s),
                     with: .color(color))
            var cap = Path()
            cap.move(to: CGPoint(x: 44.5 * s, y: 8 * s))
            cap.addLine(to: CGPoint(x: 44.5 * s, y: 14 * s))
            ctx.stroke(cap, with: .color(Theme.faint), style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
        }
        .frame(width: 46, height: 22)
        .accessibilityHidden(true)
    }
}

/// Accessory row on the desktop battery page: icon tile, name, detail, mini battery, value.
struct DeviceRow: View {
    var device: BluetoothDevice

    var body: some View {
        let low = device.level <= 0.2
        HStack(spacing: 12) {
            LineIcon(d: icon, size: 16, lineWidth: 1.4)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.well))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(device.name).lineLimit(1)
                    if low { StatusPill(text: L10n.Battery.low, fg: Theme.danger, bg: Theme.dangerBg) }
                }
                if let detail = device.detail { Text(detail).ui(12).foregroundStyle(Theme.sub).lineLimit(1) }
            }
            Spacer(minLength: 8)
            BatteryGlyph(level: device.level, fill: low ? Theme.danger : Theme.bat, rim: Theme.faint, rimOpacity: 1)
            Text(Format.percent(device.level)).ui(13, 500).foregroundStyle(low ? Theme.danger : Theme.text)
                .frame(width: 40, alignment: .trailing)
        }
        .frame(minHeight: 54)
        .accessibilityElement(children: .combine)
    }

    private var icon: String { Self.icon(device.kind) }

    static func icon(_ kind: BluetoothDevice.Kind) -> String {
        switch kind {
        case .keyboard: return Icons.keyboard
        case .mouse: return Icons.mouse
        case .trackpad: return Icons.trackpad
        case .headphones: return Icons.headphones
        case .other: return Icons.battery
        }
    }
}

struct UPSRow: View {
    var source: PowerSource

    var body: some View {
        HStack(spacing: 12) {
            LineIcon(d: Icons.ups, size: 16, lineWidth: 1.4)
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
        VStack(alignment: .leading, spacing: 16) {
            MonitorHeader(title: L10n.Module.sensors,
                          value: s.cpuAverage.map { Format.temperatureNumber($0, unit: unit) } ?? L10n.Common.dash,
                          unit: L10n.Monitor.degreeCPUAverage) {
                RangeControl(range: $range, options: [.m5, .m30, .h1, .h24], width: 256)
            }
            ChartBlock(height: 110) {
                MonitorChart(series: [ChartSeries(id: "cpu", points: monitor.history.points(.cpuTemp, range: range), color: Theme.temp)],
                             range: range, maxValue: 110, hoverText: { hover($0, unit) })
                    .accessibilityLabel(L10n.Monitor.tempChartA11y(range.title))
            }
            TitledSection(title: L10n.Sensors.temperatures) {
                VStack(spacing: 0) {
                    ForEach(s.temps) { t in
                        HStack(spacing: 12) {
                            Text(PanelText.tempName(t.group)).lineLimit(1).frame(width: 110, alignment: .leading)
                            MeterBar(fraction: t.value / 110, color: Theme.temp)
                            Text(Format.temperature(t.value, unit: unit, showUnit: true)).ui(13, 500).frame(width: 56, alignment: .trailing)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            }
            TitledSection(title: L10n.Sensors.fans) {
                if s.fans.isEmpty {
                    Panel(padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
                        Text(L10n.Sensors.fanless).foregroundStyle(Theme.sub)
                    }
                } else {
                    CellStrip(cells: s.fans.map { (Format.rpm($0.rpm), PanelText.fanName($0.id, count: s.fans.count)) })
                }
            }
            TitledSection(title: L10n.Sensors.power) {
                CellStrip(cells: [
                    (s.systemPower.map(Format.watts) ?? L10n.Common.dash, L10n.Monitor.system),
                    (s.cpuPower.map(Format.watts) ?? L10n.Common.dash, L10n.Module.cpu),
                    (s.gpuPower.map(Format.watts) ?? L10n.Common.dash, L10n.Module.gpu),
                ])
            }
        }
    }

    private func hover(_ date: Date, _ unit: TemperatureUnit) -> [String] {
        let c = monitor.history.points(.cpuTemp, range: range)
        guard let i = nearest(c, date) else { return [] }
        return [timeLabel(c[i].date, range) + "\t" + Format.temperature(c[i].value, unit: unit, showUnit: true)]
    }
}
