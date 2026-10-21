import AppKit
import SwiftUI

/// The "合并成一项" panel, for a glance: how things stand, a ring for each level, the network's
/// last minute, and the busiest processes. The details live on the overview page.
struct CombinedPanel: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    @State private var sortByMemory = false
    @State private var hovered: String?

    /// The modules shown; the monitor reads these while the panel is open.
    static let modules: [Module] = [.cpu, .memory, .network, .disk, .sensors, .bluetooth]

    var body: some View {
        let s = monitor.snapshot
        let prefs = settings.prefs
        let _ = monitor.tick
        let status = Status.now(s, prefs)
        VStack(alignment: .leading, spacing: 16) {
            // Her face and what she says about how things stand; the footer opens the overview.
            header(status)

            let gauges = self.gauges(s, prefs)
            // Bluetooth only shows while a device with a battery is connected.
            let bluetooth = prefs.isEnabled(.bluetooth) && !s.bluetooth.withBattery.isEmpty
            if !gauges.isEmpty || prefs.isEnabled(.network) || bluetooth {
                VStack(spacing: 8) {
                    if !gauges.isEmpty { gaugeRow(gauges) }
                    if prefs.isEnabled(.network) { networkBlock(s, prefs) }
                    if bluetooth { bluetoothBlock(s, prefs) }
                }
            }

            // As a module dropdown's list: the title, then the sort and "全部" on the right.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(L10n.Overview.topUsage).font(Fonts.ui(12, 500)).foregroundStyle(Theme.sub).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Segmented(label: L10n.Overview.sortBy, options: [(false, L10n.Module.cpu), (true, L10n.Module.memory)], selection: $sortByMemory, style: .tab)
                    AllProcessesLink(sort: sortByMemory ? .memory : .cpu)
                }
                .frame(height: 16)
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .padding(.bottom, 8)
                ProcessListPanel(processes: Array((sortByMemory ? s.processes.byMemory : s.processes.byCPU).prefix(5)),
                                 metric: sortByMemory ? .memory : .cpu, color: sortByMemory ? Theme.mem : Theme.cpu,
                                 rowHeight: 30, nameWidth: 110, valueWidth: 56, rowPadding: 8, fill: Theme.well, radius: 12)
            }
        }
    }

    private func header(_ status: Status) -> some View {
        HStack(spacing: 10) {
            AppMark(size: 34, mood: status.mood)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(L10n.App.name).ui(15, 600).accessibilityAddTraits(.isHeader)
                    Seal(size: 14)
                }
                .frame(height: 18)
                Text(status.line).ui(12).foregroundStyle(status.color).lineLimit(1)
                    .frame(height: 15)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.top, -2)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Gauges

    /// A ring in the top row: a level that has a whole to be part of.
    private struct Gauge: Identifiable {
        var id: String { module.rawValue }
        var module: Module
        var label: String
        var segments: [Ring.Segment]
        var text: String
        /// A state worth noticing, as a dot after the label.
        var dot: Color? = nil
    }

    private func gauges(_ s: Snapshot, _ prefs: Preferences) -> [Gauge] {
        var out: [Gauge] = []
        let on = prefs.isEnabled
        if on(.cpu) {
            out.append(Gauge(module: .cpu, label: Module.cpu.title,
                             segments: [.init(fraction: s.cpu.system, color: Theme.sys), .init(fraction: s.cpu.user, color: Theme.cpu)],
                             text: Format.percent(s.cpu.total)))
        }
        if on(.memory) {
            let pr = s.memory.pressure
            out.append(Gauge(module: .memory, label: Module.memory.title, segments: MemoryRing.segments(s.memory),
                             text: Format.percent(s.memory.usedFraction), dot: pr == .normal ? nil : PanelText.pressure(pr).1))
        }
        if on(.disk) {
            let used = s.disk.root?.usedFraction ?? 0
            out.append(Gauge(module: .disk, label: Module.disk.title, segments: [.init(fraction: used, color: Theme.disk)],
                             text: Format.percent(used)))
        }
        if on(.sensors) {
            let cpu = s.sensors.cpuAverage
            let color = TempZone.color(cpu ?? 0)
            // The CPU's temperature around a 0–100 °C ring, in its zone's color.
            out.append(Gauge(module: .sensors, label: L10n.Panel.temperature,
                             segments: [.init(fraction: (cpu ?? 0) / 100, color: color)],
                             text: cpu.map { Format.temperature($0, unit: prefs.general.temperatureUnit) } ?? L10n.Common.dash,
                             dot: cpu.flatMap { $0 >= 90 ? color : nil }))
        }
        return out
    }

    /// The rings side by side, each the same size, its name underneath.
    private func gaugeRow(_ gauges: [Gauge]) -> some View {
        HStack(spacing: 0) {
            ForEach(gauges) { g in
                button(g.id, opens: g.module) {
                    VStack(spacing: 8) {
                        PageRing(segments: g.segments, size: 54, lineWidth: 4, text: g.text, textSize: 13)
                        HStack(spacing: 4) {
                            Text(g.label).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
                            if let dot = g.dot { Circle().fill(dot).frame(width: 6, height: 6) }
                        }
                        .frame(height: 16)
                    }
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Theme.well)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Network

    /// Download over upload on the left, the last minute of both on the right.
    private func networkBlock(_ s: Snapshot, _ prefs: Preferences) -> some View {
        let n = s.network
        let unit = prefs.network.speedUnit
        let seconds = 60 * prefs.refresh(.network)
        let down = monitor.history.latest(.netDown, seconds: seconds)
        let up = monitor.history.latest(.netUp, seconds: seconds)
        // Both against one recent peak, so they compare; a floor keeps a trickle low.
        let peak = max(down.max() ?? 0, up.max() ?? 0, 10_000) * 1.1
        return button(Module.network.rawValue, opens: .network) {
            HStack(spacing: 14) {
                VStack(spacing: 6) {
                    rate(MenuBarText.downArrow, Theme.down, L10n.Panel.download, n.connected ? Format.rateParts(n.down, unit: unit) : nil)
                    rate(MenuBarText.upArrow, Theme.up, L10n.Panel.upload, n.connected ? Format.rateParts(n.up, unit: unit) : nil)
                }
                .frame(width: 128)
                MiniChart(series: [.init(values: down.map { $0 / peak }, color: Theme.down, fill: 0.13, lineWidth: 1.25),
                                   .init(values: up.map { $0 / peak }, color: Theme.up, fill: 0, lineWidth: 1)],
                          gridLines: 1, minCount: 60)
                    .frame(height: 40)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Theme.well)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func rate(_ arrow: String, _ color: Color, _ label: String, _ parts: (String, String)?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(arrow).ui(12, 500).foregroundStyle(color)
            Text(label).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
            Spacer(minLength: 4)
            Text(parts?.0 ?? L10n.Common.dash).ui(13, 500).lineLimit(1)
            if let unit = parts?.1 { Text(unit).ui(12).foregroundStyle(Theme.sub).lineLimit(1) }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Bluetooth

    /// Devices that report a battery, the lowest first: name, a level bar, the percentage.
    private func bluetoothBlock(_ s: Snapshot, _ prefs: Preferences) -> some View {
        let devices = s.bluetooth.withBattery.sorted { ($0.level ?? 1) < ($1.level ?? 1) }
        return button(Module.bluetooth.rawValue, opens: .bluetooth) {
            VStack(spacing: 6) {
                ForEach(devices.prefix(4)) { d in
                    let low = BluetoothText.isLow(d, prefs)
                    let level = d.level ?? 0
                    // Columns as the process list's below: icon, name, bar, value.
                    HStack(spacing: 10) {
                        LineIcon(d: Icons.device(d.kind), size: 14, lineWidth: 1.3).foregroundStyle(Theme.sub).frame(width: 18)
                        Text(d.name).ui(12).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                        MeterBar(fraction: level, color: low ? Theme.danger : Theme.bat).frame(width: 50)
                        HStack(spacing: 2) {
                            if d.charging { FilledIcon(d: Icons.chargingBolt, width: 8, height: 11).foregroundStyle(Theme.bat) }
                            Text(Format.percent(level)).ui(13, 500)
                        }
                        .foregroundStyle(low ? Theme.danger : Theme.text)
                        .frame(width: 56, alignment: .trailing)
                    }
                    .frame(height: 20)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Theme.well)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Opens a module's page; tints under the pointer.
    private func button<Content: View>(_ id: String, opens module: Module, @ViewBuilder content: () -> Content) -> some View {
        Button {
            MainWindowController.shared.show(.monitor(module))
        } label: {
            content()
                .background(hovered == id ? Theme.well : .clear)
                .hoverAnimation(hovered == id)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = id } else if hovered == id { hovered = nil }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.Panel.openMonitor(module.title))
    }
}
