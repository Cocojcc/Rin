import AppKit
import SwiftUI

/// The per-module dropdown: header, module cards, top processes, footer.
struct ModulePanel: View {
    let module: Module
    var quitCenter = QuitCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch module {
            case .cpu: CPUPanel()
            case .gpu: GPUPanel()
            case .memory: MemoryPanel()
            case .network: NetworkPanel()
            case .disk: DiskPanel()
            case .battery: BatteryPanel()
            case .sensors: SensorsPanel()
            }
            if let toast = quitCenter.toast { QuitToast(toast: toast) }
            PanelFooter(module: module)
        }
        .padding(10)
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

    static func pressure(_ p: MemoryPressure) -> (String, Color, Color) {
        switch p {
        case .normal: return (L10n.Panel.pressureNormal, Theme.ok, Theme.okBg)
        case .warning: return (L10n.Panel.pressureWarning, Theme.warnText, Theme.warnBg)
        case .critical: return (L10n.Panel.pressureCritical, Theme.dangerText, Theme.dangerBg)
        }
    }

    static func thermal(_ t: ThermalLevel) -> (String, Color, Color) {
        switch t {
        case .nominal: return (L10n.Panel.thermalNominal, Theme.ok, Theme.okBg)
        case .fair: return (L10n.Panel.thermalFair, Theme.warnText, Theme.warnBg)
        case .serious: return (L10n.Panel.thermalSerious, Theme.dangerText, Theme.dangerBg)
        case .critical: return (L10n.Panel.thermalCritical, Theme.dangerText, Theme.dangerBg)
        }
    }

    static func interface(_ n: NetworkSample) -> String {
        guard n.connected else { return L10n.Panel.notConnectedKind(kindName(n.kind)) }
        return "\(kindName(n.kind)) · \(n.interface)"
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

private func percentParts(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))" }

// MARK: - CPU

struct CPUPanel: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared

    var body: some View {
        let s = monitor.snapshot
        let p = settings.prefs.cpu
        let _ = monitor.tick
        PanelHeader(icon: Icons.cpu, color: Theme.cpu, title: L10n.Module.cpu, subtitle: PanelText.cpuSubtitle()) {
            BigValue(number: percentParts(s.cpu.total), unit: "%", color: Theme.cpu, size: 28, unitSize: 15)
        }
        PanelCard {
            MiniChart(series: [
                .init(values: monitor.history.latest(.cpu, seconds: 60).map { $0 / 100 }, color: Theme.cpu),
                .init(values: monitor.history.latest(.cpuSystem, seconds: 60).map { $0 / 100 }, color: Theme.sys, fill: 0.22, lineWidth: 1.25),
            ])
            .frame(height: 60)
            .accessibilityLabel(L10n.Panel.cpuChartA11y)
            PanelLegend(items: [(Theme.cpu, L10n.Panel.user, Format.percent(s.cpu.user)), (Theme.sys, L10n.Panel.system, Format.percent(s.cpu.system))],
                        right: L10n.Range.last60s)
        }
        if p.showCores, !s.cpu.perCore.isEmpty {
            PanelCard(padding: EdgeInsets(top: 4, leading: 12, bottom: 10, trailing: 12)) {
                PanelTitle(text: L10n.Panel.cores, right: p.splitCoreKinds ? PanelText.coreSplit() : L10n.Panel.coreCount(s.cpu.perCore.count))
                CoreBars(cpu: s.cpu, split: p.splitCoreKinds, height: 34)
                    .padding(.top, 4)
                if p.splitCoreKinds, SystemInfo.efficiencyCores > 0 {
                    let avg = CoreBars.averages(s.cpu)
                    HStack {
                        (Text(L10n.Panel.perfAverage) + Text(" ") + Text(Format.percent(avg.p)).foregroundColor(Theme.text).fontWeight(.semibold))
                        Spacer()
                        (Text(L10n.Panel.effAverage) + Text(" ") + Text(Format.percent(avg.e)).foregroundColor(Theme.text).fontWeight(.semibold))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.sub)
                    .padding(.top, 6)
                }
            }
        }
        if p.showLoad {
            PanelCard(padding: EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)) {
                HStack {
                    Text(L10n.Panel.loadAverage).foregroundStyle(Theme.sub)
                    Spacer()
                    HStack(spacing: 12) {
                        loadItem(s.cpu.load.0, L10n.Panel.load1)
                        loadItem(s.cpu.load.1, L10n.Panel.load5)
                        loadItem(s.cpu.load.2, L10n.Panel.load15)
                    }
                }
                .frame(height: 32)
            }
        }
        if p.showProcesses {
            PanelProcessList(title: L10n.Panel.topUsage, processes: Array(s.processes.byCPU.prefix(p.processCount)), metric: .cpu, color: Theme.cpu)
        }
    }

    private func loadItem(_ v: Double, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(Format.load(v)).fontWeight(.semibold).monospacedDigit()
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.faint)
        }
    }
}

