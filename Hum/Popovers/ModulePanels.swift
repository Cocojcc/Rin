import AppKit
import SwiftUI

/// The per-module dropdown: header, hero readouts, chart, sections, quit confirmation.
struct ModulePanel: View {
    let module: Module
    var quitCenter = QuitCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch module {
            case .cpu: CPUPanel()
            case .gpu: GPUPanel()
            case .memory: MemoryPanel()
            case .network: NetworkPanel()
            case .disk: DiskPanel()
            case .battery: BatteryPanel()
            case .bluetooth: BluetoothPanel()
            case .sensors: SensorsPanel()
            }
            if let toast = quitCenter.toast { QuitToast(toast: toast) }
        }
    }
}

// MARK: - Shared text

enum PanelText {
    static func cpuSubtitle() -> String {
        L10n.Panel.chipCores(SystemInfo.chipName, SystemInfo.coreCount)
    }

    static func coreSplit() -> String? {
        guard SystemInfo.efficiencyCores > 0 else { return nil }
        return L10n.Panel.coreSplit(SystemInfo.performanceCores, SystemInfo.efficiencyCores)
    }

    /// The Mac's address, with the adapter it's on when a VPN carries the traffic
    /// ("192.168.3.5（Wi-Fi）").
    static func localIP(_ n: NetworkSample) -> String {
        n.adapterKind.map { L10n.Network.ipVia(n.localIP, kindName($0)) } ?? n.localIP
    }

    static func pressure(_ p: MemoryPressure) -> (String, Color, Color) {
        switch p {
        case .normal: return (L10n.Panel.pressureNormal, Theme.ok, Theme.okBg)
        case .warning: return (L10n.Panel.pressureWarning, Theme.warn, Theme.warnBg)
        case .critical: return (L10n.Panel.pressureCritical, Theme.danger, Theme.dangerBg)
        }
    }

    static func thermal(_ t: ThermalLevel) -> (String, Color, Color) {
        switch t {
        case .nominal: return (L10n.Panel.thermalNominal, Theme.ok, Theme.okBg)
        case .fair: return (L10n.Panel.thermalFair, Theme.warn, Theme.warnBg)
        case .serious: return (L10n.Panel.thermalSerious, Theme.danger, Theme.dangerBg)
        case .critical: return (L10n.Panel.thermalCritical, Theme.danger, Theme.dangerBg)
        }
    }

    static func interface(_ n: NetworkSample) -> String {
        guard n.connected else { return L10n.Panel.notConnectedKind(kindName(n.kind)) }
        return L10n.Settings.interfaceOption(kindName(n.kind), n.interface)
    }

    static func kindName(_ k: InterfaceKind) -> String {
        switch k {
        case .wifi: return L10n.Panel.wifi
        case .ethernet: return L10n.Panel.ethernet
        case .vpn: return L10n.Panel.vpn
        case .other: return L10n.Panel.network
        }
    }

    static func batteryStatus(_ b: BatterySample) -> String {
        if b.isCharging {
            if let m = b.minutesToFull { return L10n.Panel.chargingUntilFull(Format.clockDuration(minutes: m)) }
            return L10n.Battery.charging
        }
        if b.onAC { return b.isCharged || b.level >= 0.99 ? L10n.Battery.charged : L10n.Battery.onAC }
        if let m = b.minutesToEmpty { return L10n.Panel.onBatteryRemaining(Format.clockDuration(minutes: m)) }
        return L10n.Battery.onBattery
    }

    static func batteryState(_ b: BatterySample) -> String {
        if b.isCharging { return L10n.Battery.charging }
        if b.onAC { return b.isCharged || b.level >= 0.99 ? L10n.Battery.charged : L10n.Battery.onAC }
        return L10n.Battery.onBattery
    }

