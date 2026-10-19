import AppKit
import SwiftUI

/// The "合并成一项" panel: every module on one sheet split by hairlines, then the busiest
/// processes.
struct CombinedPanel: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    @State private var sortByMemory = false
    @State private var hovered: Module?

    /// The modules on the sheet, in order; the monitor reads these while the panel is open.
    static let modules: [Module] = [.cpu, .memory, .network, .disk, .sensors]

    /// Cell padding; the second column's readouts line up with it in the full-width cells.
    private static let inset: CGFloat = 14

    var body: some View {
        let s = monitor.snapshot
        let prefs = settings.prefs
        let _ = monitor.tick
        VStack(alignment: .leading, spacing: 16) {
            PanelHeader(title: L10n.Overview.title, subtitle: L10n.Panel.updatedEvery(Int(prefs.refresh(.cpu))),
                        openLabel: L10n.Panel.openOverview, open: { MainWindowController.shared.show(.overview) },
                        settingsLabel: L10n.Menu.settings, settings: { MainWindowController.shared.show(.settings) })

            sheet(s, prefs)

            PanelSection(title: L10n.Overview.topUsage) {
                ProcessListPanel(processes: Array((sortByMemory ? s.processes.byMemory : s.processes.byCPU).prefix(3)),
                                 metric: sortByMemory ? .memory : .cpu, color: sortByMemory ? Theme.mem : Theme.cpu,
                                 rowHeight: 30, nameWidth: 120, valueWidth: 64, rowPadding: 8, fill: Theme.well, radius: 12)
            }
            .overlay(alignment: .topTrailing) {
                Segmented(label: L10n.Overview.sortBy, options: [(false, L10n.Module.cpu), (true, L10n.Module.memory)], selection: $sortByMemory, style: .tab)
                    .padding(.trailing, 4)
                    .offset(y: -6)
            }

            HStack(spacing: 0) {
                FooterLink(title: L10n.Panel.openActivityMonitor) {
                    ProcessActions.openActivityMonitor()
                    PanelController.shared.close()
                }
                Spacer(minLength: 0)
                HeaderButton(d: Icons.power, label: L10n.Menu.quit) { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 6)
            .padding(.top, -6)
        }
    }

    // MARK: - Sheet

    /// Rows of one or two cells. A switched-off module leaves; the cell beside it takes the row.
    private func sheet(_ s: Snapshot, _ prefs: Preferences) -> some View {
        let on = prefs.isEnabled
        let rows: [[Module]] = [
            [Module.cpu, .memory].filter(on),
            on(.network) ? [.network] : [],
            [Module.disk, .sensors].filter(on),
        ].filter { !$0.isEmpty }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                if i > 0 { Hairline().padding(.horizontal, Self.inset) }
                HStack(spacing: 0) {
                    ForEach(row, id: \.self) { m in
                        cell(m, wide: row.count == 1, s, prefs)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(Theme.well)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func cell(_ m: Module, wide: Bool, _ s: Snapshot, _ prefs: Preferences) -> some View {
        Button {
            MainWindowController.shared.show(.monitor(m))
        } label: {
            VStack(alignment: .leading, spacing: 0) { content(m, wide: wide, s, prefs) }
                .padding(EdgeInsets(top: 12, leading: Self.inset, bottom: 13, trailing: Self.inset))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(hovered == m ? Theme.well : .clear)
                .hoverAnimation(hovered == m)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = m } else if hovered == m { hovered = nil }
        }
        .accessibilityHint(L10n.Panel.openMonitor(m.title))
    }

    @ViewBuilder private func content(_ m: Module, wide: Bool, _ s: Snapshot, _ prefs: Preferences) -> some View {
        switch m {
        case .cpu:
            label(.cpu)
            readout(percentNumber(s.cpu.total), L10n.Common.percentSign)
            graphic(height: 14) {
                HistoryBars(values: monitor.history.latest(.cpu, seconds: 40 * prefs.refresh(.cpu)).map { $0 / 100 }, color: Theme.cpu,
                            count: wide ? 60 : 30)
            }
            caption(L10n.Panel.userSystemShort(Format.percent(s.cpu.user), Format.percent(s.cpu.system)))
        case .memory:
            let pr = PanelText.pressure(s.memory.pressure)
            label(.memory, detail: pr.0, color: pr.1)
            readout(String(format: "%.1f", Double(s.memory.used) / 1_073_741_824), L10n.Panel.ofTotal(Format.memory(s.memory.total)))
            graphic { MemoryComposition(m: s.memory, height: 3, gap: 2) }
            ViewThatFits(in: .horizontal) {
                caption(L10n.Panel.memoryAppWired(Format.memory(s.memory.app), Format.memory(s.memory.wired)))
                caption(L10n.Panel.memoryApp(Format.memory(s.memory.app)))
            }
        case .network:
            network(s, prefs)
        case .disk:
            let root = s.disk.root
            let free = Format.storage(root?.available ?? 0).split(separator: " ").map(String.init)
            label(.disk)
            readout(free.first ?? "", L10n.Panel.unitAvailable(free.count > 1 ? free[1] : ""))
            graphic { MeterBar(fraction: root?.usedFraction ?? 0, color: Theme.disk) }
            caption(L10n.Panel.readWriteShort(Format.rate(s.disk.read), Format.rate(s.disk.write)))
        case .sensors:
            if wide { sensors(s, prefs.general.temperatureUnit) } else { temperature(s, prefs.general.temperatureUnit) }
        case .gpu, .battery, .bluetooth:
            EmptyView()
        }
    }

    /// Download and upload side by side (the upload under the sheet's second column), the
    /// last minute or so drawn as fine lines beneath.
    @ViewBuilder private func network(_ s: Snapshot, _ prefs: Preferences) -> some View {
        let unit = prefs.network.speedUnit
        label(.network, detail: PanelText.kindName(s.network.kind))
        HStack(spacing: Self.inset * 2) {
            rate(MenuBarText.downArrow, Theme.down, s.network.connected ? Format.rateParts(s.network.down, unit: unit) : nil)
            rate(MenuBarText.upArrow, Theme.up, s.network.connected ? Format.rateParts(s.network.up, unit: unit) : nil)
        }
        .padding(.top, 8)
        let d = monitor.history.latest(.netDown, seconds: 40 * prefs.refresh(.network))
        let u = monitor.history.latest(.netUp, seconds: 40 * prefs.refresh(.network))
        let peak = max(d.max() ?? 0, u.max() ?? 0, 10_000) * 1.1
        MiniChart(series: [.init(values: d.map { $0 / peak }, color: Theme.down, fill: 0.1, lineWidth: 1.25),
                           .init(values: u.map { $0 / peak }, color: Theme.up, fill: 0, lineWidth: 1)],
                  gridLines: 0, minCount: 40)
            .frame(height: 30)
            .padding(.top, 10)
            .accessibilityHidden(true)
        if s.network.connected, !s.network.localIP.isEmpty {
            let publicIP = prefs.network.showPublicIP ? monitor.publicIP : nil
            caption(publicIP.map { L10n.Panel.localPublicIP(s.network.localIP, $0) } ?? L10n.Monitor.localIP(s.network.localIP))
        }
    }

    private func rate(_ arrow: String, _ color: Color, _ parts: (String, String)?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(arrow).ui(13, 500).foregroundStyle(color)
            Text(parts?.0 ?? L10n.Common.dash).ui(24, 400).kerning(-0.5).lineLimit(1)
            if let unit = parts?.1 { Text(unit).ui(12).foregroundStyle(Theme.sub).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Beside the disk: the CPU's temperature on a 0–100 °C bar in its zone's color, then the
    /// GPU and the first fan.
    @ViewBuilder private func temperature(_ s: Snapshot, _ unit: TemperatureUnit) -> some View {
        let cpu = s.sensors.cpuAverage
        let gpu = s.sensors.value(.gpu).map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash
        label(.sensors)
        readout(cpu.map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash, L10n.Module.cpu)
        graphic { MeterBar(fraction: (cpu ?? 0) / 100, color: TempZone.color(cpu ?? 0)) }
        if let fan = s.sensors.fans.first {
            ViewThatFits(in: .horizontal) {
                caption(L10n.Panel.sensorsCaption(gpu, Int(fan.rpm.rounded())))
                caption(L10n.Panel.gpuTempShort(gpu))
            }
        } else {
            caption(L10n.Panel.gpuTempShort(gpu))
        }
    }

    /// Four readings in two pairs, so the third starts under the sheet's second column.
    @ViewBuilder private func sensors(_ s: Snapshot, _ unit: TemperatureUnit) -> some View {
        label(.sensors)
        HStack(alignment: .top, spacing: Self.inset * 2) {
            HStack(alignment: .top, spacing: 8) {
                sensorStat(L10n.Module.cpu, s.sensors.cpuAverage.map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash, nil)
                sensorStat(L10n.Module.gpu, s.sensors.value(.gpu).map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash, nil)
            }
            HStack(alignment: .top, spacing: 8) {
                sensorStat(L10n.Sensors.fan, s.sensors.fans.first.map { "\(Int($0.rpm.rounded()))" } ?? L10n.Common.dash,
                           s.sensors.fans.isEmpty ? nil : L10n.Common.rpmUnit)
                sensorStat(L10n.Sensors.systemPower, s.sensors.systemPower.map { String(format: "%.1f", $0) } ?? L10n.Common.dash,
                           s.sensors.systemPower == nil ? nil : L10n.Common.wattUnit)
            }
        }
        .padding(.top, 10)
    }

    private func sensorStat(_ label: String, _ value: String, _ unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).ui(18, 400).kerning(-0.3)
                if let unit { Text(unit).ui(12).foregroundStyle(Theme.sub) }
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Parts

    /// Icon and name, quiet; a state on the right ("正常", "VPN"), with a color dot if it has one.
    private func label(_ m: Module, detail: String? = nil, color: Color? = nil) -> some View {
        HStack(spacing: 6) {
            LineIcon(d: Icons.module(m), size: 13, lineWidth: 1.3).foregroundStyle(Theme.faint)
            Text(m.title).ui(12, 500).foregroundStyle(Theme.sub).lineLimit(1)
            Spacer(minLength: 6)
            if let detail {
                HStack(spacing: 5) {
                    if let color { Circle().fill(color).frame(width: 5, height: 5) }
                    Text(detail).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
                }
            }
        }
        .frame(height: 16)
    }

    private func readout(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).ui(26, 400).kerning(-0.6).lineLimit(1)
            Text(unit).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    /// The bars or bar, sat on a shared line so the captions of a pair line up.
    private func graphic<G: View>(height: CGFloat = 3, @ViewBuilder _ g: () -> G) -> some View {
        g().frame(height: height).frame(height: 14, alignment: .bottom).padding(.top, 6)
    }

    private func caption(_ text: String) -> some View {
        Text(text).ui(12).foregroundStyle(Theme.sub).lineLimit(1).frame(height: 16).padding(.top, 8)
    }

    private func percentNumber(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))" }
}

/// Grey text link with a small chevron, a soft box under the pointer.
private struct FooterLink: View {
    var title: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).ui(12)
                LineIcon(d: Icons.linkChevron, width: 6, height: 10, viewBox: CGSize(width: 6, height: 10), lineWidth: 1.4)
            }
            .foregroundStyle(Theme.sub)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background {
                if hovering { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.well) }
            }
            .hoverAnimation(hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.leading, -2)
    }
}

/// Fine history bars, the latest solid; slots not yet filled show as a faint baseline.
struct HistoryBars: View {
    var values: [Double]
    var color: Color
    var count = 30
    var gap: CGFloat = 2

    var body: some View {
        Canvas { ctx, size in
            let recent = Array(values.suffix(count))
            let width = max(1, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            for i in 0..<count {
                let k = i - (count - recent.count)
                let v = k >= 0 ? min(1, max(0, recent[k])) : 0
                let h = max(1.5, size.height * v)
                let rect = CGRect(x: CGFloat(i) * (width + gap), y: size.height - h, width: width, height: h)
                let fill = k < 0 ? Theme.track : k == recent.count - 1 ? color : color.opacity(0.45)
                ctx.fill(Path(roundedRect: rect, cornerRadius: min(1, width / 2)), with: .color(fill))
            }
        }
        .accessibilityHidden(true)
    }
}
