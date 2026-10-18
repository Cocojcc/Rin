import AppKit
import SwiftUI

/// The "合并成一项" panel: every module as a tile on one screen, in the glass style.
struct CombinedPanel: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    @State private var sortByMemory = false

    var body: some View {
        let s = monitor.snapshot
        let prefs = settings.prefs
        let unit = prefs.general.temperatureUnit
        let _ = monitor.tick
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.Overview.title).ui(17, 500).kerning(-0.17).accessibilityAddTraits(.isHeader)
                    Text(L10n.Panel.updatedEvery(Int(prefs.refresh(.cpu)))).ui(11).foregroundStyle(Theme.sub)
                }
                Spacer(minLength: 0)
                IconButton(d: Icons.general, size: 28, iconSize: 16, viewBox: 16, lineWidth: 1.5, fill: .clear, tint: Theme.sub, label: L10n.Menu.settings) {
                    MainWindowController.shared.show(.settings)
                }
            }
            .padding(.leading, 6)

            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    tile(.cpu) {
                        tileHeader(.cpu, right: SystemInfo.chipName)
                        Spacer(minLength: 4)
                        bigValue(percentNumber(s.cpu.total), L10n.Common.percentSign)
                        Spacer(minLength: 4)
                        HistoryBars(values: monitor.history.latest(.cpu, seconds: 32 * prefs.refresh(.cpu)).map { $0 / 100 }, color: Theme.cpu)
                            .frame(height: 26)
                    }
                    tile(.memory) {
                        let pr = PanelText.pressure(s.memory.pressure)
                        HStack(spacing: 8) {
                            tileTitle(.memory)
                            Spacer(minLength: 0)
                            StatusPill(text: pr.0, fg: pr.1, bg: pr.2)
                        }
                        Spacer(minLength: 4)
                        bigValue(String(format: "%.1f", Double(s.memory.used) / 1_073_741_824), L10n.Panel.ofTotal(Format.memory(s.memory.total)))
                        Spacer(minLength: 4)
                        MemoryComposition(m: s.memory)
                        Text(L10n.Panel.memoryBreakdown(Format.memory(s.memory.app), Format.memory(s.memory.wired), Format.memory(s.memory.compressed)))
                            .ui(11).foregroundStyle(Theme.sub).lineLimit(1).padding(.top, 8)
                    }
                }
                GridRow {
                    tile(.network, height: 116) {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 6) {
                                    tileTitle(.network)
                                    Text(PanelText.kindName(s.network.kind)).ui(13).foregroundStyle(Theme.sub)
                                }
                                Spacer(minLength: 4)
                                let down = Format.rateParts(s.network.down, unit: prefs.network.speedUnit)
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(MenuBarText.downArrow).ui(15, 500).foregroundStyle(Theme.down)
                                    Text(s.network.connected ? down.0 : L10n.Common.dash).ui(32, 500).kerning(-0.64)
                                    Text(down.1).ui(13).foregroundStyle(Theme.sub)
                                }
                                let up = Format.rateParts(s.network.up, unit: prefs.network.speedUnit)
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(MenuBarText.upArrow).ui(13, 500).foregroundStyle(Theme.up)
                                    Text(s.network.connected ? up.0 : L10n.Common.dash).ui(16, 500)
                                    Text(up.1).ui(13).foregroundStyle(Theme.sub)
                                }
                            }
                            VStack(alignment: .trailing, spacing: 6) {
                                let d = monitor.history.latest(.netDown, seconds: 30 * prefs.refresh(.network))
                                let u = monitor.history.latest(.netUp, seconds: 30 * prefs.refresh(.network))
                                let peak = max(d.max() ?? 0, u.max() ?? 0, 10_000) * 1.1
                                MiniChart(series: [.init(values: d.map { $0 / peak }, color: Theme.down),
                                                   .init(values: u.map { $0 / peak }, color: Theme.up, fill: 0, lineWidth: 1.25)], gridLines: 1)
                                    .frame(height: 62)
                                HStack(spacing: 12) {
                                    LegendDot(color: Theme.down, label: L10n.Panel.download, size: 6)
                                    LegendDot(color: Theme.up, label: L10n.Panel.upload, size: 6)
                                }
                            }
                            .frame(width: 176)
                        }
                    }
                    .gridCellColumns(2)
                }
                GridRow {
                    let root = s.disk.root
                    tile(.disk, height: 136) {
                        tileHeader(.disk, right: root?.name ?? "")
                        Spacer(minLength: 4)
                        let free = Format.storage(root?.available ?? 0).split(separator: " ").map(String.init)
                        bigValue(free.first ?? "", L10n.Panel.unitAvailable(free.count > 1 ? free[1] : ""))
                        Spacer(minLength: 4)
                        MeterBar(fraction: root?.usedFraction ?? 0, color: Theme.disk)
                        Text(L10n.Panel.readWriteShort(Format.rate(s.disk.read), Format.rate(s.disk.write)))
                            .ui(11).foregroundStyle(Theme.sub).lineLimit(1).padding(.top, 8)
                    }
                    if s.battery.hasBattery {
                        tile(.battery, height: 136) {
                            tileHeader(.battery, right: PanelText.batteryState(s.battery))
                            Spacer(minLength: 4)
                            bigValue(percentNumber(s.battery.level), L10n.Common.percentSign)
                            Spacer(minLength: 4)
                            MeterBar(fraction: s.battery.level, color: s.battery.level <= 0.2 && !s.battery.onAC ? Theme.danger : Theme.bat)
                            Text(batteryLine(s.battery)).ui(11).foregroundStyle(Theme.sub).lineLimit(1).padding(.top, 8)
                        }
                    } else {
                        tile(.gpu, height: 136) {
                            tileHeader(.gpu, right: s.gpu.model)
                            Spacer(minLength: 4)
                            bigValue(percentNumber(s.gpu.utilization), L10n.Common.percentSign)
                            Spacer(minLength: 4)
                            MeterBar(fraction: s.gpu.utilization, color: Theme.gpu)
                            Text(L10n.Panel.vramUsed(Format.memory(s.gpu.memoryUsed))).ui(11).foregroundStyle(Theme.sub).padding(.top, 8)
                        }
                    }
                }
                GridRow {
                    tile(.sensors, height: nil) {
                        tileTitle(.sensors)
                        HStack(alignment: .top, spacing: 8) {
                            sensorStat(L10n.Module.cpu, s.sensors.cpuAverage.map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash, nil)
                            sensorStat(L10n.Module.gpu, s.sensors.value(.gpu).map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash, nil)
                            sensorStat(L10n.Sensors.fan, s.sensors.fans.first.map { "\(Int($0.rpm.rounded()))" } ?? L10n.Common.dash,
                                       s.sensors.fans.isEmpty ? nil : L10n.Common.rpmUnit)
                            sensorStat(L10n.Sensors.systemPower, s.sensors.systemPower.map { String(format: "%.1f", $0) } ?? L10n.Common.dash,
                                       s.sensors.systemPower == nil ? nil : L10n.Common.wattUnit)
                        }
                        .padding(.top, 10)
                    }
                    .gridCellColumns(2)
                }
            }

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

            HStack(spacing: 8) {
                WellButton(title: L10n.Panel.openActivityMonitor, height: 38, radius: 12, expands: true) {
                    ProcessActions.openActivityMonitor()
                    PanelController.shared.close()
                }
                IconButton(d: Icons.power, size: 38, radius: 12, iconSize: 15, viewBox: 16, lineWidth: 1.6, tint: Theme.text, label: L10n.Menu.quit) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func percentNumber(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))" }

    private func bigValue(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).ui(36, 500).kerning(-1.08).lineLimit(1)
            Text(unit).ui(13).foregroundStyle(Theme.sub).lineLimit(1)
        }
    }

    private func batteryLine(_ b: BatterySample) -> String {
        var parts: [String] = []
        if b.isCharging, let m = b.minutesToFull { parts.append(L10n.Battery.untilFull(Format.clockDuration(minutes: m))) }
        else if !b.onAC, let m = b.minutesToEmpty { parts.append(L10n.Battery.remaining(Format.clockDuration(minutes: m))) }
        if let h = b.health { parts.append(L10n.Panel.healthShort(Format.percent(h))) }
        return parts.joined(separator: L10n.A11y.dotSeparator)
    }

    private func tile<Content: View>(_ m: Module, height: CGFloat? = 140, @ViewBuilder content: () -> Content) -> some View {
        Button {
            MainWindowController.shared.show(.monitor(m))
        } label: {
            VStack(alignment: .leading, spacing: 0) { content() }
                .opacity(settings.prefs.isMonitored(m) ? 1 : 0.35)   // switched off: nothing is read
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: height)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.well))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.Panel.openMonitor(m.title))
    }

    private func tileTitle(_ m: Module) -> some View {
        HStack(spacing: 6) {
            LineIcon(d: Icons.module(m), size: 14, lineWidth: 1.5).foregroundStyle(Theme.sub)
            Text(m.title).ui(13, 500)
        }
    }

    private func tileHeader(_ m: Module, right: String) -> some View {
        HStack(spacing: 8) {
            tileTitle(m)
            Spacer(minLength: 4)
            Text(right).ui(11).foregroundStyle(Theme.sub).lineLimit(1)
        }
    }

    private func sensorStat(_ label: String, _ value: String, _ unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).ui(11).foregroundStyle(Theme.sub).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).ui(20, 500).kerning(-0.4)
                if let unit { Text(unit).ui(11).foregroundStyle(Theme.sub) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Little history bars (latest is solid), used by the combined CPU tile.
struct HistoryBars: View {
    var values: [Double]
    var color: Color
    var count = 16

    var body: some View {
        let recent = Array(values.suffix(count))
        let padded = [Double](repeating: 0, count: max(0, count - recent.count)) + recent
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(padded.enumerated()), id: \.offset) { i, v in
                GeometryReader { geo in
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(i == padded.count - 1 ? color : color.opacity(0.4))
                            .frame(height: max(3, geo.size.height * min(1, max(0.04, v))))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