    static func tempName(_ g: TempGroup) -> String {
        switch g {
        case .cpuPerformance: return L10n.Sensors.cpuPerformance
        case .cpuEfficiency: return L10n.Sensors.cpuEfficiency
        case .gpu: return L10n.Sensors.gpu
        case .ssd: return L10n.Sensors.ssd
        case .battery: return L10n.Sensors.battery
        case .wireless: return L10n.Sensors.wireless
        }
    }

    static func fanName(_ i: Int, count: Int) -> String {
        L10n.Sensors.fanNumbered(i + 1)
    }
}

/// Bold value followed by a grey word, as one line ("2.8 GB 已用", "性能核 平均 42%").
private func valueThenLabel(_ value: String, _ label: String, size: CGFloat = 15) -> Text {
    Text(value).font(Fonts.ui(size, 500)).foregroundColor(Theme.text)
        + Text(verbatim: " ")
        + Text(label).font(Fonts.ui(12)).foregroundColor(Theme.sub)
}

private func labelThenValue(_ label: String, _ value: String) -> Text {
    Text(label).font(Fonts.ui(12)).foregroundColor(Theme.sub)
        + Text(verbatim: " ")
        + Text(value).font(Fonts.ui(12, 500)).foregroundColor(Theme.text)
}

// MARK: - CPU

struct CPUPanel: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared

    var body: some View {
        let s = monitor.snapshot
        let p = settings.prefs.cpu
        let _ = monitor.tick
        PanelHeader(module: .cpu, subtitle: PanelText.cpuSubtitle())
        HeroRow {
            HeroItem(label: L10n.Panel.user) {
                ValueRing(fraction: s.cpu.user, color: Theme.cpu, value: Format.percent(s.cpu.user), large: false)
            }
        } center: {
            HeroItem(label: L10n.Monitor.totalUsage) {
                ValueRing(segments: [Ring.Segment(fraction: s.cpu.user, color: Theme.cpu), Ring.Segment(fraction: s.cpu.system, color: Theme.sys)],
                          value: Format.percent(s.cpu.total))
            }
        } trailing: {
            HeroItem(label: L10n.Panel.system) {
                ValueRing(fraction: s.cpu.system, color: Theme.sys, value: Format.percent(s.cpu.system), large: false)
            }
        }
        Well {
            WellChart(legend: [(Theme.sys, L10n.Panel.system), (Theme.cpu, L10n.Panel.user)], right: L10n.Range.last60s) {
                MiniChart(series: [
                    .init(values: monitor.history.latest(.cpu, seconds: 60).map { $0 / 100 }, color: Theme.cpu, fill: 0.16, lineWidth: 2),
                    .init(values: monitor.history.latest(.cpuSystem, seconds: 60).map { $0 / 100 }, color: Theme.sys, fill: 0.24, lineWidth: 1.5),
                ])
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.Panel.cpuChartA11y)
            }
        }
        if p.showCores, !s.cpu.perCore.isEmpty {
            let split = p.splitCoreKinds && SystemInfo.efficiencyCores > 0
            PanelSection(title: L10n.Panel.cores, right: split ? PanelText.coreSplit() : L10n.Panel.coreCount(s.cpu.perCore.count)) {
                Well(padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)) {
                    CoreBars(cpu: s.cpu, split: split, height: 28)
                    if split {
                        let avg = CoreBars.averages(s.cpu)
                        HStack {
                            labelThenValue(L10n.Panel.perfAverage, Format.percent(avg.p))
                            Spacer(minLength: 8)
                            labelThenValue(L10n.Panel.effAverage, Format.percent(avg.e))
                        }
                        .padding(.top, 10)
                    }
                }
            }
        }
        if p.showLoad {
            PanelSection(title: L10n.Panel.loadAverage) {
                CellStrip(cells: [(Format.load(s.cpu.load.0), L10n.Panel.load1),
                                  (Format.load(s.cpu.load.1), L10n.Panel.load5),
                                  (Format.load(s.cpu.load.2), L10n.Panel.load15)],
                          fill: Theme.well, radius: 12, compact: true)
            }
        }
        if p.showProcesses {
            PanelProcessList(title: L10n.Panel.topUsage, processes: Array(s.processes.byCPU.prefix(p.processCount)), metric: .cpu, color: Theme.cpu, link: .cpu)
        }
    }
}