/// One bar per logical core; efficiency cores are lighter and set apart.
struct CoreBars: View {
    var cpu: CPUSample
    var split: Bool
    var height: CGFloat
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
        let perf = indices.filter { !(split && $0 < cpu.coreKinds.count && cpu.coreKinds[$0] == .efficiency) }
        let eff = split ? indices.filter { $0 < cpu.coreKinds.count && cpu.coreKinds[$0] == .efficiency } : []
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(perf, id: \.self) { bar(cpu.perCore[$0], dim: false) }
            if !eff.isEmpty {
                Color.clear.frame(width: 3)
                ForEach(eff, id: \.self) { bar(cpu.perCore[$0], dim: true) }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func bar(_ v: Double, dim: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Theme.track)
                Rectangle().fill(color.opacity(dim ? 0.55 : 1))
                    .frame(height: geo.size.height * min(1, max(0, v)))
            }
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
    }
}

// MARK: - GPU

struct GPUPanel: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared

    var body: some View {
        let s = monitor.snapshot
        let p = settings.prefs.gpu
        let unit = settings.prefs.general.temperatureUnit
        let _ = monitor.tick
        PanelHeader(icon: Icons.gpu, color: Theme.gpu, title: L10n.Module.gpu, subtitle: L10n.Panel.chipCores(s.gpu.model, s.gpu.cores)) {
            BigValue(number: percentParts(s.gpu.utilization), unit: "%", color: Theme.gpu, size: 28, unitSize: 15)
        }
        PanelCard {
            MiniChart(series: [.init(values: monitor.history.latest(.gpu, seconds: 60).map { $0 / 100 }, color: Theme.gpu)])
                .frame(height: 60)
                .accessibilityLabel(L10n.Panel.gpuChartA11y)
            PanelLegend(items: [(Theme.gpu, L10n.Panel.utilization, Format.percent(s.gpu.utilization))], right: L10n.Range.last60s)
        }
        if p.showMemory || p.showFrequency || p.showTempPower {
            PanelCard(padding: EdgeInsets(top: 4, leading: 12, bottom: 10, trailing: 12)) {
                if p.showMemory {
                    PanelTitle(text: L10n.Panel.vram, right: s.gpu.memoryLimit > 0 ? L10n.Panel.limit(Format.memory(s.gpu.memoryLimit)) : nil)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Format.memory(s.gpu.memoryUsed)).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                        Text(L10n.Panel.used).foregroundStyle(Theme.sub)
                    }
                    MeterBar(fraction: s.gpu.memoryLimit > 0 ? Double(s.gpu.memoryUsed) / Double(s.gpu.memoryLimit) : 0, color: Theme.gpu, height: 6)
                        .padding(.top, 8)
                }
                let stats = gpuStats(s.gpu, p, unit)
                if !stats.isEmpty {
                    if p.showMemory { Hairline().padding(.top, 10) }
                    HStack(spacing: 8) {
                        ForEach(stats, id: \.1) { StatBlock(value: $0.0, label: $0.1, valueSize: 15) }
                    }
                    .padding(.top, p.showMemory ? 10 : 6)
                }
            }
        }
        if p.showProcesses {
            PanelProcessList(title: L10n.Panel.topUsage, processes: Array(s.processes.byGPU.prefix(p.processCount)), metric: .gpu, color: Theme.gpu)
        }
    }

    private func gpuStats(_ g: GPUSample, _ p: GPUPrefs, _ unit: TemperatureUnit) -> [(String, String)] {
        var out: [(String, String)] = []
        if p.showFrequency, let f = g.frequencyMHz { out.append((Format.frequency(f), L10n.Panel.frequency)) }
        if p.showTempPower {
            if let t = g.temperature { out.append((Format.temperature(t, unit: unit, showUnit: true), L10n.Panel.temperature)) }
            if let w = g.power { out.append((Format.watts(w), L10n.Panel.power)) }
        }
        return out
    }
}

