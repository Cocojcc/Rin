import AppKit
import SwiftUI

/// The per-module dropdown: header, the big reading, then the module's parts.
struct ModulePanel: View {
    let module: Module
    var quitCenter = QuitCenter.shared
    var monitor = Monitor.shared

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

    /// One fan needs no number.
    static func fanName(_ i: Int, count: Int) -> String {
        count > 1 ? L10n.Sensors.fanNumbered(i + 1) : L10n.Overview.fan
    }
}

// MARK: - Shared pieces

/// A dropdown's lead: the reading and, when there is one, a line under it, standing on a rule.
struct PanelStand<Reading: View, Foot: View>: View {
    @ViewBuilder var reading: Reading
    @ViewBuilder var foot: Foot

    var body: some View {
        Stand(top: 12) {
            VStack(alignment: .leading, spacing: 8) {
                reading
                if Foot.self != EmptyView.self {
                    HStack(spacing: 12) { foot }.ui(13).foregroundStyle(Theme.sub).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

extension PanelStand where Foot == EmptyView {
    init(@ViewBuilder reading: () -> Reading) { self.init(reading: reading, foot: { EmptyView() }) }
}

/// The last minute (or the network's chosen span) in a dropdown, edge to edge.
struct PanelChart: View {
    var kind: ConsoleChart.Kind
    var series: [ChartSeries]
    var seconds: Double = 60
    var maxGap: Double? = nil
    var maxValue: Double = 100
    var bottomMax: Double = 1
    var height: CGFloat = 60
    var top: CGFloat = 8
    var bands: [ClosedRange<Date>] = []

    var body: some View {
        ConsoleChart(kind: kind, series: series, span: seconds, maxGap: maxGap, maxValue: maxValue, bottomMax: bottomMax, height: height, bands: bands)
            .padding(.horizontal, -20)
            .padding(.top, top)
    }
}

/// Small figures in a grid: two to a row, 16 apart down and 24 across, or three, 12 across.
struct FigureGrid<Content: View>: View {
    var columns = 2
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: columns > 2 ? 12 : 24, alignment: .leading), count: columns), alignment: .leading, spacing: 16) {
            content
        }
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
        PanelHeader(module: .cpu)
        PanelStand {
            BigValue(value: Format.percentNumber(s.cpu.total), unit: "%", size: BigValue.panelLead)
        } foot: {
            KeyDot(text: L10n.Monitor.userShare(Format.percent(s.cpu.user)), color: Theme.color(for: .cpu))
            KeyDot(text: L10n.Monitor.systemShare(Format.percent(s.cpu.system)), color: Theme.soft(.cpu))
        }
        PanelChart(kind: .area, series: ChartSeries.cpuStack(total: monitor.history.points(.cpu, range: .m5), system: monitor.history.points(.cpuSystem, range: .m5)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.Panel.cpuChartA11y)
        if p.showCores, p.splitCoreKinds, SystemInfo.efficiencyCores > 0 {
            let avg = PanelCoreBars.averages(s.cpu)
            HStack {
                KeyValue(label: L10n.Monitor.performanceCores, value: Format.percent(avg.p))
                Spacer(minLength: 8)
                KeyValue(label: L10n.Monitor.efficiencyCores, value: Format.percent(avg.e))
            }
            .padding(.top, 12)
        }
        if p.showLoad {
            HStack(spacing: 12) {
                Text(L10n.Panel.loadAverage).foregroundStyle(Theme.sub)
                Spacer(minLength: 8)
                loadPair(L10n.Panel.load1, s.cpu.load.0)
                loadPair(L10n.Panel.load5, s.cpu.load.1)
                loadPair(L10n.Panel.load15, s.cpu.load.2)
            }
            .ui(13)
            .lineLimit(1)
            .frame(height: 32)
            .padding(.top, 8)
            .accessibilityElement(children: .combine)
        }
        if p.showProcesses {
            PanelProcessList(title: L10n.Monitor.topCPU, processes: Array(s.processes.byCPU.prefix(p.processCount)), value: { Format.percentValue($0.cpu) }, link: .cpu)
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
        PanelHeader(module: .gpu)
        PanelStand {
            BigValue(value: Format.percentNumber(g.utilization), unit: "%", size: BigValue.panelLead)
        }
        PanelChart(kind: .area, series: ChartSeries.line(monitor.history.points(.gpu, range: .m5), Theme.color(for: .gpu)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.Panel.gpuChartA11y)
        if p.showMemory || p.showFrequency || p.showVideo || p.showTempPower {
            FigureGrid(columns: 3) {
                if p.showMemory {
                    let vram = GPUText.vram(g)
                    Figure(name: L10n.Panel.vram, value: vram.0, unit: vram.1, size: 22)
                }
                if p.showFrequency {
                    let f = Format.parts(g.frequencyMHz.map(Format.frequency) ?? L10n.Common.dash)
                    Figure(name: L10n.Panel.frequency, value: f.0, unit: f.1, size: 22)
                }
                if p.showTempPower {
                    Figure(name: L10n.Panel.temperature, value: g.temperature.map { Format.temperatureNumber($0, unit: unit) } ?? L10n.Common.dash, unit: g.temperature == nil ? nil : "°", size: 22)
                    let w = Format.parts(g.power.map(Format.watts) ?? L10n.Common.dash)
                    Figure(name: L10n.Panel.power, value: w.0, unit: w.1, size: 22)
                }
                if p.showVideo {
                    let w = Format.parts(g.decodeWatts.map(Format.watts) ?? L10n.Common.dash)
                    Figure(name: L10n.Monitor.videoDecode, value: w.0, unit: w.1, size: 22)
                }
            }
            .padding(.top, 18)
        }
        if p.showProcesses {
            PanelProcessList(title: L10n.Monitor.topGPU, processes: Array(monitor.snapshot.processes.byGPU.prefix(p.processCount)), value: { Format.percentValue($0.gpu) }, link: .gpu)
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
        PanelHeader(module: .memory)
        PanelStand {
            BigValue(value: Format.percentNumber(m.usedFraction), unit: "%", size: BigValue.panelLead)
        } foot: {
            Text(Format.memory(used: m.used, of: m.total))
        }
        if p.showComposition {
            StackedBar(parts: MemoryParts.of(m).map { .init(label: L10n.Monitor.partValue($0.label, Format.memory(UInt64($0.bytes))), value: $0.bytes, color: $0.color,
                                                            ring: $0.label == L10n.Memory.free) }, keySize: 12)
                .padding(.top, 14)
        }
        if p.showPressure || p.showSwap {
            HStack {
                if p.showPressure { KeyValue(label: L10n.Monitor.memoryPressure, value: pr.0, valueColor: m.pressure == .normal ? Theme.text : pr.1) }
                Spacer(minLength: 8)
                if p.showSwap { KeyValue(label: L10n.Memory.swap, value: Format.memory(m.swapUsed)) }
            }
            .padding(.top, 18)
        }
        if p.showPressure {
            PanelChart(kind: .area, series: ChartSeries.line(monitor.history.points(.memoryPressure, range: .m5), Theme.color(for: .memory)), height: 44, top: 6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.Panel.pressureChartA11y)
        }
        if p.showProcesses {
            PanelProcessList(title: L10n.Monitor.topMemory, processes: Array(monitor.snapshot.processes.byMemory.prefix(p.processCount)), value: { Format.memory($0.memory) }, link: .memory)
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
        PanelHeader(module: .network)
        if n.connected {
            PanelStand {
                HStack(alignment: .top, spacing: 16) {
                    speed(MenuBarText.downArrow, n.down, p.speedUnit)
                    speed(MenuBarText.upArrow, n.up, p.speedUnit)
                }
            }
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
            .padding(.top, 12)
        }
        PanelChart(kind: .mirroredArea, series: ChartSeries.mirrored(down, Theme.color(for: .network), up, Theme.color(for: .network)),
                   seconds: seconds, maxValue: dMax, bottomMax: uMax)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.Panel.networkChartA11y)
        VStack(spacing: 0) {
            if n.connected {
                KVRow(key: L10n.Network.localIP, value: n.localIP.isEmpty ? L10n.Common.dash : PanelText.localIP(n))
                if !n.router.isEmpty { KVRow(key: L10n.Network.router, value: n.router) }
                if p.showPublicIP { KVRow(key: L10n.Network.publicIP, value: monitor.publicIP ?? L10n.Common.dash) }
            } else if let last = n.lastConnected {
                KVRow(key: L10n.Network.lastConnected, value: Format.time(last))
            }
            KVRow(key: L10n.Network.today, value: L10n.Network.downUp(Format.storage(n.todayDown), Format.storage(n.todayUp)))
        }
        .padding(.top, 12)
        if p.showProcesses && n.connected {
            PanelProcessList(title: L10n.Monitor.topNetwork, processes: Array(monitor.snapshot.processes.byNetwork.prefix(4)),
                             value: { MenuBarText.downArrow + " " + Format.rate($0.netDown, unit: p.speedUnit) }, secondary: { MenuBarText.upArrow + " " + Format.rate($0.netUp, unit: p.speedUnit) },
                             valueWidth: 78, secondaryWidth: 68, rowHeight: 30, valueSize: 13, link: .network)
        }
    }

    /// Download and upload alike.
    private func speed(_ label: String, _ v: Double, _ unit: SpeedUnit) -> some View {
        let parts = Format.rateParts(v, unit: unit)
        return VStack(alignment: .leading, spacing: 4) {
            SmallLabel(text: label)
            BigValue(value: parts.0, unit: parts.1, size: 36, proportional: true)
        }
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
        PanelHeader(module: .disk)
        PanelStand {
            BigValue(value: volume.map { Format.percentNumber($0.usedFraction) } ?? L10n.Common.dash, unit: volume == nil ? nil : "% " + L10n.Disk.used, size: BigValue.panelLead)
        } foot: {
            KeyValue(label: MenuBarText.downArrow, value: Format.rate(d.read), size: 13)
            KeyValue(label: MenuBarText.upArrow, value: Format.rate(d.write), size: 13)
        }
        if p.showGraph {
            let reads = monitor.history.points(.diskRead, range: .m5), writes = monitor.history.points(.diskWrite, range: .m5)
            let from = Date().addingTimeInterval(-60)
            let top = ConsoleChart.niceMax(max(reads.filter { $0.date >= from }.map(\.value).max() ?? 0, writes.filter { $0.date >= from }.map(\.value).max() ?? 0, 1_000_000) * 1.1)
            PanelChart(kind: .mirroredArea, series: ChartSeries.mirrored(reads, Theme.color(for: .disk), writes, Theme.color(for: .disk)), maxValue: top, bottomMax: top, height: 56)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.Panel.diskChartA11y)
        }
        ForEach(p.showAllDisks ? d.volumes : (volume.map { [$0] } ?? [])) { v in
            let free = Format.parts(Format.storage(v.available))
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(v.name).ui(14, 500).lineLimit(1)
                    Text(v.isInternal ? L10n.Disk.internalDrive : L10n.Disk.external).ui(14).foregroundStyle(Theme.sub).fixedSize()
                    if v.isEjectable && !v.isRoot { EjectButton(volume: v, size: 18) }
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(free.0).ui(14, 500)
                        Text(" " + L10n.Monitor.unitFree(free.1)).ui(14).foregroundStyle(Theme.sub)
                    }
                    .lineLimit(1)
                    .fixedSize()
                }
                KeyValues(pairs: VolumeBlock.details(v))
            }
            .padding(.top, 14)
            .accessibilityElement(children: .combine)
        }
        VStack(spacing: 0) {
            KVRow(key: L10n.Disk.sinceBoot, value: L10n.Disk.readWriteTotals(Format.storage(d.totalRead), Format.storage(d.totalWritten)))
            if p.showHealth, let h = d.health {
                KVRow(key: L10n.Panel.health, value: L10n.Panel.healthValue(Format.percent(h.lifeRemaining), h.ok ? L10n.Monitor.smartGood : L10n.Monitor.smartFailing),
                      valueColor: h.ok ? Theme.text : Theme.danger)
            }
        }
        .padding(.top, 10)
        if p.showProcesses {
            PanelProcessList(title: L10n.Monitor.topReadWrite, processes: Array(monitor.snapshot.processes.byDisk.prefix(5)), value: { Format.rate($0.diskTotal) }, link: .disk)
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
        let unit = settings.prefs.general.temperatureUnit
        PanelHeader(module: .battery)
        if b.hasBattery {
            PanelStand {
                BigValue(value: Format.percentNumber(b.level), unit: "%", size: BigValue.panelLead, color: Theme.batteryLevel(b))
            } foot: {
                HStack(spacing: 5) {
                    if b.isCharging { ChargingBolt(size: 13) }
                    Text(PanelText.batteryState(b)).ui(13, 500).foregroundStyle(Theme.text).fixedSize()
                }
                if b.isCharging, let m = b.minutesToFull {
                    Text(L10n.Battery.untilFull(BatteryTime.text(m)))
                } else if !b.onAC, let m = b.minutesToEmpty {
                    Text(L10n.Battery.remaining(BatteryTime.text(m)))
                }
            }
            PanelChart(kind: .area, series: ChartSeries.line(monitor.history.points(.battery, range: .h24), Theme.batteryLevel(b, lead: false)),
                       seconds: TimeRange.h24.seconds, maxGap: TimeRange.h24.batteryGap, height: 64, bands: ChargingBands.of(.h24))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.Panel.batteryChartA11y)
            FigureGrid {
                let drawn: Double? = b.onAC ? b.systemPowerIn : b.power.map(abs)
                if p.showPower, let drawn {
                    let adapter = b.onAC ? b.adapterWatts : nil
                    Figure(name: L10n.Monitor.systemDraw, value: String(format: "%.1f", drawn), unit: adapter.map { L10n.Monitor.ofTotal("\($0) " + L10n.Common.wattUnit) } ?? L10n.Common.wattUnit, size: 22)
                }
                if p.showHealth, let h = b.health { Figure(name: L10n.Battery.health, value: Format.percentNumber(h), unit: "%", size: 22) }
                if p.showCycles, let c = b.cycles { Figure(name: L10n.Battery.cycles, value: "\(c)", unit: L10n.Monitor.ofTotal("\(b.designCycles ?? 1000)"), size: 22) }
                if p.showTemperature, let t = b.temperature ?? monitor.snapshot.sensors.value(.battery) {
                    Figure(name: L10n.Battery.temperature, value: Format.temperatureNumber(t, unit: unit), unit: Format.temperatureSymbol(unit), size: 22)
                }
            }
            .padding(.top, 18)
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
        let reading = MenuBarText.sensorValue(s, p.sensor)
        PanelHeader(module: .sensors)
        PanelStand {
            BigValue(value: reading.map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash, size: BigValue.panelLead)
        } foot: {
            if p.showThermal {
                KeyValue(label: L10n.Sensors.thermalShort, value: L10n.Monitor.thermalLevel(s.thermal.rawValue), valueColor: s.thermal == .nominal ? Theme.text : ThermalText.color(s.thermal), size: 13)
            }
        }
        if p.showAllTemps, !s.temps.isEmpty {
            VStack(spacing: 0) {
                ForEach(s.temps) { t in
                    MeterRow(name: PanelText.tempName(t.group), fraction: t.value / 100, value: Format.temperatureNumber(t.value, unit: unit) + "°",
                             color: t.value >= 90 ? Theme.danger : t.value >= 70 ? Theme.warn : Theme.mid, valueWidth: 36)
                }
            }
            .padding(.top, 8)
        }
        if p.showFans, s.hasFans {
            VStack(spacing: 0) {
                ForEach(s.fans) { f in
                    MeterRow(name: PanelText.fanName(f.id, count: s.fans.count), fraction: f.max > f.min ? (f.rpm - f.min) / (f.max - f.min) : 0,
                             value: Format.rpm(f.rpm), valueWidth: 72)
                }
            }
            .padding(.top, 12)
        }
        if p.showPower, s.systemPower != nil || s.cpuPower != nil || s.gpuPower != nil {
            VStack(alignment: .trailing, spacing: 8) {
                if let w = s.systemPower { KeyValue(label: L10n.Monitor.wholeMac, value: Format.watts(w)) }
                StackedBar(parts: PowerParts.of(s, keyed: false), keySize: 12)
            }
            .padding(.top, 14)
        }
    }
}