// MARK: - GPU

struct GPUPanel: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared

    var body: some View {
        let g = monitor.snapshot.gpu
        let p = settings.prefs.gpu
        let unit = settings.prefs.general.temperatureUnit
        let _ = monitor.tick
        let vram = g.memoryLimit > 0 ? Double(g.memoryUsed) / Double(g.memoryLimit) : 0
        PanelHeader(module: .gpu, subtitle: L10n.Panel.chipCores(g.model, g.cores))
        HeroRow {
            HeroItem(label: L10n.Panel.vram) {
                ValueRing(fraction: vram, color: Theme.gpu, value: Format.percent(vram), large: false)
            }
        } center: {
            HeroItem(label: L10n.Panel.utilization) {
                ValueRing(fraction: g.utilization, color: Theme.gpu, value: Format.percent(g.utilization))
            }
        } trailing: {
            HeroItem(label: L10n.Panel.temperature) {
                ValueRing(fraction: (g.temperature ?? 0) / 100, color: Theme.temp,
                          value: g.temperature.map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash, large: false)
            }
        }
        Well {
            WellChart(legend: [(Theme.gpu, L10n.Panel.utilization)], right: L10n.Range.last60s) {
                MiniChart(series: [.init(values: monitor.history.latest(.gpu, seconds: 60).map { $0 / 100 }, color: Theme.gpu)])
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.Panel.gpuChartA11y)
            }
        }
        let stats = gpuStats(g, p, unit)
        if p.showMemory {
            PanelSection(title: L10n.Panel.vram, right: g.memoryLimit > 0 ? L10n.Panel.limit(Format.memory(g.memoryLimit)) : nil) {
                Well {
                    VStack(alignment: .leading, spacing: 0) {
                        valueThenLabel(Format.memory(g.memoryUsed), L10n.Panel.used)
                        MeterBar(fraction: vram, color: Theme.gpu).padding(.top, 10)
                    }
                    .padding(12)
                    if !stats.isEmpty {
                        CellStrip(cells: stats, fill: .clear, radius: 0, compact: true)
                            .overlay(alignment: .top) { Hairline() }
                    }
                }
            }
        } else if !stats.isEmpty {
            CellStrip(cells: stats, fill: Theme.well, radius: 12, compact: true)
        }
        if p.showProcesses {
            PanelProcessList(title: L10n.Panel.topUsage, processes: Array(monitor.snapshot.processes.byGPU.prefix(p.processCount)), metric: .gpu, color: Theme.gpu)
        }
    }

    private func gpuStats(_ g: GPUSample, _ p: GPUPrefs, _ unit: TemperatureUnit) -> [(String, String)] {
        var out: [(String, String)] = []
        if p.showFrequency, let f = g.frequencyMHz { out.append((Format.frequency(f), L10n.Panel.frequency)) }
        if p.showVideo { out.append((MediaText.state(g.decodeWatts), L10n.Monitor.videoDecode)) }
        if p.showTempPower, let w = g.power { out.append((Format.watts(w), L10n.Panel.power)) }
        return out
    }
}

// MARK: - Memory

/// Half-circle pressure dial: green / yellow / red bands, a needle at the current level.
struct PressureGauge: View {
    var level: Double
    var pressure: MemoryPressure