// MARK: - Memory

struct MemoryComposition: View {
    var m: MemorySample
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let total = max(Double(m.total), 1)
            HStack(spacing: 1) {
                seg(Double(m.app) / total, Theme.mem, geo.size.width)
                seg(Double(m.wired) / total, Theme.mem.opacity(0.6), geo.size.width)
                seg(Double(m.compressed) / total, Theme.mem.opacity(0.35), geo.size.width)
                seg(Double(m.cached) / total, Theme.cache, geo.size.width)
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(Theme.track)
        .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
        .accessibilityHidden(true)
    }

    private func seg(_ f: Double, _ c: Color, _ w: CGFloat) -> some View {
        Rectangle().fill(c).frame(width: max(0, w * f - 1))
    }
}

struct MemoryPanel: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared

    var body: some View {
        let m = monitor.snapshot.memory
        let p = settings.prefs.memory
        let _ = monitor.tick
        PanelHeader(icon: Icons.memory, color: Theme.mem, title: L10n.Module.memory,
                    subtitle: L10n.Panel.memoryUsedOf(Format.memory(m.used), Format.memory(m.total))) {
            BigValue(number: percentParts(m.usedFraction), unit: "%", color: Theme.mem, size: 28, unitSize: 15)
        }
        if p.showComposition {
            PanelCard(padding: EdgeInsets(top: 4, leading: 12, bottom: 10, trailing: 12)) {
                PanelTitle(text: L10n.Panel.composition)
                MemoryComposition(m: m).padding(.top, 4)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible())], alignment: .leading, spacing: 5) {
                    legend(Theme.mem, L10n.Memory.app, m.app)
                    legend(Theme.mem.opacity(0.6), L10n.Memory.wired, m.wired)
                    legend(Theme.mem.opacity(0.35), L10n.Memory.compressed, m.compressed)
                    legend(Theme.cache, L10n.Memory.cached, m.cached)
                    legend(Theme.track, L10n.Memory.free, m.free, ring: true)
                }
                .font(.system(size: 11))
                .padding(.top, 10)
            }
        }
        if p.showPressure || p.showSwap {
            PanelCard(padding: EdgeInsets(top: 4, leading: 12, bottom: 0, trailing: 12)) {
                if p.showPressure {
                    let pr = PanelText.pressure(m.pressure)
                    HStack {
                        Text(L10n.Panel.pressure).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.sub)
                        Spacer()
                        StatusBadge(text: pr.0, fg: pr.1, bg: pr.2)
                    }
                    .frame(height: 24)
                    MiniChart(series: [.init(values: monitor.history.latest(.memoryPressure, seconds: 60).map { $0 / 100 }, color: pr.1)], gridLines: 2)
                        .frame(height: 40)
                        .padding(.top, 4)
                        .padding(.bottom, p.showSwap ? 8 : 10)
                        .accessibilityLabel(L10n.Panel.pressureChartA11y)
                }
                if p.showSwap {
                    if p.showPressure { Hairline() }
                    KVRow(key: L10n.Memory.swap, value: Format.memory(m.swapUsed))
                }
            }
        }
        if p.showProcesses {
            PanelProcessList(title: L10n.Panel.topUsage, processes: Array(monitor.snapshot.processes.byMemory.prefix(p.processCount)), metric: .memory, color: Theme.mem)
        }
    }

    private func legend(_ c: Color, _ label: String, _ bytes: UInt64, ring: Bool = false) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 7, height: 7)
                .overlay(Circle().strokeBorder(ring ? Theme.cache : .clear, lineWidth: 1))
            Text(label).foregroundStyle(Theme.sub)
            Spacer(minLength: 4)
            Text(Format.memory(bytes)).fontWeight(.semibold).monospacedDigit()
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
        let peak = max(down.max() ?? 0, up.max() ?? 0, 10_000)
        PanelHeader(icon: Icons.network, color: n.connected ? Theme.down : Theme.faint, title: L10n.Module.network, subtitle: PanelText.interface(n)) {
            if n.connected {
                VStack(alignment: .trailing, spacing: 2) {
                    speed(MenuBarText.downArrow, n.down, p.speedUnit, Theme.down, 20, 11)
                    speed(MenuBarText.upArrow, n.up, p.speedUnit, Theme.up, 13, 10)
                }
            } else {
                Text(L10n.Panel.notConnected).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.faint)
            }
        }
        PanelCard {
            MiniChart(series: [
                .init(values: down.map { $0 / peak }, color: Theme.down, fill: n.connected ? 0.14 : 0.1),
                .init(values: up.map { $0 / peak }, color: Theme.up, fill: 0),
            ], minCount: Int(seconds / max(settings.prefs.general.refreshInterval, 1)))
            .frame(height: 60)
            .accessibilityLabel(L10n.Panel.networkChartA11y)
            PanelLegend(items: [(Theme.down, L10n.Panel.download, nil), (Theme.up, L10n.Panel.upload, nil)], right: L10n.Range.lastSeconds(p.graphSeconds))
        }
        if !n.connected {
            PanelCard(padding: EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)) {
                HStack(spacing: 10) {
                    ZStack {
                        LineIcon(d: Icons.wifi, size: 16, lineWidth: 1.6).opacity(0.35)
                        LineIcon(d: Icons.slash, size: 16, lineWidth: 1.6)
                    }
                    .foregroundStyle(Theme.sub)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.chip))
                    Text(L10n.Panel.noConnection).fontWeight(.semibold)
                    Spacer()
                    Button(L10n.Panel.networkSettings) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.well))
                }
                .frame(height: 44)
            }
        }
        PanelCard(padding: EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)) {
            DividedRows {
                if n.connected {
                    KVRow(key: L10n.Network.localIP, value: n.localIP.isEmpty ? L10n.Common.dash : n.localIP)
                    if !n.router.isEmpty { KVRow(key: L10n.Network.router, value: n.router) }
                    if p.showPublicIP { KVRow(key: L10n.Network.publicIP, value: monitor.publicIP ?? L10n.Common.dash) }
                } else if let last = n.lastConnected {
                    KVRow(key: L10n.Network.lastConnected, value: Format.time(last))
                }
                KVRow(key: L10n.Network.today, value: L10n.Network.downUp(Format.storage(n.todayDown), Format.storage(n.todayUp)))
            }
        }
        if p.showProcesses && n.connected {
            PanelProcessList(title: L10n.Panel.topTraffic, processes: Array(monitor.snapshot.processes.byNetwork.prefix(5)), metric: .network, color: Theme.down)
        }
    }

    private func speed(_ arrow: String, _ v: Double, _ unit: SpeedUnit, _ c: Color, _ size: CGFloat, _ unitSize: CGFloat) -> some View {
        let parts = Format.rateParts(v, unit: unit)
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(arrow).font(Fonts.big(unitSize + 1))
            Text(parts.0).font(Fonts.big(size)).monospacedDigit()
            Text(parts.1).font(Fonts.big(unitSize))
        }
        .foregroundStyle(c)
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
        PanelHeader(icon: Icons.disk, color: Theme.disk, title: L10n.Module.disk, subtitle: L10n.Panel.volumeAvailable(volume?.name ?? L10n.Common.dash)) {
            let parts = Format.storage(volume?.available ?? 0).split(separator: " ").map(String.init)
            BigValue(number: parts.first ?? "", unit: parts.count > 1 ? parts[1] : "", color: Theme.disk, size: 28, unitSize: 13)
        }
        let volumes = p.showAllDisks ? d.volumes : (volume.map { [$0] } ?? [])
        if !volumes.isEmpty {
            PanelCard(padding: EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)) {
                DividedRows {
                    ForEach(volumes) { VolumeBlock(volume: $0) }
                }
            }
        }
        if p.showGraph {
            let read = monitor.history.latest(.diskRead, seconds: 60)
            let write = monitor.history.latest(.diskWrite, seconds: 60)
            let peak = max(read.max() ?? 0, write.max() ?? 0, 1_000_000)
            PanelCard(padding: EdgeInsets(top: 10, leading: 12, bottom: 0, trailing: 12)) {
                MiniChart(series: [
                    .init(values: read.map { $0 / peak }, color: Theme.read),
                    .init(values: write.map { $0 / peak }, color: Theme.write, fill: 0),
                ])
                .frame(height: 52)
                .accessibilityLabel(L10n.Panel.diskChartA11y)
                PanelLegend(items: [(Theme.read, L10n.Disk.read, Format.rate(d.read)), (Theme.write, L10n.Disk.write, Format.rate(d.write))], right: nil)
                Hairline().padding(.top, 8)
                KVRow(key: L10n.Disk.sinceBoot, value: L10n.Disk.readWriteTotals(Format.storage(d.totalRead), Format.storage(d.totalWritten)))
            }
        }
        if p.showProcesses {
            PanelProcessList(title: L10n.Panel.topDisk, processes: Array(monitor.snapshot.processes.byDisk.prefix(5)), metric: .disk, color: Theme.disk)
        }
    }
}

