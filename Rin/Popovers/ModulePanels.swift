import AppKit
import SwiftUI

/// The per-module dropdown: header, hero readouts, chart, sections, quit confirmation.
struct ModulePanel: View {
    let module: Module
    var quitCenter = QuitCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

// MARK: - Shared pieces

/// The last minute (or the network's chosen span) in a dropdown: no scale, "−60 秒 … 现在" under it.
struct PanelChart: View {
    var kind: ConsoleChart.Kind
    var series: [ChartSeries]
    var seconds: Double = 60
    var maxValue: Double = 100
    var bottomMax: Double = 1
    var height: CGFloat = 64
    var labels: [String]? = nil
    var bands: [ClosedRange<Date>] = []

    var body: some View {
        ConsoleChart(kind: kind, series: series, span: seconds, maxValue: maxValue, bottomMax: bottomMax, height: height,
                     xLabels: labels ?? [L10n.Chart.secondsAgo(Int(seconds)), L10n.Range.now], baseline: kind != .mirrored, bands: bands)
    }
}

/// A big reading with a small grey label above it, or a key in front of the label.
struct PanelStat<Value: View>: View {
    var label: String
    var key: Color? = nil
    @ViewBuilder var value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let key { RoundedRectangle(cornerRadius: 2, style: .continuous).fill(key).frame(width: 8, height: 8) }
                Text(label).ui(13).foregroundStyle(Theme.sub).lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) { value }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Readings in a grid of equal columns (12 apart vertically, 14 across).
struct PanelStatGrid<Content: View>: View {
    var columns = 2
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .leading), count: columns), alignment: .leading, spacing: 12) {
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
        PanelHeader(module: .cpu, subtitle: PanelText.cpuSubtitle())
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.Monitor.totalUsage).ui(12).foregroundStyle(Theme.sub)
                BigValue(value: Format.percent(s.cpu.total), size: 40)
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 4) {
                KeyValue(label: L10n.Panel.user, value: Format.percent(s.cpu.user), key: Theme.cpu)
                KeyValue(label: L10n.Panel.system, value: Format.percent(s.cpu.system), key: Theme.sys)
            }
            .padding(.bottom, 4)
        }
        .accessibilityElement(children: .combine)
        PanelChart(kind: .bars, series: [ChartSeries(id: "t", points: monitor.history.points(.cpu, range: .m5), color: Theme.cpu),
                                         ChartSeries(id: "s", points: monitor.history.points(.cpuSystem, range: .m5), color: Theme.sys)])
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.Panel.cpuChartA11y)
        if p.showCores, !s.cpu.perCore.isEmpty {
            let split = p.splitCoreKinds && SystemInfo.efficiencyCores > 0
            ConsoleRule()
            VStack(alignment: .leading, spacing: 0) {
                PanelTitle(title: L10n.Panel.cores) { Text(split ? PanelText.coreSplit() ?? "" : L10n.Panel.coreCount(s.cpu.perCore.count)).ui(12) }
                PanelCoreBars(cpu: s.cpu, split: split).frame(height: 26).padding(.top, 8).padding(.bottom, 6)
                if split {
                    let avg = PanelCoreBars.averages(s.cpu)
                    HStack {
                        KeyValue(label: L10n.Panel.perfAverage, value: Format.percent(avg.p))
                        Spacer(minLength: 8)
                        KeyValue(label: L10n.Panel.effAverage, value: Format.percent(avg.e))
                    }
                }
            }
        }
        if p.showLoad {
            ConsoleRule()
            HStack(spacing: 12) {
                Text(L10n.Panel.loadAverage).ui(13).foregroundStyle(Theme.sub).fixedSize()
                Spacer(minLength: 0)
                KeyValue(label: L10n.Panel.load1, value: Format.load(s.cpu.load.0))
                KeyValue(label: L10n.Panel.load5, value: Format.load(s.cpu.load.1))
                KeyValue(label: L10n.Panel.load15, value: Format.load(s.cpu.load.2))
            }
            .frame(height: 22)
        }
        if p.showProcesses {
            ConsoleRule()
            PanelProcessList(title: L10n.Panel.topUsage, processes: Array(s.processes.byCPU.prefix(p.processCount)), metric: .cpu, color: Theme.cpu, link: .cpu)
        }
    }
}