    var body: some View {
        let pr = PanelText.pressure(pressure)
        ZStack(alignment: .bottom) {
            Canvas { ctx, _ in
                let center = CGPoint(x: 44, y: 56)
                func band(_ from: Double, _ to: Double, _ color: Color) {
                    var p = Path()
                    p.addArc(center: center, radius: 38, startAngle: .degrees(180 + 180 * from), endAngle: .degrees(180 + 180 * to), clockwise: false)
                    ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
                band(0, 0.48, Theme.ok)
                band(0.52, 0.78, Theme.sys)
                band(0.82, 1, Theme.temp)
                let angle = Angle.degrees(180 + 180 * min(1, max(0, level))).radians
                var needle = Path()
                needle.move(to: center)
                needle.addLine(to: CGPoint(x: center.x + 26 * cos(angle), y: center.y + 26 * sin(angle)))
                ctx.stroke(needle, with: .color(Theme.text), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(Theme.text))
            }
            Text(pr.0).ui(13, 500).foregroundStyle(pr.1).padding(.bottom, 4)
        }
        .frame(width: 88, height: 84)
    }
}

struct MemoryPanel: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared

    var body: some View {
        let m = monitor.snapshot.memory
        let p = settings.prefs.memory
        let _ = monitor.tick
        let total = max(Double(m.total), 1)
        let pr = PanelText.pressure(m.pressure)
        PanelHeader(module: .memory, subtitle: L10n.Monitor.unifiedMemory)
        HeroPair {
            HeroItem(label: L10n.Panel.pressure) {
                PressureGauge(level: m.pressureLevel, pressure: m.pressure)
            }
        } trailing: {
            HeroItem(label: L10n.Panel.memoryUsedOf(Format.memory(m.used), Format.memory(m.total))) {
                ValueRing(segments: [Ring.Segment(fraction: Double(m.app) / total, color: Theme.mem),
                                     Ring.Segment(fraction: Double(m.wired) / total, color: Theme.mem, opacity: 0.6),
                                     Ring.Segment(fraction: Double(m.compressed) / total, color: Theme.mem, opacity: 0.35)],
                          value: Format.percent(m.usedFraction))
            }
        }
        if p.showComposition {
            PanelSection(title: L10n.Panel.composition) {
                Well(padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)) {
                    MemoryComposition(m: m)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                        MemoryLegend(color: Theme.mem, label: L10n.Monitor.appMemory, bytes: m.app)
                        MemoryLegend(color: Theme.mem.opacity(0.6), label: L10n.Memory.wired, bytes: m.wired)
                        MemoryLegend(color: Theme.mem.opacity(0.35), label: L10n.Monitor.compressed, bytes: m.compressed)
                        MemoryLegend(color: Theme.cache, label: L10n.Monitor.cache, bytes: m.cached)
                        MemoryLegend(color: Theme.track, label: L10n.Memory.free, bytes: m.free, ring: true)
                    }
                    .padding(.top, 12)
                }
            }
        }
        if p.showPressure {
            PanelSection(title: L10n.Panel.pressure) {
                Well {
                    MiniChart(series: [.init(values: monitor.history.latest(.memoryPressure, seconds: 60).map { $0 / 100 }, color: pr.1)], gridLines: 2)
                        .frame(height: 36)
                        .padding(.top, 10)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L10n.Panel.pressureChartA11y)
                    if p.showSwap {
                        KVRow(key: L10n.Memory.swap, value: Format.memory(m.swapUsed))
                            .overlay(alignment: .top) { Hairline() }
                    }
                }
            }
        } else if p.showSwap {
            Well { KVRow(key: L10n.Memory.swap, value: Format.memory(m.swapUsed)) }
        }
        if p.showProcesses {
            PanelProcessList(title: L10n.Panel.topUsage, processes: Array(monitor.snapshot.processes.byMemory.prefix(p.processCount)), metric: .memory, color: Theme.mem, link: .memory)
        }
    }
}

// MARK: - Network

