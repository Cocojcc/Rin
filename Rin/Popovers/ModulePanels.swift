import AppKit
import SwiftUI

/// The per-module dropdown: header, the big reading and its last minute, then the module's parts.
struct ModulePanel: View {
    let module: Module
    var quitCenter = QuitCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            if let toast = quitCenter.toast { QuitToast(toast: toast).padding(.top, 12) }
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

// MARK: - Shared pieces

/// The last minute (or the network's chosen span) in a dropdown: no scale, "−60 秒 … 现在" under it.
struct PanelChart: View {
    var kind: ConsoleChart.Kind
    var series: [ChartSeries]
    var seconds: Double = 60
    var maxValue: Double = 100
    var bottomMax: Double = 1
    var height: CGFloat = 52
    var labels: [String]? = nil
    var bands: [ClosedRange<Date>] = []

    var body: some View {
        ConsoleChart(kind: kind, series: series, span: seconds, maxValue: maxValue, bottomMax: bottomMax, height: height,
                     xLabels: labels ?? [L10n.Chart.secondsAgo(Int(seconds)), L10n.Range.now], bands: bands)
            .padding(.top, 14)
    }
}

/// Small figures two to a row (or more), 16 apart down and 24 across.
struct FigureGrid<Content: View>: View {
    var columns = 2
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .leading), count: columns), alignment: .leading, spacing: 16) {
            content
        }
    }
}

/// A one-line fact on a rule ("平均负载", "散热状态"): grey label left, the value right (36 pt).
struct PanelLine<Value: View>: View {
    var label: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 12) {
            Text(label).ui(13).foregroundStyle(Theme.sub).lineLimit(1).fixedSize()
            Spacer(minLength: 8)
            value.ui(13).lineLimit(1).fixedSize()
        }
        .frame(height: 36)
        .overlay(alignment: .top) { Hairline() }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }
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
        PanelHero(label: L10n.Monitor.totalUsage, value: Format.percentNumber(s.cpu.total), unit: "%") {
            KeyDot(text: L10n.Monitor.userShare(Format.percent(s.cpu.user)), color: Theme.accent)
            KeyDot(text: L10n.Monitor.systemShare(Format.percent(s.cpu.system)), color: Theme.faint)
        }
        PanelChart(kind: .area, series: ChartSeries.cpuStack(total: monitor.history.points(.cpu, range: .m5), system: monitor.history.points(.cpuSystem, range: .m5)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.Panel.cpuChartA11y)
        if p.showCores, !s.cpu.perCore.isEmpty {
            let split = p.splitCoreKinds && SystemInfo.efficiencyCores > 0
            PanelSection(title: L10n.Panel.cores, right: split ? PanelText.coreSplit() : L10n.Panel.coreCount(s.cpu.perCore.count)) {
                CoreStrip(cpu: split ? s.cpu : CPUSample(perCore: s.cpu.perCore), height: 30, compact: true).padding(.top, 10)
                if split {
                    let avg = PanelCoreBars.averages(s.cpu)
                    HStack {
                        Text(L10n.Panel.perfAverageValue(Format.percent(avg.p)))
                        Spacer(minLength: 8)
                        Text(L10n.Panel.effAverageValue(Format.percent(avg.e)))
                    }
                    .ui(12).foregroundStyle(Theme.sub)
                    .padding(.top, 8)
                }
            }
        }
        if p.showLoad {
            PanelLine(label: L10n.Panel.loadAverage) {
                HStack(spacing: 12) {
                    loadPair(L10n.Panel.load1, s.cpu.load.0)
                    loadPair(L10n.Panel.load5, s.cpu.load.1)
                    loadPair(L10n.Panel.load15, s.cpu.load.2)
                }
            }
        }
        if p.showProcesses {
            PanelProcessList(title: L10n.Panel.topUsage, processes: Array(s.processes.byCPU.prefix(p.processCount)), value: { Format.percentValue($0.cpu) },
                             link: .cpu, top: p.showLoad ? 10 : 18)
        }
    }

    private func loadPair(_ label: String, _ v: Double) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(Theme.sub)
            Text(Format.load(v)).fontWeight(.medium)
        }
    }
}