struct VolumeBlock: View {
    var volume: Volume

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(volume.name).fontWeight(.semibold).lineLimit(1)
                if !volume.isInternal {
                    Text(L10n.Disk.external)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.sub)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.chip))
                }
                Spacer(minLength: 4)
                Text(L10n.Disk.available(Format.storage(volume.available))).foregroundStyle(Theme.sub)
                if volume.isEjectable && !volume.isRoot {
                    Button {
                        try? NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
                    } label: {
                        Image(systemName: "eject.fill").font(.system(size: 9))
                            .frame(width: 20, height: 20)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.well))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.Disk.eject(volume.name))
                }
            }
            .frame(height: 20)
            MeterBar(fraction: volume.usedFraction, color: Theme.disk, height: 6).padding(.top, 6)
            Text(L10n.Disk.usedOf(Format.storage(volume.used), Format.storage(volume.total)))
                .font(.system(size: 11)).foregroundStyle(Theme.faint).padding(.top, 5)
        }
        .padding(.vertical, 9)
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
        PanelHeader(icon: Icons.battery, color: Theme.bat, title: L10n.Module.battery, subtitle: b.hasBattery ? PanelText.batteryStatus(b) : L10n.Battery.noBattery) {
            if b.hasBattery { BigValue(number: percentParts(b.level), unit: "%", color: Theme.bat, size: 28, unitSize: 15) }
        }
        if b.hasBattery {
            PanelCard {
                BigBatteryBar(level: b.level, color: b.level <= 0.2 && !b.onAC ? Theme.low : Theme.bat)
                let stats = batteryStats(b, p)
                if !stats.isEmpty {
                    Hairline().padding(.top, 10)
                    HStack(spacing: 8) { ForEach(stats, id: \.1) { StatBlock(value: $0.0, label: $0.1, valueSize: 15) } }
                        .padding(.top, 10)
                }
            }
            PanelCard(padding: EdgeInsets(top: 4, leading: 12, bottom: 10, trailing: 12)) {
                PanelTitle(text: L10n.Battery.level, right: L10n.Range.last24h)
                let pts = monitor.history.points(.battery, range: .h24)
                TimeChart(points: pts, range: .h24, color: Theme.bat, maxValue: 100)
                    .frame(height: 56)
                    .padding(.top, 4)
                    .accessibilityLabel(L10n.Panel.batteryChartA11y)
                HStack {
                    Text(L10n.Range.ago24h)
                    Spacer()
                    Text(L10n.Range.ago12h)
                    Spacer()
                    Text(L10n.Range.now)
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.faint)
                .padding(.top, 4)
            }
        }
        if p.showBluetooth || !b.hasBattery {
            PanelCard(padding: EdgeInsets(top: 2, leading: 12, bottom: 4, trailing: 12)) {
                PanelTitle(text: L10n.Battery.bluetooth)
                if monitor.bluetooth.isEmpty {
                    Text(L10n.Battery.noDevices).foregroundStyle(Theme.faint).frame(height: 30)
                }
                DividedRows {
                    ForEach(monitor.bluetooth) { DeviceRow(device: $0, compact: true) }
                    ForEach(b.ups) { UPSRow(source: $0, compact: true) }
                }
            }
        }
    }

    private func batteryStats(_ b: BatterySample, _ p: BatteryPrefs) -> [(String, String)] {
        var out: [(String, String)] = []
        if p.showHealth, let h = b.health { out.append((Format.percent(h), L10n.Battery.health)) }
        if p.showCycles, let c = b.cycles { out.append(("\(c)", L10n.Battery.cycles)) }
        if p.showPower {
            if b.isCharging, let w = b.power, w > 0 { out.append((Format.watts(w), L10n.Battery.chargingPower)) }
            else if !b.onAC, let w = b.power { out.append((Format.watts(abs(w)), L10n.Battery.power)) }
            if let a = b.adapterWatts, b.onAC { out.append(("\(a) W", L10n.Battery.adapterLabel)) }
        }
        return out
    }
}

