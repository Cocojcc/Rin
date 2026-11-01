import SwiftUI

/// Every module at a glance, four to a row: its name, a big reading, a small graphic that suits
/// the data (a line for rates, a fill for capacities, a bar per Bluetooth device) and a line of
/// detail, each in the module's own hue; a tile opens its page. Under them, the apps using the most CPU and memory.
struct OverviewPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    var alerts = Alerts.shared
    var navigator = Navigator.shared

    var body: some View {
        let s = monitor.snapshot
        let _ = monitor.tick
        let modules = Sidebar.moduleOrder.filter(settings.prefs.isEnabled)
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: L10n.Overview.title, spec: Format.uptime(since: SystemInfo.bootTime)) {
                if let event = alerts.current {
                    Button { alerts.show(event) } label: { Attention(text: AlertText.headline(event)).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .help(L10n.Alerts.view)
                }
                KeyValue(label: L10n.Monitor.processesLabel, value: grouped(s.processes.processCount), size: 13)
            }
            if modules.isEmpty {
                Text(L10n.Overview.allOff).ui(14).foregroundStyle(Theme.sub).padding(.top, 20)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .topLeading), count: 4), alignment: .leading, spacing: 8) {
                    ForEach(modules) { tile($0, s) }
                }
                .padding(.horizontal, -16)
                .padding(.top, 20)
            }
            Columns(gap: 44) {
                VStack(alignment: .leading, spacing: 0) {
                    HeadRow(title: L10n.Monitor.topCPU) { AllProcessesLink(sort: .cpu) }
                    ProcessTable(processes: Array(s.processes.byCPU.prefix(5)), value: { Format.percentValue($0.cpu) }, rowHeight: 34, minRows: 5)
                }
            } b: {
                VStack(alignment: .leading, spacing: 0) {
                    HeadRow(title: L10n.Monitor.topMemory) { AllProcessesLink(sort: .memory) }
                    ProcessTable(processes: Array(s.processes.byMemory.prefix(5)), value: { Format.memory($0.memory) }, rowHeight: 34, minRows: 5)
                }
            }
            .padding(.top, 26)
        }
    }

    // MARK: Tiles

    private var range: TimeRange { navigator.overviewRange }

    private func spark(_ metric: Metric, _ color: Color) -> some View {
        ConsoleChart(kind: .area, series: ChartSeries.line(monitor.history.points(metric, range: range), color, width: 1.5, fill: false),
                     range: range, maxValue: 100, height: 28, gutter: 0, showTimes: false)
            .allowsHitTesting(false)
    }

    /// A tile's reading: the module's hue, red while one of its alerts is on.
    private func lead(_ m: Module, _ kind: Alerts.Rule) -> Color {
        alerts.firing(kind) == nil ? Theme.color(for: m) : Theme.danger
    }

    @ViewBuilder private func tile(_ m: Module, _ s: Snapshot) -> some View {
        let unit = settings.prefs.general.temperatureUnit
        switch m {
        case .cpu:
            OverviewTile(module: m) {
                BigValue(value: Format.percentNumber(s.cpu.total), unit: "%", size: 36, color: lead(m, .cpu))
            } visual: {
                spark(.cpu, Theme.color(for: m))
            } foot: {
                KeyValues(pairs: [(L10n.Panel.user, Format.percent(s.cpu.user)), (L10n.Panel.system, Format.percent(s.cpu.system))])
            }
        case .gpu:
            OverviewTile(module: m) {
                BigValue(value: Format.percentNumber(s.gpu.utilization), unit: "%", size: 36, color: lead(m, .gpu))
            } visual: {
                spark(.gpu, Theme.color(for: m))
            } foot: {
                KeyValue(label: L10n.Panel.vram, value: Format.memory(s.gpu.memoryUsed))
            }
        case .memory:
            let mem = s.memory
            OverviewTile(module: m) {
                BigValue(value: Format.percentNumber(mem.usedFraction), unit: "%", size: 36, color: Theme.color(for: m))
            } visual: {
                LevelBar(fraction: mem.usedFraction, color: mem.pressure == .normal ? Theme.color(for: m) : PanelText.pressure(mem.pressure).1)
            } foot: {
                KeyValue(label: L10n.Monitor.usedLabel, value: L10n.Monitor.usedSlash(Format.memory(mem.used), Format.memoryTotal(mem.total)))
            }
        case .network:
            let n = s.network
            let speed = settings.prefs.network.speedUnit
            let down = monitor.history.points(.netDown, range: range), up = monitor.history.points(.netUp, range: range)
            let d = Format.rateParts(n.down, unit: speed)
            OverviewTile(module: m) {
                BigValue(value: n.connected ? d.0 : L10n.Common.dash, unit: n.connected ? d.1 + " " + MenuBarText.downArrow : nil, size: 36, color: Theme.color(for: m))
            } visual: {
                ConsoleChart(kind: .mirroredArea, series: ChartSeries.mirrored(down, Theme.color(for: m), up, Theme.color(for: m), lineWidth: 1.3),
                             range: range, maxValue: ConsoleChart.niceMax(Swift.max(down.map(\.value).max() ?? 0, 10_000) * 1.1),
                             bottomMax: ConsoleChart.niceMax(Swift.max(up.map(\.value).max() ?? 0, 10_000) * 1.1), height: 28, gutter: 0, showTimes: false)
                    .allowsHitTesting(false)
            } foot: {
                if n.connected {
                    KeyValue(label: MenuBarText.upArrow, value: Format.rate(n.up, unit: speed))
                } else {
                    Text(L10n.Overview.disconnected).foregroundStyle(Theme.sub)
                }
            }
        case .disk:
            let root = s.disk.root
            let free = Format.parts(Format.storage(root?.available ?? 0))
            OverviewTile(module: m) {
                BigValue(value: free.0, unit: L10n.Monitor.unitFree(free.1), size: 36, color: lead(m, .disk))
            } visual: {
                LevelBar(fraction: root?.usedFraction ?? 0, color: Theme.color(for: m))
            } foot: {
                KeyValue(label: L10n.Monitor.readWriteTitle, value: L10n.Monitor.readWritePair(Format.parts(Format.rate(s.disk.read)).0, Format.rate(s.disk.write)))
            }
        case .battery:
            let b = s.battery
            OverviewTile(module: m) {
                BigValue(value: b.hasBattery ? Format.percentNumber(b.level) : L10n.Common.dash, unit: b.hasBattery ? "%" : nil, size: 36,
                         color: b.hasBattery && b.level <= 0.2 && !b.onAC ? Theme.danger : Theme.text)
            } visual: {
                if b.hasBattery { LevelBar(fraction: b.level, color: Theme.batteryLevel(b, lead: false)) }
            } foot: {
                Text(b.hasBattery ? PanelText.batteryState(b) : L10n.Battery.noBattery).foregroundStyle(Theme.sub)
            }
        case .bluetooth:
            let devices = s.bluetooth.withBattery
            let low = devices.filter { BluetoothText.isLow($0, settings.prefs) }.sorted { ($0.level ?? 1) < ($1.level ?? 1) }
            OverviewTile(module: m) {
                BigValue(value: "\(s.bluetooth.connected.count)", unit: L10n.Overview.devicesConnected, size: 36)
            } visual: {
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(devices) { d in
                        let isLow = BluetoothText.isLow(d, settings.prefs)
                        Capsule().fill(Theme.track).frame(width: 4, height: 28)
                            .overlay(alignment: .bottom) { Capsule().fill(isLow ? Theme.danger : Theme.mid).frame(height: max(2, 28 * (d.level ?? 0))) }
                            .help(L10n.Bluetooth.deviceLevel(d.name, Format.percent(d.level ?? 0)))
                    }
                }
            } foot: {
                if let first = low.first {
                    Attention(text: L10n.Bluetooth.deviceLevel(first.name, Format.percent(first.level ?? 0)), size: 12).foregroundStyle(Theme.text)
                } else if devices.isEmpty {
                    Text(L10n.Bluetooth.noDevices).foregroundStyle(Theme.sub)
                }
            }
        case .sensors:
            let t = s.sensors
            OverviewTile(module: m) {
                BigValue(value: t.cpuAverage.map { Format.temperatureNumber($0, unit: unit) } ?? L10n.Common.dash, unit: Format.temperatureSymbol(unit), size: 36,
                         color: lead(m, .temperature))
            } visual: {
                spark(.cpuTemp, Theme.color(for: m))
            } foot: {
                if let f = t.fans.first {
                    KeyValue(label: L10n.Overview.fan, value: Format.rpm(f.rpm))
                } else if let w = t.systemPower {
                    KeyValue(label: L10n.Panel.power, value: Format.watts(w))
                }
            }
        }
    }
}

/// One module on the overview: name, reading, a 28 tall graphic and a line of detail; the whole
/// tile opens the module's page and greys under the pointer.
private struct OverviewTile<Value: View, Visual: View, Foot: View>: View {
    let module: Module
    @ViewBuilder var value: Value
    @ViewBuilder var visual: Visual
    @ViewBuilder var foot: Foot
    @State private var hovering = false

    var body: some View {
        Button { Navigator.shared.page = .monitor(module) } label: {
            VStack(alignment: .leading, spacing: 0) {
                SmallLabel(text: module.title)
                value.padding(.top, 8)
                visual.frame(maxWidth: .infinity, alignment: .bottomLeading).frame(height: 28, alignment: .bottom).padding(.top, 12)
                HStack(spacing: 0) { foot }.ui(12).lineLimit(1).frame(height: 16, alignment: .leading).padding(.top, 10)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background { if hovering { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lgHover) } }
            .hoverAnimation(hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.Panel.openMonitor(module.title))
    }
}