/// One bar per core filled from the bottom (system under user), efficiency cores set apart.
struct PanelCoreBars: View {
    var cpu: CPUSample
    var split: Bool

    static func averages(_ cpu: CPUSample) -> (p: Double, e: Double) {
        var p: [Double] = [], e: [Double] = []
        for (i, v) in cpu.perCore.enumerated() {
            if i < cpu.coreKinds.count, cpu.coreKinds[i] == .efficiency { e.append(v) } else { p.append(v) }
        }
        let avg = { (a: [Double]) in a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }
        return (avg(p), avg(e))
    }

    var body: some View {
        let isE = { (i: Int) in split && i < cpu.coreKinds.count && cpu.coreKinds[i] == .efficiency }
        let perf = cpu.perCore.indices.filter { !isE($0) }
        let eff = cpu.perCore.indices.filter { isE($0) }
        HStack(spacing: 3) {
            ForEach(perf, id: \.self) { bar($0) }
            if !eff.isEmpty {
                Color.clear.frame(width: 3)
                ForEach(eff, id: \.self) { bar($0) }
            }
        }
        .accessibilityHidden(true)
    }

    private func bar(_ i: Int) -> some View {
        let sys = min(1, max(0, i < cpu.perCoreSystem.count ? cpu.perCoreSystem[i] : 0))
        let total = min(1, max(0, cpu.perCore[i]))
        return GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle().fill(Theme.cpu).frame(height: geo.size.height * max(0, total - sys))
                Rectangle().fill(Theme.sys).frame(height: geo.size.height * min(total, sys))
            }
        }
        .background(Theme.track)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
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
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.Panel.utilization).ui(12).foregroundStyle(Theme.sub)
                BigValue(value: Format.percent(g.utilization), size: 40)
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 4) {
                KeyValue(label: L10n.Panel.vram, value: Format.percent(vram))
                KeyValue(label: L10n.Panel.temperature, value: g.temperature.map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash)
            }
            .padding(.bottom, 4)
        }
        .accessibilityElement(children: .combine)
        PanelChart(kind: .bars, series: [ChartSeries(id: "g", points: monitor.history.points(.gpu, range: .m5), color: Theme.gpu)])
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.Panel.gpuChartA11y)
        if p.showMemory || p.showFrequency || p.showVideo || p.showTempPower {
            ConsoleRule()
            PanelStatGrid {
                if p.showMemory {
                    PanelStat(label: g.memoryLimit > 0 ? L10n.Panel.vramLimit(Format.memory(g.memoryLimit)) : L10n.Panel.vram) {
                        let used = Format.parts(Format.memory(g.memoryUsed))
                        BigValue(value: used.0, unit: L10n.Panel.unitUsed(used.1), size: 20)
                    }
                }
                if p.showFrequency {
                    PanelStat(label: L10n.Panel.frequency) {
                        let f = Format.parts(g.frequencyMHz.map(Format.frequency) ?? L10n.Common.dash)
                        BigValue(value: f.0, unit: f.1, size: 20)
                    }
                }
                if p.showVideo {
                    PanelStat(label: L10n.Monitor.videoDecode) { BigValue(value: MediaText.state(g.decodeWatts), size: 20) }
                }
                if p.showTempPower {
                    PanelStat(label: L10n.Panel.power) {
                        let w = Format.parts(g.power.map(Format.watts) ?? L10n.Common.dash)
                        BigValue(value: w.0, unit: w.1, size: 20)
                    }
                }
            }
        }
        if p.showProcesses {
            ConsoleRule()
            PanelProcessList(title: L10n.Panel.topUsage, processes: Array(monitor.snapshot.processes.byGPU.prefix(p.processCount)), metric: .gpu, color: Theme.gpu)
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
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                BigValue(value: Format.percent(m.usedFraction), size: 40)
                Text(L10n.Monitor.usedOfTotal(Format.memory(m.used), Format.memory(m.total))).ui(12).foregroundStyle(Theme.sub)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(L10n.Panel.pressure).ui(12).foregroundStyle(Theme.sub)
                StatusText(text: pr.0, color: pr.1)
            }
        }
        .accessibilityElement(children: .combine)
        if p.showComposition {
            VStack(alignment: .leading, spacing: 10) {
                SegmentBar(parts: MemoryParts.of(m).map { ($0.bytes, $0.color) })
                StackLegend(items: MemoryParts.of(m).map { .init(label: $0.label, value: Format.memory(UInt64($0.bytes)), color: $0.color) }, columns: 3)
            }
        }
        if p.showPressure {
            ConsoleRule()
            VStack(alignment: .leading, spacing: 8) {
                PanelTitle(title: L10n.Panel.pressure) {
                    if p.showSwap { KeyValue(label: L10n.Memory.swap, value: Format.memory(m.swapUsed)) }
                }
                PanelChart(kind: .area, series: [ChartSeries(id: "p", points: monitor.history.points(.memoryPressure, range: .m5), color: Theme.ok, fill: 0.18, lineWidth: 1.5)],
                           height: 44)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.Panel.pressureChartA11y)
            }
        } else if p.showSwap {
            ConsoleRule()
            KVRow(key: L10n.Memory.swap, value: Format.memory(m.swapUsed))
        }
        if p.showProcesses {
            ConsoleRule()
            PanelProcessList(title: L10n.Panel.topUsage, processes: Array(monitor.snapshot.processes.byMemory.prefix(p.processCount)), metric: .memory, color: Theme.mem,
                             valueWidth: 62, link: .memory)
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
            HStack(alignment: .top, spacing: 14) {
                PanelStat(label: MenuBarText.downArrow + " " + L10n.Panel.download, key: Theme.down) { speed(n.down, p.speedUnit) }
                PanelStat(label: MenuBarText.upArrow + " " + L10n.Panel.upload, key: Theme.up) { speed(n.up, p.speedUnit) }
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
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.well))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
        }
        PanelChart(kind: .mirrored, series: [ChartSeries(id: "d", points: down, color: Theme.down), ChartSeries(id: "u", points: up, color: Theme.up)],
                   seconds: seconds, maxValue: dMax, bottomMax: uMax)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.Panel.networkChartA11y)
        ConsoleRule()
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
        if p.showProcesses && n.connected {
            ConsoleRule()
            PanelSection(title: L10n.Panel.topTraffic, link: .network) {
                TrafficList(processes: Array(monitor.snapshot.processes.byNetwork.prefix(5)), unit: p.speedUnit)
            }
        }
    }

    private func speed(_ v: Double, _ unit: SpeedUnit) -> some View {
        let parts = Format.rateParts(v, unit: unit)
        return BigValue(value: parts.0, unit: parts.1)
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
        HStack(alignment: .top, spacing: 12) {
            PanelStat(label: L10n.Disk.read, key: Theme.read) { rate(d.read) }
            PanelStat(label: L10n.Disk.write, key: Theme.write) { rate(d.write) }
            PanelStat(label: L10n.Disk.used) { BigValue(value: volume.map { Format.percent($0.usedFraction) } ?? L10n.Common.dash) }
        }
        if p.showGraph {
            let reads = monitor.history.points(.diskRead, range: .m5), writes = monitor.history.points(.diskWrite, range: .m5)
            let from = Date().addingTimeInterval(-60)
            PanelChart(kind: .mirrored, series: [ChartSeries(id: "r", points: reads, color: Theme.read), ChartSeries(id: "w", points: writes, color: Theme.write)],
                       maxValue: ConsoleChart.niceMax(max(reads.filter { $0.date >= from }.map(\.value).max() ?? 0, 1_000_000) * 1.1),
                       bottomMax: ConsoleChart.niceMax(max(writes.filter { $0.date >= from }.map(\.value).max() ?? 0, 1_000_000) * 1.1), height: 56)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.Panel.diskChartA11y)
        }
        let volumes = p.showAllDisks ? d.volumes : (volume.map { [$0] } ?? [])
        if !volumes.isEmpty {
            ConsoleRule()
            VStack(spacing: 12) {
                ForEach(volumes) { VolumeBlock(volume: $0) }
            }
        }
        ConsoleRule()
        VStack(spacing: 0) {
            KVRow(key: L10n.Disk.sinceBoot, value: L10n.Disk.readWriteTotals(Format.storage(d.totalRead), Format.storage(d.totalWritten)))
            if p.showHealth, let h = d.health {
                KVRow(key: L10n.Panel.health, value: L10n.Panel.healthValue(Format.percent(h.lifeRemaining), h.ok ? L10n.Monitor.smartGood : L10n.Monitor.smartFailing),
                      valueColor: h.ok ? Theme.ok : Theme.danger)
            }
        }
        if p.showProcesses {
            ConsoleRule()
            PanelProcessList(title: L10n.Panel.topDisk, processes: Array(monitor.snapshot.processes.byDisk.prefix(5)), metric: .disk, color: Theme.disk,
                             valueWidth: 68)
        }
    }

    private func rate(_ v: Double) -> some View {
        let parts = Format.rateParts(v)
        return BigValue(value: parts.0, unit: parts.1)
    }
}