enum PanelCoreBars {
    static func averages(_ cpu: CPUSample) -> (p: Double, e: Double) {
        var p: [Double] = [], e: [Double] = []
        for (i, v) in cpu.perCore.enumerated() {
            if i < cpu.coreKinds.count, cpu.coreKinds[i] == .efficiency { e.append(v) } else { p.append(v) }
        }
        let avg = { (a: [Double]) in a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }
        return (avg(p), avg(e))
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
        PanelHero(label: L10n.Panel.utilization, value: Format.percentNumber(g.utilization), unit: "%") {
            Text(L10n.Monitor.partValue(L10n.Panel.vram, Format.percent(vram)))
            Text(L10n.Monitor.partValue(L10n.Panel.temperature, g.temperature.map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash))
        }
        PanelChart(kind: .area, series: ChartSeries.line(monitor.history.points(.gpu, range: .m5)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.Panel.gpuChartA11y)
        if p.showMemory || p.showFrequency || p.showVideo || p.showTempPower {
            FigureGrid {
                if p.showMemory {
                    let used = Format.parts(Format.memory(g.memoryUsed))
                    Figure(name: g.memoryLimit > 0 ? L10n.Panel.vramLimit(Format.memory(g.memoryLimit)) : L10n.Panel.vram, value: used.0, unit: L10n.Panel.unitUsed(used.1), size: 22)
                }
                if p.showFrequency {
                    Figure(name: L10n.Panel.frequency, value: g.frequencyMHz.map { String(format: "%.2f", $0 / 1000) } ?? L10n.Common.dash,
                           unit: g.frequencyMHz == nil ? nil : L10n.Monitor.ghz, size: 22)
                }
                if p.showVideo {
                    let w = Format.parts(MediaText.state(g.decodeWatts))
                    Figure(name: L10n.Monitor.videoDecode, value: w.0, unit: w.1, size: 22)
                }
                if p.showTempPower {
                    let w = Format.parts(g.power.map(Format.watts) ?? L10n.Common.dash)
                    Figure(name: L10n.Panel.power, value: w.0, unit: w.1, size: 22)
                }
            }
            .padding(.top, 20)
        }
        if p.showProcesses {
            PanelProcessList(title: L10n.Panel.topUsage, processes: Array(monitor.snapshot.processes.byGPU.prefix(p.processCount)), value: { Format.percentValue($0.gpu) },
                             link: .gpu, top: 22)
        }
    }
}

// MARK: - Memory

struct MemoryPanel: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared

    var body: some View {
        let m = monitor.snapshot.memory
        let p = settings.prefs.memory
        let _ = monitor.tick
        let pr = PanelText.pressure(m.pressure)
        PanelHeader(module: .memory, subtitle: L10n.Monitor.unifiedMemory)
        PanelHero(label: L10n.Monitor.usedLabel, value: Format.percentNumber(m.usedFraction), unit: "%") {
            Text(L10n.Monitor.usedOfTotal(Format.memory(m.used), Format.memory(m.total)))
            HStack(spacing: 4) {
                Text(L10n.Panel.pressure)
                Text(pr.0).foregroundStyle(m.pressure == .normal ? Theme.sub : pr.1)
            }
        }
        if p.showComposition {
            StackedBar(parts: MemoryParts.of(m).map { .init(label: L10n.Monitor.partValue($0.label, Format.memory(UInt64($0.bytes))), value: $0.bytes, color: $0.color,
                                                            ring: $0.label == L10n.Memory.free) }, keySize: 12)
                .padding(.top, 16)
        }
        if p.showPressure {
            PanelSection(title: L10n.Panel.pressure, right: p.showSwap ? L10n.Monitor.partValue(L10n.Memory.swap, Format.memory(m.swapUsed)) : nil, top: 20) {
                ConsoleChart(kind: .area, series: ChartSeries.line(monitor.history.points(.memoryPressure, range: .m5)),
                             span: 60, maxValue: 100, height: 40, xLabels: nil)
                    .padding(.top, 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.Panel.pressureChartA11y)
            }
        } else if p.showSwap {
            KVRow(key: L10n.Memory.swap, value: Format.memory(m.swapUsed)).padding(.top, 12)
        }
        if p.showProcesses {
            PanelProcessList(title: L10n.Panel.topUsage, processes: Array(monitor.snapshot.processes.byMemory.prefix(p.processCount)), value: { Format.memory($0.memory) },
                             link: .memory)
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
        let down = monitor.history.points(.netDown, range: seconds > 300 ? .m30 : .m5)
        let up = monitor.history.points(.netUp, range: seconds > 300 ? .m30 : .m5)
        let from = Date().addingTimeInterval(-seconds)
        let dMax = ConsoleChart.niceMax(max(down.filter { $0.date >= from }.map(\.value).max() ?? 0, 10_000) * 1.1)
        let uMax = ConsoleChart.niceMax(max(up.filter { $0.date >= from }.map(\.value).max() ?? 0, 10_000) * 1.1)
        PanelHeader(module: .network, subtitle: PanelText.interface(n))
        if n.connected {
            HStack(alignment: .top, spacing: 16) {
                speed(MenuBarText.downArrow + " " + L10n.Panel.download, n.down, p.speedUnit)
                speed(MenuBarText.upArrow + " " + L10n.Panel.upload, n.up, p.speedUnit)
            }
            .padding(.top, 20)
        } else {
            VStack(spacing: 8) {
                ZStack {
                    LineIcon(d: Icons.wifi, size: 24, viewBox: 16, lineWidth: 1.6).opacity(0.35)
                    LineIcon(d: Icons.slash, size: 24, viewBox: 16, lineWidth: 1.6)
                }
                .foregroundStyle(Theme.sub)
                Text(L10n.Panel.notConnected).ui(16, 500).foregroundStyle(Theme.sub)
                WellButton(title: L10n.Panel.networkSettings, height: 26, fontSize: 12) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") { NSWorkspace.shared.open(url) }
                    PanelController.shared.close()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .padding(.top, 20)
        }
        PanelChart(kind: .mirroredArea, series: ChartSeries.mirrored(down, Theme.accent, up, Theme.accent),
                   seconds: seconds, maxValue: dMax, bottomMax: uMax, height: 56)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.Panel.networkChartA11y)
        VStack(spacing: 0) {
            DividedRows {
                if n.connected {
                    KVRow(key: L10n.Network.localIP, value: n.localIP.isEmpty ? L10n.Common.dash : PanelText.localIP(n))
                    if !n.router.isEmpty { KVRow(key: L10n.Network.router, value: n.router) }
                    if p.showPublicIP { KVRow(key: L10n.Network.publicIP, value: monitor.publicIP ?? L10n.Common.dash) }
                } else if let last = n.lastConnected {
                    KVRow(key: L10n.Network.lastConnected, value: Format.time(last))
                }
                KVRow(key: L10n.Network.today, value: L10n.Network.downUp(Format.storage(n.todayDown), Format.storage(n.todayUp)))
            }
        }
        .padding(.top, 14)
        if p.showProcesses && n.connected {
            PanelProcessList(title: L10n.Panel.topTraffic, processes: Array(monitor.snapshot.processes.byNetwork.prefix(5)),
                             value: { MenuBarText.downArrow + " " + Format.rate($0.netDown, unit: p.speedUnit) }, secondary: { MenuBarText.upArrow + " " + Format.rate($0.netUp, unit: p.speedUnit) },
                             valueWidth: 86, link: .network, top: 16)
        }
    }

    /// Download and upload alike, in the accent.
    private func speed(_ label: String, _ v: Double, _ unit: SpeedUnit) -> some View {
        let parts = Format.rateParts(v, unit: unit)
        return VStack(alignment: .leading, spacing: 6) {
            SmallLabel(text: label)
            BigValue(value: parts.0, unit: parts.1, size: 40, color: Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
        FigureGrid(columns: 3) {
            let r = Format.rateParts(d.read), w = Format.rateParts(d.write)
            Figure(name: MenuBarText.downArrow + " " + L10n.Disk.read, value: r.0, unit: r.1, size: 28)
            Figure(name: MenuBarText.upArrow + " " + L10n.Disk.write, value: w.0, unit: w.1, size: 28)
            Figure(name: L10n.Disk.used, value: volume.map { Format.percentNumber($0.usedFraction) } ?? L10n.Common.dash, unit: volume == nil ? nil : "%", size: 28)
        }
        .padding(.top, 20)
        if p.showGraph {
            let reads = monitor.history.points(.diskRead, range: .m5), writes = monitor.history.points(.diskWrite, range: .m5)
            let from = Date().addingTimeInterval(-60)
            PanelChart(kind: .mirroredArea, series: ChartSeries.mirrored(reads, Theme.text, writes, Theme.text, lineWidth: 1.3),
                       maxValue: ConsoleChart.niceMax(max(reads.filter { $0.date >= from }.map(\.value).max() ?? 0, 1_000_000) * 1.1),
                       bottomMax: ConsoleChart.niceMax(max(writes.filter { $0.date >= from }.map(\.value).max() ?? 0, 1_000_000) * 1.1), height: 48)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.Panel.diskChartA11y)
        }
        let volumes = p.showAllDisks ? d.volumes : (volume.map { [$0] } ?? [])
        ForEach(volumes) { VolumeBlock(volume: $0, size: 28, barHeight: 4).padding(.top, 18) }
        VStack(spacing: 0) {
            DividedRows {
                KVRow(key: L10n.Disk.sinceBoot, value: L10n.Disk.readWriteTotals(Format.storage(d.totalRead), Format.storage(d.totalWritten)))
                if p.showHealth, let h = d.health {
                    KVRow(key: L10n.Panel.health, value: L10n.Panel.healthValue(Format.percent(h.lifeRemaining), h.ok ? L10n.Monitor.smartGood : L10n.Monitor.smartFailing),
                          valueColor: h.ok ? Theme.text : Theme.danger)
                }
            }
        }
        .overlay(alignment: .top) { Hairline() }
        .padding(.top, 14)
        if p.showProcesses {
            PanelProcessList(title: L10n.Panel.topDisk, processes: Array(monitor.snapshot.processes.byDisk.prefix(5)), value: { Format.rate($0.diskTotal) })
        }
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
        let unit = settings.prefs.general.temperatureUnit
        PanelHeader(module: .battery, subtitle: b.onAC ? b.adapterWatts.map { L10n.Battery.adapter($0) } : nil)
        if b.hasBattery {
            PanelHero(label: L10n.Battery.level, value: Format.percentNumber(b.level), unit: "%", color: low ? Theme.danger : Theme.accent) {
                Text(PanelText.batteryState(b))
                if b.isCharging, let m = b.minutesToFull {
                    Text(L10n.Battery.untilFull(BatteryTime.text(m))).ui(13, 500).foregroundStyle(Theme.text)
                } else if !b.onAC, let m = b.minutesToEmpty {
                    Text(L10n.Battery.remaining(BatteryTime.text(m))).ui(13, 500).foregroundStyle(Theme.text)
                }
            }
            FigureGrid {
                let watts: Double? = b.isCharging ? b.power.flatMap { $0 > 0 ? $0 : nil } : (b.onAC ? b.systemPowerIn : b.power.map(abs))
                Figure(name: b.isCharging ? L10n.Battery.chargingPower : L10n.Battery.power, value: watts.map { "\(Int($0.rounded()))" } ?? L10n.Common.dash,
                       unit: watts == nil ? nil : L10n.Common.wattUnit, size: 22)
                if p.showHealth, let h = b.health { Figure(name: L10n.Battery.health, value: Format.percentNumber(h), unit: "%", size: 22) }
                if p.showCycles, let c = b.cycles { Figure(name: L10n.Battery.cycles, value: "\(c)", unit: L10n.Monitor.ofTotal("\(b.designCycles ?? 1000)"), size: 22) }
                if p.showTemperature, let t = b.temperature ?? monitor.snapshot.sensors.value(.battery) {
                    Figure(name: L10n.Battery.temperature, value: Format.temperatureNumber(t, unit: unit), unit: Format.temperatureSymbol(unit), size: 22)
                }
            }
            .padding(.top, 20)
            PanelSection(title: L10n.Battery.level, right: L10n.Range.last24h, top: 22) {
                ConsoleChart(kind: .area, series: ChartSeries.line(monitor.history.points(.battery, range: .h24), low ? Theme.danger : Theme.accent),
                             span: TimeRange.h24.seconds, maxValue: 100, height: 56, xLabels: [L10n.Range.ago24h, L10n.Range.ago12h, L10n.Range.now],
                             bands: ChargingBands.of(.h24))
                    .padding(.top, 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.Panel.batteryChartA11y)
            }
        }
        // Bluetooth accessories have their own module; a UPS stays with the battery.
        if !b.ups.isEmpty {
            PanelSection(title: L10n.Battery.ups) {
                VStack(spacing: 0) {
                    ForEach(b.ups) { source in
                        MeterRow(name: source.name, fraction: source.level, value: Format.percent(source.level),
                                 color: source.level <= 0.2 ? Theme.danger : Theme.mid, nameWidth: 132, valueWidth: 44)
                    }
                }
            }
        }
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
        let deg = { (c: Double?) in c.map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash }
        PanelHeader(module: .sensors, subtitle: s.fans.isEmpty ? L10n.Panel.passiveCooling : L10n.Panel.fanCount(s.fans.count))
        ShareRow(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SmallLabel(text: L10n.Sensors.choice(p.sensor))
                BigValue(value: deg(MenuBarText.sensorValue(s, p.sensor)), size: 52, color: Theme.accent)
            }
            .share(1.5)
            Figure(name: L10n.Sensors.gpu, value: deg(s.value(.gpu)), size: 28)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .share(1)
            Figure(name: L10n.Sensors.ssd, value: deg(s.value(.ssd)), size: 28)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .share(1)
        }
        .padding(.top, 20)
        .accessibilityElement(children: .combine)
        if p.showThermal {
            PanelLine(label: L10n.Sensors.thermalState) {
                Text(PanelText.thermal(s.thermal).0)
                    .foregroundStyle(s.thermal == .nominal ? Theme.text : ThermalText.color(s.thermal))
            }
        }
        if p.showAllTemps, !s.temps.isEmpty {
            PanelSection(title: L10n.Sensors.temperatures, top: 10) {
                VStack(spacing: 0) {
                    ForEach(s.temps) { t in
                        MeterRow(name: PanelText.tempName(t.group), fraction: t.value / 100, value: Format.temperature(t.value, unit: unit, showUnit: true),
                                 color: t.value >= 90 ? Theme.danger : t.value >= 70 ? Theme.warn : Theme.mid)
                    }
                }
            }
        }
        if p.showFans {
            if s.hasFans {
                PanelSection(title: L10n.Sensors.fans, right: s.fans.first.map { L10n.Sensors.maxRPM(Int($0.max)) }, top: 16) {
                    VStack(spacing: 0) {
                        ForEach(s.fans) { f in
                            MeterRow(name: PanelText.fanName(f.id, count: s.fans.count), fraction: f.max > f.min ? (f.rpm - f.min) / (f.max - f.min) : 0,
                                     value: Format.rpm(f.rpm), valueWidth: 72)
                        }
                    }
                }
            } else {
                PanelSection(title: L10n.Sensors.fans, top: 16) { KVRow(key: L10n.Sensors.fanless, value: "") }
            }
        }
        if p.showPower, s.systemPower != nil || s.cpuPower != nil || s.gpuPower != nil {
            let cpu = s.cpuPower ?? 0, gpu = s.gpuPower ?? 0
            let other = max(0, (s.systemPower ?? cpu + gpu) - cpu - gpu)
            PanelSection(title: L10n.Sensors.power, right: s.systemPower.map { L10n.Processes.wholeMac(Format.watts($0)) }, top: 16) {
                StackedBar(parts: [.init(label: L10n.Monitor.partValue(L10n.Module.cpu, s.cpuPower.map(Format.watts) ?? L10n.Common.dash), value: cpu, color: Theme.accent),
                                   .init(label: L10n.Monitor.partValue(L10n.Module.gpu, s.gpuPower.map(Format.watts) ?? L10n.Common.dash), value: gpu, color: Theme.mid),
                                   .init(label: "", value: other, color: Theme.track)], height: 4, keySize: 12)
                    .padding(.top, 8)
            }
        }
    }
}