struct NetworkPanel: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared

    var body: some View {
        let n = monitor.snapshot.network
        let p = settings.prefs.network
        let seconds = Double(p.graphSeconds)
        let _ = monitor.tick
        let down = monitor.history.latest(.netDown, seconds: seconds)
        let up = monitor.history.latest(.netUp, seconds: seconds)
        let peak = max(down.max() ?? 0, up.max() ?? 0, 10_000) * 1.1
        PanelHeader(module: .network, subtitle: PanelText.interface(n))
        if n.connected {
            HeroPair {
                HeroItem(label: L10n.Panel.download, dot: Theme.down, height: 44) { speed(MenuBarText.downArrow, n.down, p.speedUnit) }
            } trailing: {
                HeroItem(label: L10n.Panel.upload, dot: Theme.up, height: 44) { speed(MenuBarText.upArrow, n.up, p.speedUnit) }
            }
        } else {
            VStack(spacing: 8) {
                ZStack {
                    LineIcon(d: Icons.wifi, size: 24, viewBox: 16, lineWidth: 1.6).opacity(0.35)
                    LineIcon(d: Icons.slash, size: 24, viewBox: 16, lineWidth: 1.6)
                }
                .foregroundStyle(Theme.sub)
                Text(L10n.Panel.notConnected).ui(15, 500).foregroundStyle(Theme.sub)
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") { NSWorkspace.shared.open(url) }
                    PanelController.shared.close()
                } label: {
                    Text(L10n.Panel.networkSettings).ui(12)
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised).raisedShadow())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .padding(.top, 2)
        }
        Well {
            WellChart(legend: [(Theme.down, L10n.Panel.download), (Theme.up, L10n.Panel.upload)], right: L10n.Range.lastSeconds(p.graphSeconds)) {
                MiniChart(series: [
                    .init(values: down.map { $0 / peak }, color: Theme.down, fill: n.connected ? 0.13 : 0.1),
                    .init(values: up.map { $0 / peak }, color: Theme.up, fill: 0, lineWidth: 1.25),
                ], minCount: Int(seconds / max(settings.prefs.refresh(.network), 1)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.Panel.networkChartA11y)
            }
        }
        Well {
            DividedRows {
                if n.connected {
                    KVRow(key: L10n.Network.localIP, value: n.localIP.isEmpty ? L10n.Common.dash : PanelText.localIP(n))
                    if !n.router.isEmpty { KVRow(key: L10n.Network.router, value: n.router) }
                    if p.showPublicIP { KVRow(key: L10n.Network.publicIP, value: monitor.publicIP ?? L10n.Common.dash) }
                    if p.showLatency { KVRow(key: L10n.Monitor.latency, value: n.latencyMS.map { L10n.Monitor.milliseconds(Int($0.rounded())) } ?? L10n.Common.dash) }
                } else if let last = n.lastConnected {
                    KVRow(key: L10n.Network.lastConnected, value: Format.time(last))
                }
                KVRow(key: L10n.Network.today, value: L10n.Network.downUp(Format.storage(n.todayDown), Format.storage(n.todayUp)))
            }
        }
        if p.showProcesses && n.connected {
            PanelSection(title: L10n.Panel.topTraffic) {
                TrafficList(processes: Array(monitor.snapshot.processes.byNetwork.prefix(5)), unit: p.speedUnit)
            }
        }
    }

    private func speed(_ arrow: String, _ v: Double, _ unit: SpeedUnit) -> some View {
        let parts = Format.rateParts(v, unit: unit)
        return BigReadout(value: [arrow, parts.0].joined(separator: " "), unit: parts.1)
    }
}

// MARK: - Disk