/// A volume in the disk dropdown: name, tag, eject and free space; capacity as cells; the details.
struct VolumeBlock: View {
    var volume: Volume

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(volume.name).ui(13, 600).lineLimit(1)
                TagText(text: volume.isInternal ? L10n.Disk.internalDrive : L10n.Disk.external)
                if volume.isEjectable && !volume.isRoot { EjectButton(volume: volume, size: 20) }
                Spacer(minLength: 4)
                Text(L10n.Disk.available(Format.storage(volume.available))).ui(13, 500).lineLimit(1)
            }
            .frame(height: 20)
            CapacityCells(used: Double(max(0, volume.used - volume.purgeable)), purgeable: Double(volume.purgeable), total: Double(max(volume.total, 1)), height: 6)
            Text(volume.purgeable > 0
                 ? L10n.Panel.volumeUsedPurgeable(Format.storage(volume.used), Format.storage(volume.purgeable), Format.storage(volume.total))
                 : L10n.Disk.usedOf(Format.storage(volume.used), Format.storage(volume.total)))
                .ui(12).foregroundStyle(Theme.sub).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
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
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    BigValue(value: Format.percent(b.level), size: 40, color: low ? Theme.danger : Theme.text)
                    StatusText(text: PanelText.batteryState(b), color: b.onAC ? Theme.ok : (low ? Theme.danger : Theme.sub))
                }
                Spacer(minLength: 8)
                if b.isCharging, let m = b.minutesToFull {
                    BigValue(value: BatteryTime.text(m), unit: L10n.Panel.untilFullLabel)
                } else if !b.onAC, let m = b.minutesToEmpty {
                    BigValue(value: BatteryTime.text(m), unit: L10n.Panel.timeLeftLabel)
                }
            }
            .accessibilityElement(children: .combine)
            ConsoleRule()
            PanelStatGrid {
                let watts: Double? = b.isCharging ? b.power.flatMap { $0 > 0 ? $0 : nil } : (b.onAC ? b.systemPowerIn : b.power.map(abs))
                PanelStat(label: b.isCharging ? L10n.Battery.chargingPower : L10n.Battery.power) {
                    BigValue(value: watts.map { "\(Int($0.rounded()))" } ?? L10n.Common.dash, unit: watts == nil ? nil : L10n.Common.wattUnit, size: 20)
                }
                if p.showHealth, let h = b.health {
                    PanelStat(label: L10n.Battery.health) { BigValue(value: Format.percent(h), size: 20) }
                }
                if p.showCycles, let c = b.cycles {
                    PanelStat(label: L10n.Battery.cycles) { BigValue(value: "\(c)", unit: L10n.Monitor.ofTotal("\(b.designCycles ?? 1000)"), size: 20) }
                }
                if p.showTemperature, let t = b.temperature ?? monitor.snapshot.sensors.value(.battery) {
                    PanelStat(label: L10n.Battery.temperature) { BigValue(value: Format.temperatureNumber(t, unit: unit), unit: Format.temperatureSymbol(unit), size: 20) }
                }
            }
            ConsoleRule()
            VStack(alignment: .leading, spacing: 8) {
                PanelTitle(title: L10n.Battery.level) { Text(L10n.Range.last24h).ui(12) }
                ConsoleChart(kind: .area, series: [ChartSeries(id: "b", points: monitor.history.points(.battery, range: .h24), color: Theme.bat, fill: 0.16, lineWidth: 1.5)],
                             span: TimeRange.h24.seconds, maxValue: 100, height: 72, xLabels: [L10n.Range.ago24h, L10n.Range.ago12h, L10n.Range.now],
                             bands: ChargingBands.of(.h24), slot: 5)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.Panel.batteryChartA11y)
            }
        }
        // Bluetooth accessories have their own module; a UPS stays with the battery.
        if !b.ups.isEmpty {
            ConsoleRule()
            PanelSection(title: L10n.Battery.ups) {
                VStack(spacing: 0) {
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

/// A UPS in the battery dropdown: icon, name and state, its level as cells, the percentage.
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
                Text(name).lineLimit(1)
                if let detail { Text(detail).ui(12).foregroundStyle(Theme.sub).lineLimit(1) }
            }
            Spacer(minLength: 4)
            DotMeter(fraction: level, color: low ? Theme.danger : Theme.bat, count: 16).frame(width: 72)
            Text(Format.percent(level)).ui(13, 500).foregroundStyle(low ? Theme.danger : Theme.text)
                .frame(width: 40, alignment: .trailing)
        }
        .frame(minHeight: 36)
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
        let deg = { (c: Double?) in c.map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash }
        PanelHeader(module: .sensors, subtitle: s.fans.isEmpty ? L10n.Panel.passiveCooling : L10n.Panel.fanCount(s.fans.count))
        ShareRow(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.Sensors.choice(p.sensor)).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
                BigValue(value: deg(MenuBarText.sensorValue(s, p.sensor)), size: 40)
            }
            .share(1.4)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.Sensors.gpu).ui(12).foregroundStyle(Theme.sub)
                BigValue(value: deg(s.value(.gpu)))
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .share(1)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.Sensors.ssd).ui(12).foregroundStyle(Theme.sub)
                BigValue(value: deg(s.value(.ssd)))
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .share(1)
        }
        .accessibilityElement(children: .combine)
        if p.showThermal {
            let th = PanelText.thermal(s.thermal)
            HStack {
                Text(L10n.Sensors.thermalState).ui(13).foregroundStyle(Theme.sub)
                Spacer(minLength: 8)
                StatusText(text: th.0, color: th.1)
            }
            .frame(height: 22)
            .accessibilityElement(children: .combine)
        }
        if p.showAllTemps, !s.temps.isEmpty {
            ConsoleRule()
            PanelSection(title: L10n.Sensors.temperatures) {
                VStack(spacing: 0) {
                    ForEach(s.temps) { t in
                        MeterRow(name: PanelText.tempName(t.group), fraction: t.value / 100,
                                 value: Format.temperature(t.value, unit: unit, showUnit: true), color: TempZone.meter(t.value))
                    }
                }
            }
        }
        if p.showFans {
            ConsoleRule()
            if s.hasFans {
                PanelSection(title: L10n.Sensors.fans, right: s.fans.first.map { L10n.Sensors.maxRPM(Int($0.max)) }) {
                    VStack(spacing: 0) {
                        ForEach(s.fans) { f in
                            MeterRow(name: PanelText.fanName(f.id, count: s.fans.count), fraction: f.max > 0 ? f.rpm / f.max : 0,
                                     value: Format.rpm(f.rpm), color: Theme.temp)
                        }
                    }
                }
            } else {
                PanelSection(title: L10n.Sensors.fans) { KVRow(key: L10n.Sensors.fanless, value: "") }
            }
        }
        if p.showPower, s.systemPower != nil || s.cpuPower != nil || s.gpuPower != nil {
            let cpu = s.cpuPower ?? 0, gpu = s.gpuPower ?? 0
            let other = max(0, (s.systemPower ?? cpu + gpu) - cpu - gpu)
            ConsoleRule()
            VStack(alignment: .leading, spacing: 8) {
                PanelTitle(title: L10n.Sensors.power) { KeyValue(label: L10n.Sensors.systemPower, value: s.systemPower.map(Format.watts) ?? L10n.Common.dash) }
                SegmentBar(parts: [(cpu, Theme.cpu), (gpu, Theme.gpu), (other, Theme.neutral.opacity(0.4))], height: 8)
                HStack(spacing: 14) {
                    KeyValue(label: L10n.Module.cpu, value: s.cpuPower.map(Format.watts) ?? L10n.Common.dash, key: Theme.cpu)
                    KeyValue(label: L10n.Module.gpu, value: s.gpuPower.map(Format.watts) ?? L10n.Common.dash, key: Theme.gpu)
                }
            }
        }
    }
}