struct BigBatteryBar: View {
    var level: Double
    var color: Color
    var height: CGFloat = 22

    var body: some View {
        HStack(spacing: 3) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Theme.rim, lineWidth: 1.5)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color)
                            .frame(width: max(2, (geo.size.width - 7) * min(1, max(0, level))))
                            .padding(3.5)
                    }
            }
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 2, topTrailingRadius: 2)
                .fill(Theme.rim)
                .frame(width: 3, height: height * 0.36)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct DeviceRow: View {
    var device: BluetoothDevice
    var compact = false

    var body: some View {
        let low = device.level <= 0.2
        HStack(spacing: 10) {
            IconChip(d: icon, size: compact ? 24 : 28, iconSize: 15, radius: 7, color: Theme.text, fill: Theme.chip, lineWidth: 1.4)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(device.name).lineLimit(1)
                    if low {
                        Text(L10n.Battery.low).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.dangerText)
                            .padding(.horizontal, 6).frame(height: 16)
                            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.dangerBg))
                    }
                }
                if let detail = device.detail { Text(detail).font(.system(size: 11)).foregroundStyle(Theme.sub).lineLimit(1) }
            }
            Spacer(minLength: 4)
            BatteryGlyph(level: device.level, fill: low ? Theme.low : Theme.bat, rim: Theme.rim)
            Text(Format.percent(device.level)).fontWeight(.semibold).monospacedDigit()
                .foregroundStyle(low ? Theme.dangerText : Theme.text)
                .frame(width: 40, alignment: .trailing)
        }
        .frame(height: compact ? 38 : 46)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch device.kind {
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
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            IconChip(d: Icons.ups, size: compact ? 24 : 28, iconSize: 15, radius: 7, color: Theme.text, fill: Theme.chip, lineWidth: 1.4)
            VStack(alignment: .leading, spacing: 0) {
                Text(source.name).lineLimit(1)
                Text(source.onAC ? (source.minutesLeft.map { L10n.Battery.upsDetail($0) } ?? L10n.Battery.upsOnAC) : L10n.Battery.onBattery)
                    .font(.system(size: 11)).foregroundStyle(Theme.sub).lineLimit(1)
            }
            Spacer(minLength: 4)
            BatteryGlyph(level: source.level, fill: Theme.bat, rim: Theme.rim)
            Text(Format.percent(source.level)).fontWeight(.semibold).monospacedDigit().frame(width: 40, alignment: .trailing)
        }
        .frame(height: compact ? 38 : 46)
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
        let headline = MenuBarText.sensorValue(s, p.sensor)
        PanelHeader(icon: Icons.sensors, color: Theme.temp, title: L10n.Module.sensors, subtitle: L10n.Sensors.choice(p.sensor)) {
            if let headline {
                BigValue(number: Format.temperatureNumber(headline, unit: unit), unit: "°", color: Theme.temp, size: 28, unitSize: 15)
            }
        }
        let th = PanelText.thermal(s.thermal)
        PanelCard(padding: EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)) {
            HStack {
                Text(L10n.Sensors.thermalState).foregroundStyle(Theme.sub)
                Spacer()
                StatusBadge(text: th.0, fg: th.1, bg: th.2)
            }
            .frame(height: 32)
        }
        if p.showAllTemps, !s.temps.isEmpty {
            PanelCard(padding: EdgeInsets(top: 2, leading: 12, bottom: 4, trailing: 12)) {
                PanelTitle(text: L10n.Sensors.temperatures)
                ForEach(s.temps) { t in
                    MeterRow(name: PanelText.tempName(t.group), fraction: t.value / 110, value: Format.temperature(t.value, unit: unit, showUnit: true), color: Theme.temp)
                        .overlay(alignment: .top) { Hairline() }
                }
            }
        }
        if p.showFans {
            if s.hasFans {
                PanelCard(padding: EdgeInsets(top: 2, leading: 12, bottom: 4, trailing: 12)) {
                    PanelTitle(text: L10n.Sensors.fans, right: s.fans.first.map { L10n.Sensors.maxRPM(Int($0.max)) })
                    ForEach(s.fans) { f in
                        MeterRow(name: PanelText.fanName(f.id, count: s.fans.count), fraction: f.max > 0 ? f.rpm / f.max : 0, value: Format.rpm(f.rpm), color: Theme.sub)
                            .overlay(alignment: .top) { Hairline() }
                    }
                }
            } else {
                PanelCard(padding: EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)) {
                    HStack {
                        Text(L10n.Sensors.fans).foregroundStyle(Theme.sub)
                        Spacer()
                        Text(L10n.Sensors.fanless).foregroundStyle(Theme.faint)
                    }
                    .frame(height: 32)
                }
            }
        }
        if p.showPower, s.systemPower != nil || s.cpuPower != nil || s.gpuPower != nil {
            PanelCard {
                HStack(spacing: 8) {
                    if let w = s.systemPower { StatBlock(value: Format.watts(w), label: L10n.Sensors.systemPower, valueSize: 15) }
                    if let w = s.cpuPower { StatBlock(value: Format.watts(w), label: L10n.Module.cpu, valueSize: 15) }
                    if let w = s.gpuPower { StatBlock(value: Format.watts(w), label: L10n.Module.gpu, valueSize: 15) }
                }
            }
        }
    }
}
