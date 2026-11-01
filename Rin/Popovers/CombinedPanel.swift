import AppKit
import SwiftUI

/// The "合并成一项" dropdown, for a glance: her face and how things stand, then a grouped list with
/// a row for each module in the order set in 设置 › 菜单栏 (its last minute, the reading), and a
/// second group with the busiest apps and what keeps the Mac awake while something does. Every
/// row opens its page.
struct CombinedPanel: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    @State private var blockers: [SleepBlocker] = []

    var body: some View {
        let s = monitor.snapshot
        let prefs = settings.prefs
        let _ = monitor.tick
        let bar = prefs.menubar
        let modules = prefs.combinedModules.filter { hasReading($0, s) }
        let busiest = bar.combinedTop ? Array((bar.combinedTopByMemory ? s.processes.byMemory : s.processes.byCPU).prefix(3)) : []
        let awake = bar.combinedSleep ? blockers : []
        VStack(alignment: .leading, spacing: 12) {
            header(Status.now(s, prefs), line: bar.combinedStatus)
            if !modules.isEmpty {
                RowGroup {
                    ForEach(modules) { ModuleRow(module: $0) }
                }
            }
            if !busiest.isEmpty || !awake.isEmpty {
                RowGroup {
                    if !busiest.isEmpty { TopRow(processes: busiest, byMemory: bar.combinedTopByMemory) }
                    if !awake.isEmpty { SleepRow(blockers: awake) }
                }
            }
            CombinedFooter()
        }
        .task(id: bar.combinedSleep) {
            guard bar.combinedSleep else { return }
            // Assertions come and go with playback and syncing; re-read while the dropdown is open.
            while !Task.isCancelled {
                blockers = Self.appBlockers()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onAppear { if RenderContext.offscreen { blockers = Self.appBlockers() } }
    }

    /// Apps and processes holding the Mac awake; not macOS itself, and not Rin's own keep-awake.
    static func appBlockers() -> [SleepBlocker] {
        let me = ProcessInfo.processInfo.processIdentifier
        return SleepBlocker.read().filter { b in
            switch b.owner {
            case .app(let app): return app.processIdentifier != me
            case .process: return true
            case .system: return false
            }
        }
    }

    /// A module with nothing to show leaves no card: no battery, no device reporting one.
    private func hasReading(_ m: Module, _ s: Snapshot) -> Bool {
        switch m {
        case .battery: return s.battery.hasBattery
        case .bluetooth: return !s.bluetooth.withBattery.isEmpty
        case .sensors: return s.sensors.cpuAverage != nil
        default: return true
        }
    }

    private func header(_ status: Status, line: Bool) -> some View {
        HStack(spacing: 10) {
            AppMark(size: 30, mood: status.mood)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.App.name).ui(16, 600).accessibilityAddTraits(.isHeader)
                if line {
                    HStack(spacing: 6) {
                        Circle().fill(status.color).frame(width: 6, height: 6)
                        Text(status.line).ui(14).lineLimit(1).truncationMode(.tail)
                    }
                    .foregroundStyle(status.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            CombinedLink(title: L10n.Sidebar.overview) { MainWindowController.shared.show(.overview) }
        }
    }
}

// MARK: - Rows

/// A group of rows on one panel-toned block, ruled between rows (as a grouped list in Settings).
private struct RowGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { RuledRows { content } }
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// A whole row that opens a page, tinted under the pointer.
private struct RowButton<Content: View>: View {
    var height: CGFloat = 50
    var hint: String
    var action: () -> Void
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) { content }
                .padding(.horizontal, 12)
                .frame(height: height)
                .background { if hovering { Theme.lgHover } }
                .hoverAnimation(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityHint(hint)
    }
}

/// Icon, name over one detail, the last minute, the reading.
private struct ModuleRow: View {
    let module: Module
    var monitor = Monitor.shared
    var settings = SettingsStore.shared

    var body: some View {
        let s = monitor.snapshot
        let prefs = settings.prefs
        RowButton(hint: L10n.Panel.openMonitor(module.title)) {
            MainWindowController.shared.show(.monitor(module))
        } content: {
            LineIcon(d: Icons.module(module), size: 18, lineWidth: 1.5)
                .foregroundStyle(module == .bluetooth ? Theme.neutral : Theme.color(for: module))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(module == .sensors ? L10n.Panel.temperature : module.title).ui(14, 500).lineLimit(1)
                Text(detail(s, prefs)).ui(12).foregroundStyle(Theme.sub).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            chart(s, prefs).frame(width: 60, height: 24)
            reading(s, prefs).frame(width: 80, alignment: .trailing)
        }
    }

    private func detail(_ s: Snapshot, _ prefs: Preferences) -> String {
        switch module {
        case .cpu: return L10n.Panel.coreCount(SystemInfo.coreCount)
        case .gpu: return s.gpu.cores > 0 ? L10n.Panel.coreCount(s.gpu.cores) : s.gpu.model
        case .memory: return Format.memory(used: s.memory.used, of: s.memory.total)
        case .network: return s.network.connected ? PanelText.kindName(s.network.kind) : PanelText.interface(s.network)
        case .disk:
            guard let root = s.disk.root else { return L10n.Common.dash }
            let free = Format.parts(Format.storage(root.available))
            return free.0 + " " + L10n.Monitor.unitFree(free.1)
        case .battery: return PanelText.batteryState(s.battery)
        case .bluetooth: return lowestDevice(s)?.name ?? L10n.Common.dash
        case .sensors:
            if let fan = s.sensors.fans.first { return Format.rpm(fan.rpm) }
            return PanelText.thermal(s.sensors.thermal).0
        }
    }

    private func lowestDevice(_ s: Snapshot) -> BluetoothDevice? {
        s.bluetooth.withBattery.min { ($0.level ?? 1) < ($1.level ?? 1) }
    }

    @ViewBuilder private func reading(_ s: Snapshot, _ prefs: Preferences) -> some View {
        switch module {
        case .cpu: BigValue(value: Format.percent(s.cpu.total), size: 22, color: Theme.cpu)
        case .gpu: BigValue(value: Format.percent(s.gpu.utilization), size: 22, color: Theme.gpu)
        case .memory: BigValue(value: Format.percent(s.memory.usedFraction), size: 22, color: Theme.mem)
        case .disk: BigValue(value: s.disk.root.map { Format.percent($0.usedFraction) } ?? L10n.Common.dash, size: 22, color: Theme.disk)
        case .battery: BigValue(value: Format.percent(s.battery.level), size: 22)
        case .sensors:
            BigValue(value: s.sensors.cpuAverage.map { Format.temperature($0, unit: prefs.general.temperatureUnit) } ?? L10n.Common.dash, size: 22, color: Theme.temp)
        case .bluetooth:
            let d = lowestDevice(s)
            BigValue(value: d?.level.map { Format.percent($0) } ?? L10n.Common.dash, size: 22,
                     color: d.map { BluetoothText.isLow($0, prefs) } == true ? Theme.danger : Theme.text)
        case .network:
            // Both directions of one reading, so they look the same.
            let n = s.network, unit = prefs.network.speedUnit
            VStack(alignment: .trailing, spacing: 2) {
                Text(MenuBarText.downArrow + " " + (n.connected ? Format.rate(n.down, unit: unit) : L10n.Common.dash))
                Text(MenuBarText.upArrow + " " + (n.connected ? Format.rate(n.up, unit: unit) : L10n.Common.dash))
            }
            .ui(14, 500)
            .foregroundStyle(Theme.down)
            .lineLimit(1)
            .fixedSize()
        }
    }

    /// The last minute as a small area chart (a stack for the CPU, mirrored for traffic).
    @ViewBuilder private func chart(_ s: Snapshot, _ prefs: Preferences) -> some View {
        if module == .bluetooth {
            let d = lowestDevice(s)
            LevelBar(fraction: d?.level ?? 0, color: d.map { BluetoothText.isLow($0, prefs) } == true ? Theme.danger : Theme.neutral)
        } else {
            plot.accessibilityHidden(true)
        }
    }

    @ViewBuilder private var plot: some View {
        let h = monitor.history
        switch module {
        case .cpu:
            spark(.area, ChartSeries.cpuStack(total: h.points(.cpu, range: .m5), system: h.points(.cpuSystem, range: .m5)))
        case .gpu:
            spark(.area, [ChartSeries(id: "g", points: h.points(.gpu, range: .m5), color: Theme.gpu, fill: 0.2, lineWidth: 1.5)])
        case .memory:
            spark(.area, [ChartSeries(id: "p", points: h.points(.memoryPressure, range: .m5), color: Theme.mem, fill: 0.18, lineWidth: 1.5)])
        case .sensors:
            spark(.area, [ChartSeries(id: "t", points: h.points(.cpuTemp, range: .m5), color: Theme.temp, fill: 0.16, lineWidth: 1.5)])
        case .battery:
            spark(.area, [ChartSeries(id: "b", points: h.points(.battery, range: .m5), color: Theme.bat, fill: 0.14, lineWidth: 1.5)])
        case .network:
            mirrored(h.points(.netDown, range: .m5), Theme.down, h.points(.netUp, range: .m5), Theme.up, floor: 10_000)
        case .disk:
            mirrored(h.points(.diskRead, range: .m5), Theme.read, h.points(.diskWrite, range: .m5), Theme.write, floor: 1_000_000)
        case .bluetooth:
            EmptyView()
        }
    }

    private func spark(_ kind: ConsoleChart.Kind, _ series: [ChartSeries]) -> some View {
        ConsoleChart(kind: kind, series: series, span: 60, maxValue: 100, height: 24, xLabels: nil, grid: [], baseline: false, midline: false)
    }

    /// Up against its own last-minute peak, down against its own; a floor keeps a trickle low.
    private func mirrored(_ top: [ChartPoint], _ topColor: Color, _ bottom: [ChartPoint], _ bottomColor: Color, floor: Double) -> some View {
        let from = Date().addingTimeInterval(-60)
        func peak(_ points: [ChartPoint]) -> Double {
            ConsoleChart.niceMax(max(points.filter { $0.date >= from }.map(\.value).max() ?? 0, floor) * 1.1)
        }
        return ConsoleChart(kind: .mirroredArea, series: ChartSeries.mirrored(top, topColor, bottom, bottomColor),
                            span: 60, maxValue: peak(top), bottomMax: peak(bottom), height: 24, xLabels: nil, grid: [], baseline: false, midline: false)
    }
}

/// The busiest apps folded into one row: the first by name and figure, their icons stacked.
private struct TopRow: View {
    var processes: [ProcessUsage]
    var byMemory: Bool

    var body: some View {
        RowButton(hint: L10n.Sidebar.processes) {
            MainWindowController.shared.showProcesses(sortedBy: byMemory ? .memory : .cpu)
        } content: {
            LineIcon(d: Icons.processes, size: 18, lineWidth: 1.5).foregroundStyle(Theme.sub).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.Overview.topUsage).ui(14, 500).lineLimit(1)
                if let first = processes.first {
                    Text(byMemory ? L10n.Combined.topMemory(first.name, Format.memory(first.memory))
                                  : L10n.Combined.topCPU(first.name, Format.percentValue(first.cpu)))
                        .ui(12).foregroundStyle(Theme.sub).lineLimit(1).truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: -4) {
                ForEach(processes) { p in
                    ProcessIcon(process: p, size: 20)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.panel).padding(-2))
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// What keeps the Mac awake: the first app by name, how many more.
private struct SleepRow: View {
    var blockers: [SleepBlocker]

    var body: some View {
        RowButton(height: 42, hint: L10n.Sidebar.sleep) {
            MainWindowController.shared.show(.sleep)
        } content: {
            LineIcon(d: Icons.cup, size: 16, lineWidth: 1.5).foregroundStyle(Theme.warn).frame(width: 18)
            Text(L10n.Combined.blockingSleep(name(blockers[0]))).ui(14).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if blockers.count > 1 {
                Text(L10n.Combined.more(blockers.count - 1)).ui(14).foregroundStyle(Theme.sub)
            }
        }
    }

    private func name(_ b: SleepBlocker) -> String {
        switch b.owner {
        case .app(let app): return app.localizedName ?? ""
        case .process(let name, _): return name
        case .system: return L10n.Sleep.macOS
        }
    }
}

// MARK: - Header link and footer

/// "概览 ›": text with a chevron, tinted under the pointer.
private struct CombinedLink: View {
    var title: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).ui(14)
                LineIcon(d: Icons.chevronSmallRight, size: 12, viewBox: 12, lineWidth: 1.6).frame(width: 8)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background { if hovering { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.lgHover) } }
            .hoverAnimation(hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// "设置…" on the left; keep awake, pause and quit on the right.
private struct CombinedFooter: View {
    var monitor = Monitor.shared
    var keepAwake = KeepAwake.shared

    var body: some View {
        HStack(spacing: 2) {
            FooterLabelButton(title: L10n.Combined.settings) { MainWindowController.shared.show(.menuBar) }
            Spacer(minLength: 0)
            FooterIconButton(d: Icons.cup, label: L10n.Sleep.keepAwake, on: keepAwake.isOn) {
                if keepAwake.isOn { keepAwake.stop() } else { keepAwake.start(keepAwake.mode) }
            }
            FooterIconButton(d: monitor.isPaused ? Icons.play : Icons.pause, lineWidth: monitor.isPaused ? 1.5 : 1.8,
                             label: monitor.isPaused ? L10n.Sidebar.resume : L10n.Sidebar.pause) { monitor.togglePause() }
            Rectangle().fill(Theme.grid).frame(width: 1, height: 16).padding(.horizontal, 4)
            FooterIconButton(d: Icons.power, label: L10n.Menu.quit) { NSApp.terminate(nil) }
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { ConsoleRule() }
    }
}

private struct FooterLabelButton: View {
    var title: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                LineIcon(d: Icons.gear, size: 16, lineWidth: 1.3)
                Text(title).ui(14)
            }
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .frame(height: 28)
            .background { if hovering { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.lgHover) } }
            .hoverAnimation(hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct FooterIconButton: View {
    var d: String
    var lineWidth: CGFloat = 1.5
    var label: String
    var on = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            LineIcon(d: d, size: 16, lineWidth: lineWidth)
                .foregroundStyle(on ? Theme.text : Theme.sub)
                .frame(width: 30, height: 28)
                .background {
                    if on || hovering { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Theme.selection : Theme.lgHover) }
                }
                .hoverAnimation(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}