struct DiskPanel: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared

    var body: some View {
        let d = monitor.snapshot.disk
        let p = settings.prefs.disk
        let volume = MenuBarText.volume(d, p.volume)
        let _ = monitor.tick
        PanelHeader(module: .disk, subtitle: volume?.name)
        HeroRow {
            HeroItem(label: L10n.Disk.read, dot: Theme.read) { rate(d.read) }
        } center: {
            HeroItem(label: L10n.Disk.used) {
                ValueRing(fraction: volume?.usedFraction ?? 0, color: Theme.disk, value: volume.map { Format.percent($0.usedFraction) } ?? L10n.Common.dash)
            }
        } trailing: {
            HeroItem(label: L10n.Disk.write, dot: Theme.write) { rate(d.write) }
        }
        let volumes = p.showAllDisks ? d.volumes : (volume.map { [$0] } ?? [])
        if !volumes.isEmpty {
            Well {
                DividedRows {
                    ForEach(volumes) { VolumeBlock(volume: $0) }
                }
            }
        }
        if p.showGraph {
            let read = monitor.history.latest(.diskRead, seconds: 60)
            let write = monitor.history.latest(.diskWrite, seconds: 60)
            let peak = max(read.max() ?? 0, write.max() ?? 0, 1_000_000) * 1.1
            Well {
                WellChart(legend: [(Theme.read, L10n.Disk.read), (Theme.write, L10n.Disk.write)], right: L10n.Range.last60s) {
                    MiniChart(series: [
                        .init(values: read.map { $0 / peak }, color: Theme.read),
                        .init(values: write.map { $0 / peak }, color: Theme.write, fill: 0, lineWidth: 1.25),
                    ])
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.Panel.diskChartA11y)
                }
            }
        }
        Well {
            DividedRows {
                KVRow(key: L10n.Disk.sinceBoot, value: L10n.Disk.readWriteTotals(Format.storage(d.totalRead), Format.storage(d.totalWritten)))
                if p.showHealth, let h = d.health {
                    KVRow(key: L10n.Panel.health, value: L10n.Panel.healthValue(Format.percent(h.lifeRemaining), h.ok ? L10n.Monitor.smartGood : L10n.Monitor.smartFailing),
                          valueColor: h.ok ? Theme.ok : Theme.danger)
                }
            }
        }
        if p.showProcesses {
            PanelProcessList(title: L10n.Panel.topDisk, processes: Array(monitor.snapshot.processes.byDisk.prefix(5)), metric: .disk, color: Theme.disk,
                             nameWidth: 84, valueWidth: 68)
        }
    }

    private func rate(_ v: Double) -> some View {
        let parts = Format.rateParts(v)
        return BigReadout(value: parts.0, unit: parts.1)
    }
}

/// A volume in the disk dropdown: name, free space, usage bar, used of total.
struct VolumeBlock: View {
    var volume: Volume

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(volume.name).ui(13, 500).lineLimit(1)
                Text(volume.isInternal ? L10n.Disk.internalDrive : L10n.Disk.external).ui(12).foregroundStyle(Theme.sub)
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.raised))
                if volume.isEjectable && !volume.isRoot { EjectButton(volume: volume, size: 24) }
                Spacer(minLength: 4)
                Text(L10n.Disk.available(Format.storage(volume.available))).foregroundStyle(Theme.sub).lineLimit(1)
            }
            .frame(height: 20)
            StackedBar(parts: [(Double(max(0, volume.used - volume.purgeable)), Theme.disk), (Double(volume.purgeable), Theme.disk.opacity(0.4)),
                               (Double(volume.available), Theme.track)], height: 3)
                .padding(.top, 8)
            Text(volume.purgeable > 0
                 ? L10n.Panel.volumeUsedPurgeable(Format.storage(volume.used), Format.storage(volume.purgeable), Format.storage(volume.total))
                 : L10n.Disk.usedOf(Format.storage(volume.used), Format.storage(volume.total)))
                .ui(12).foregroundStyle(Theme.sub).lineLimit(1).padding(.top, 6)
        }
        .padding(12)
    }
}

// MARK: - Battery

