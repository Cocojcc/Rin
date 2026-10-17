import AppKit
import SwiftUI

/// The "合并成一项" panel: every module as a tile on one screen (design D, without gradients).
struct CombinedPanel: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    @State private var sortByMemory = false

    var body: some View {
        let s = monitor.snapshot
        let prefs = settings.prefs
        let unit = prefs.general.temperatureUnit
        let _ = monitor.tick
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.Overview.title).font(.system(size: 17, weight: .bold))
                    Text(L10n.Panel.updatedEvery(Int(prefs.general.refreshInterval))).font(.system(size: 11)).foregroundStyle(Theme.sub)
                }
                Spacer()
                Button {
                    MainWindowController.shared.show(.general)
                } label: {
                    LineIcon(d: Icons.general, size: 16, lineWidth: 1.6)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.popGroup))
                        .overlay(Circle().strokeBorder(Theme.groupRim, lineWidth: 0.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Menu.settings)
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .frame(height: 40)

            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    tile(.cpu) {
                        tileHeader(.cpu, right: Text(SystemInfo.chipName))
                        Spacer(minLength: 4)
                        BigValue(number: "\(Int((s.cpu.total * 100).rounded()))", unit: "%", color: Theme.text, size: 40, unitSize: 20)
                        Spacer(minLength: 4)
                        HistoryBars(values: monitor.history.latest(.cpu, seconds: 32 * prefs.general.refreshInterval).map { $0 / 100 }, color: Theme.cpu)
                            .frame(height: 26)
                    }
                    tile(.memory) {
                        let pr = PanelText.pressure(s.memory.pressure)
                        HStack {
                            tileTitle(.memory)
                            Spacer()
                            StatusBadge(text: pr.0, fg: pr.1, bg: pr.2)
                        }
                        Spacer(minLength: 4)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.1f", Double(s.memory.used) / 1_073_741_824)).font(Fonts.big(36)).monospacedDigit()
                            Text(L10n.Panel.ofTotal(Format.memory(s.memory.total))).font(.system(size: 13)).foregroundStyle(Theme.sub)
                        }
                        Spacer(minLength: 4)
                        MemoryComposition(m: s.memory, height: 10)
                        Text(L10n.Panel.memoryBreakdown(Format.memory(s.memory.app), Format.memory(s.memory.wired), Format.memory(s.memory.compressed)))
                            .font(.system(size: 11)).foregroundStyle(Theme.sub).lineLimit(1).padding(.top, 6)
                    }
                }
                GridRow {
                    tile(.network, height: 116) {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 7) {
                                    tileTitle(.network)
                                    Text(PanelText.kindName(s.network.kind)).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.sub)
                                }
                                Spacer(minLength: 4)
                                let down = Format.rateParts(s.network.down, unit: prefs.network.speedUnit)
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(MenuBarText.downArrow).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.down)
                                    Text(s.network.connected ? down.0 : L10n.Common.dash).font(Fonts.big(32)).monospacedDigit()
                                    Text(down.1).font(.system(size: 13)).foregroundStyle(Theme.sub)
                                }
                                let up = Format.rateParts(s.network.up, unit: prefs.network.speedUnit)
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(MenuBarText.upArrow).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.up)
                                    Text(s.network.connected ? up.0 : L10n.Common.dash).font(Fonts.big(16)).monospacedDigit()
                                    Text(up.1).font(.system(size: 13)).foregroundStyle(Theme.sub)
                                }
                            }
                            VStack(alignment: .trailing, spacing: 6) {
                                let d = monitor.history.latest(.netDown, seconds: 30 * prefs.general.refreshInterval)
                                let u = monitor.history.latest(.netUp, seconds: 30 * prefs.general.refreshInterval)
                                let peak = max(d.max() ?? 0, u.max() ?? 0, 10_000)
                                MiniChart(series: [.init(values: d.map { $0 / peak }, color: Theme.down, lineWidth: 2),
                                                   .init(values: u.map { $0 / peak }, color: Theme.up, fill: 0, lineWidth: 2)], gridLines: 1)
                                    .frame(height: 62)
                                HStack(spacing: 12) {
                                    LegendDot(color: Theme.down, label: L10n.Panel.download)
                                    LegendDot(color: Theme.up, label: L10n.Panel.upload)
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
                        tileHeader(.disk, right: Text(root?.name ?? ""))
                        Spacer(minLength: 4)
                        let free = Format.storage(root?.available ?? 0).split(separator: " ").map(String.init)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(free.first ?? "").font(Fonts.big(36)).monospacedDigit()
                            Text(L10n.Panel.unitAvailable(free.count > 1 ? free[1] : "")).font(.system(size: 13)).foregroundStyle(Theme.sub)
                        }
                        Spacer(minLength: 4)
                        MeterBar(fraction: root?.usedFraction ?? 0, color: Theme.disk, height: 8)
                        Text(L10n.Panel.readWriteShort(Format.rate(s.disk.read), Format.rate(s.disk.write)))
                            .font(.system(size: 11)).foregroundStyle(Theme.sub).lineLimit(1).padding(.top, 6)
                    }
                    if s.battery.hasBattery {
                        tile(.battery, height: 136) {
                            tileHeader(.battery, right: Text(s.battery.isCharging ? L10n.Battery.charging : (s.battery.onAC ? L10n.Battery.onAC : L10n.Battery.onBattery)))
                            Spacer(minLength: 4)
                            BigValue(number: "\(Int((s.battery.level * 100).rounded()))", unit: "%", color: Theme.text, size: 36, unitSize: 18)
                            Spacer(minLength: 4)
                            BigBatteryBar(level: s.battery.level, color: s.battery.level <= 0.2 && !s.battery.onAC ? Theme.low : Theme.bat, height: 16)
                            Text(batteryLine(s.battery)).font(.system(size: 11)).foregroundStyle(Theme.sub).lineLimit(1).padding(.top, 6)
                        }
                    } else {
                        tile(.gpu, height: 136) {
                            tileHeader(.gpu, right: Text(s.gpu.model))
                            Spacer(minLength: 4)
                            BigValue(number: "\(Int((s.gpu.utilization * 100).rounded()))", unit: "%", color: Theme.text, size: 36, unitSize: 18)
                            Spacer(minLength: 4)
                            MeterBar(fraction: s.gpu.utilization, color: Theme.gpu, height: 8)
                            Text(L10n.Panel.vramUsed(Format.memory(s.gpu.memoryUsed))).font(.system(size: 11)).foregroundStyle(Theme.sub).padding(.top, 6)
                        }
                    }
                }
                GridRow {
                    tile(.sensors, height: nil) {
                        tileTitle(.sensors)
                        HStack(alignment: .top, spacing: 8) {
                            sensorStat(L10n.Module.cpu, s.sensors.cpuAverage.map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash, nil)
                            sensorStat(L10n.Module.gpu, s.sensors.value(.gpu).map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash, nil)
                            if let fan = s.sensors.fans.first {
                                sensorStat(L10n.Sensors.fan, "\(Int(fan.rpm))", "rpm")
                            } else {
                                sensorStat(L10n.Sensors.fan, L10n.Common.dash, nil)
                            }
                            sensorStat(L10n.Sensors.systemPower, s.sensors.systemPower.map { String(format: "%.1f", $0) } ?? L10n.Common.dash, s.sensors.systemPower == nil ? nil : "W")
                        }
                        .padding(.top, 10)
                    }
                    .gridCellColumns(2)
                }
            }

            topCard(s)

            HStack(spacing: 8) {
                Button {
                    ProcessActions.openActivityMonitor()
                    PanelController.shared.close()
                } label: {
                    Text(L10n.Panel.openActivityMonitor)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Capsule().fill(Theme.popGroup))
                        .overlay(Capsule().strokeBorder(Theme.groupRim, lineWidth: 0.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    NSApp.terminate(nil)
                } label: {
                    LineIcon(d: Icons.power, size: 15, lineWidth: 1.7)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.popGroup))
                        .overlay(Circle().strokeBorder(Theme.groupRim, lineWidth: 0.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Menu.quit)
            }
        }
        .padding(12)
    }

    private func batteryLine(_ b: BatterySample) -> String {
        var parts: [String] = []
        if b.isCharging, let m = b.minutesToFull { parts.append(L10n.Battery.untilFull(Format.clockDuration(minutes: m))) }
        else if !b.onAC, let m = b.minutesToEmpty { parts.append(L10n.Battery.remaining(Format.clockDuration(minutes: m))) }
        if let h = b.health { parts.append(L10n.Panel.healthShort(Format.percent(h))) }
        return parts.joined(separator: " · ")
    }

    private func tile<Content: View>(_ m: Module, height: CGFloat? = 140, @ViewBuilder content: () -> Content) -> some View {
        Button {
            MainWindowController.shared.show(.monitor(m))
        } label: {
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: height)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.popGroup))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.groupRim, lineWidth: 0.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.Panel.openMonitor(m.title))
    }

    private func tileTitle(_ m: Module) -> some View {
        HStack(spacing: 7) {
            LineIcon(d: Icons.module(m), size: 14, lineWidth: 1.6)
                .foregroundStyle(Theme.color(for: m))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.chip))
            Text(m.title).font(.system(size: 13, weight: .semibold))
        }
    }

    private func tileHeader(_ m: Module, right: Text) -> some View {
        HStack {
            tileTitle(m)
            Spacer(minLength: 4)
            right.font(.system(size: 11)).foregroundStyle(Theme.sub).lineLimit(1)
        }
    }

    private func sensorStat(_ label: String, _ value: String, _ unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.sub).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(Fonts.big(22)).monospacedDigit()
                if let unit { Text(unit).font(.system(size: 11, weight: .bold)) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func topCard(_ s: Snapshot) -> some View {
        let list = Array((sortByMemory ? s.processes.byMemory : s.processes.byCPU).prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.Overview.topUsage).font(.system(size: 13, weight: .semibold))
                Spacer()
                SegmentedPicker(label: L10n.Overview.sortBy, options: [(false, L10n.Module.cpu), (true, L10n.Module.memory)], selection: $sortByMemory, height: 20, fontSize: 11)
            }
            .frame(height: 28)
            ForEach(Array(list.enumerated()), id: \.element.id) { i, p in
                if i > 0 { Hairline() }
                HStack(spacing: 10) {
                    ProcessIcon(process: p, size: 24)
                    Text(p.name).font(.system(size: 13)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(sortByMemory ? Format.memory(p.memory) : Format.percentValue(p.cpu)).font(Fonts.big(15)).monospacedDigit()
                }
                .frame(height: 38)
                .contentShape(Rectangle())
                .contextMenu { ProcessContextMenu(process: p) }
            }
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 6, trailing: 14))
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.popGroup))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.groupRim, lineWidth: 0.5))
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
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(i == padded.count - 1 ? color : color.opacity(0.4))
                            .frame(height: max(3, geo.size.height * min(1, max(0.04, v))))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