struct BatteryPanel: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared

    var body: some View {
        let b = monitor.snapshot.battery
        let p = settings.prefs.battery
        let _ = monitor.tick
        let low = b.level <= 0.2 && !b.onAC
        PanelHeader(module: .battery, subtitle: b.onAC ? b.adapterWatts.map { L10n.Battery.adapter($0) } : nil)
        if b.hasBattery {
            HeroRow {
                timeItem(b)
            } center: {
                HeroItem(label: PanelText.batteryState(b)) {
                    VStack(spacing: 6) {
                        LargeBattery(level: b.level, charging: b.isCharging, color: low ? Theme.danger : Theme.bat).frame(width: 80, height: 37)
                        Text(Format.percent(b.level)).ui(20, 500).kerning(-0.4)
                    }
                }
            } trailing: {
                powerItem(b)
            }
            let cells = batteryCells(b, p)
            if !cells.isEmpty {
                CellStrip(cells: cells, fill: Theme.well, radius: 12, compact: true)
            }
            PanelSection(title: L10n.Battery.level, right: L10n.Range.last24h) {
                Well {
                    WellChart(labels: [L10n.Range.ago24h, L10n.Range.ago12h, L10n.Range.now]) {
                        MonitorChart(series: [ChartSeries(id: "battery", points: monitor.history.points(.battery, range: .h24), color: Theme.bat, lineWidth: 1.5)],
                                     range: .h24, maxValue: 100, bands: ChargingBands.of(.h24))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(L10n.Panel.batteryChartA11y)
                    }
                }
            }
        }
        // Bluetooth accessories have their own module; a UPS stays with the battery.
        if !b.ups.isEmpty {
            PanelSection(title: L10n.Battery.ups) {
                Well(padding: EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)) {
                    DividedRows {
                        ForEach(b.ups) { source in
                            PanelDeviceRow(icon: Icons.ups, name: source.name,
                                           detail: source.onAC ? (source.minutesLeft.map { L10n.Battery.upsDetail($0) } ?? L10n.Battery.upsOnAC) : L10n.Battery.onBattery,
                                           level: source.level)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func timeItem(_ b: BatterySample) -> some View {
        if b.isCharging {
            HeroItem(label: L10n.Panel.untilFullLabel) {
                BigReadout(value: b.minutesToFull.map { BatteryTime.text($0) } ?? L10n.Common.dash)
            }
        } else {
            HeroItem(label: L10n.Panel.timeLeftLabel) {
                BigReadout(value: b.onAC ? L10n.Common.dash : (b.minutesToEmpty.map { BatteryTime.text($0) } ?? L10n.Common.dash))
            }
        }
    }

    @ViewBuilder private func powerItem(_ b: BatterySample) -> some View {
        let watts: Double? = b.isCharging ? b.power.flatMap { $0 > 0 ? $0 : nil } : (b.onAC ? b.systemPowerIn : b.power.map(abs))
        HeroItem(label: b.isCharging ? L10n.Battery.chargingPower : L10n.Battery.power) {
            BigReadout(value: watts.map { "\(Int($0.rounded()))" } ?? L10n.Common.dash, unit: watts == nil ? "" : L10n.Common.wattUnit)
        }
    }

    private func batteryCells(_ b: BatterySample, _ p: BatteryPrefs) -> [(String, String)] {
        var out: [(String, String)] = []
        if p.showHealth, let h = b.health { out.append((Format.percent(h), L10n.Battery.health)) }
        if p.showCycles, let c = b.cycles { out.append(("\(c)" + Format.marker + L10n.Monitor.cyclesLimit(b.designCycles ?? 1000), L10n.Battery.cycles)) }
        if p.showTemperature, let t = b.temperature ?? monitor.snapshot.sensors.value(.battery) {
            out.append((Format.temperature(t, unit: settings.prefs.general.temperatureUnit, showUnit: true), L10n.Battery.temperature))
        }
        return out
    }
}

/// Bluetooth device or UPS in the battery dropdown (40 pt).
struct PanelDeviceRow: View {
    var icon: String
    var name: String
    var detail: String?
    var level: Double

    var body: some View {
        let low = level <= 0.2
        HStack(spacing: 10) {
            LineIcon(d: icon, size: 16, lineWidth: 1.4).foregroundStyle(Theme.sub)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(name).lineLimit(1)
                    if low { StatusPill(text: L10n.Battery.low, fg: Theme.danger, bg: Theme.dangerBg, fontSize: 12, height: 18, radius: 5) }
                }
                if let detail { Text(detail).ui(12).foregroundStyle(Theme.sub).lineLimit(1) }
            }
            Spacer(minLength: 4)
            BatteryGlyph(level: level, fill: low ? Theme.danger : Theme.bat, rim: Theme.faint, rimOpacity: 1)
            Text(Format.percent(level)).ui(13, 500).foregroundStyle(low ? Theme.danger : Theme.text)
                .frame(width: 40, alignment: .trailing)
        }
        .frame(minHeight: 40)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sensors

struct SensorsPanel: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared

    var body: some View {
        let s = monitor.snapshot.sensors
        let p = settings.prefs.sensors
        let unit = settings.prefs.general.temperatureUnit
        let _ = monitor.tick
        PanelHeader(module: .sensors, subtitle: s.fans.isEmpty ? L10n.Panel.passiveCooling : L10n.Panel.fanCount(s.fans.count))
        HeroRow {
            HeroItem(label: L10n.Sensors.gpu) { tempRing(s.value(.gpu), unit, large: false) }
        } center: {
            HeroItem(label: L10n.Sensors.choice(p.sensor)) { tempRing(MenuBarText.sensorValue(s, p.sensor), unit, large: true) }
        } trailing: {
            HeroItem(label: L10n.Sensors.ssd) { tempRing(s.value(.ssd), unit, large: false) }
        }
        if p.showThermal {
            let th = PanelText.thermal(s.thermal)
            Well(padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.Sensors.thermalState).foregroundStyle(Theme.sub)
                    Spacer(minLength: 8)
                    Text(th.0).fontWeight(.medium).foregroundStyle(th.1).lineLimit(1)
                }
                LevelSegments(level: s.thermal.rawValue, color: th.1, height: 3, gap: 3).padding(.top, 10)
            }
            .accessibilityElement(children: .combine)
        }
        if p.showAllTemps, !s.temps.isEmpty {
            PanelSection(title: L10n.Sensors.temperatures) {
                Well(padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)) {
                    ForEach(s.temps) { t in
                        HStack(spacing: 10) {
                            Text(PanelText.tempName(t.group)).lineLimit(1).frame(width: 84, alignment: .leading)
                            ZoneTrack(zones: [(50, Theme.ok), (20, Theme.sys), (10, Theme.temp)], position: (t.value - 20) / 80,
                                      knob: TempZone.color(t.value), zoneOpacity: 0.3)
                            Text(Format.temperature(t.value, unit: unit, showUnit: true)).ui(13, 500).lineLimit(1).frame(width: 48, alignment: .trailing)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        if p.showFans {
            if s.hasFans {
                PanelSection(title: L10n.Sensors.fans, right: s.fans.first.map { L10n.Sensors.maxRPM(Int($0.max)) }) {
                    Well(padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)) {
                        ForEach(s.fans) { f in
                            MeterRow(name: PanelText.fanName(f.id, count: s.fans.count), fraction: f.max > 0 ? f.rpm / f.max : 0,
                                     value: Format.rpm(f.rpm), color: Theme.sub)
                        }
                    }
                }
            } else {
                PanelSection(title: L10n.Sensors.fans) {
                    Well { KVRow(key: L10n.Sensors.fanless, value: "") }
                }
            }
        }
        if p.showPower, s.systemPower != nil || s.cpuPower != nil || s.gpuPower != nil {
            CellStrip(cells: [(s.systemPower.map(Format.watts) ?? L10n.Common.dash, L10n.Sensors.systemPower),
                              (s.cpuPower.map(Format.watts) ?? L10n.Common.dash, L10n.Module.cpu),
                              (s.gpuPower.map(Format.watts) ?? L10n.Common.dash, L10n.Module.gpu)],
                      fill: Theme.well, radius: 12, compact: true)
        }
    }

    private func tempRing(_ celsius: Double?, _ unit: TemperatureUnit, large: Bool) -> some View {
        ValueRing(fraction: (celsius ?? 0) / 100, color: Theme.temp,
                  value: celsius.map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash, large: large)
    }
}
