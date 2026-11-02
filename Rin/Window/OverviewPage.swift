import SwiftUI

/// A shelf of instruments, four to a row in the sidebar's order: each module's small device standing
/// on a rule, its reading underneath, a second reading beside it where one matters. A piece opens its
/// page. Who uses the most stays on the Processes page and each module's own.
struct OverviewPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    var alerts = Alerts.shared
    @Environment(\.pageExtra) private var extra

    var body: some View {
        let s = monitor.snapshot
        let _ = monitor.tick
        let modules = Sidebar.moduleOrder.filter(settings.prefs.isEnabled)
        if modules.isEmpty {
            Text(L10n.Overview.allOff).ui(14).foregroundStyle(Theme.sub).padding(.top, 20)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .topLeading), count: 4), alignment: .leading, spacing: 70 + extra / 2) {
                ForEach(modules) { piece($0, s) }
            }
            .padding(.top, 38 + extra / 4)
        }
    }

    /// A reading's color: plain, red while one of the module's alerts is on.
    private func lead(_ kind: Alerts.Rule) -> Color { alerts.firing(kind) == nil ? Theme.text : Theme.danger }

    @ViewBuilder private func piece(_ m: Module, _ s: Snapshot) -> some View {
        switch m {
        case .cpu:
            ShelfPiece(module: m, value: Format.percentNumber(s.cpu.total), unit: "%", color: lead(.cpu)) { ChipInstrument() } beside: { EmptyView() }
        case .gpu:
            ShelfPiece(module: m, value: Format.percentNumber(s.gpu.utilization), unit: "%", color: lead(.gpu)) { ScreenInstrument(history: true) } beside: { EmptyView() }
        case .memory:
            let used = Format.parts(Format.memory(used: s.memory.used, of: s.memory.total))
            ShelfPiece(module: m, value: Format.percentNumber(s.memory.usedFraction), unit: "%", color: lead(.memory)) { StickInstrument() } beside: {
                strong(used.0, " " + used.1)
            }
        case .network:
            let n = s.network, speed = settings.prefs.network.speedUnit
            let down = Format.rateParts(n.down, unit: speed), up = Format.rateParts(n.up, unit: speed)
            ShelfPiece(module: m, value: n.connected ? down.0 : L10n.Common.dash, unit: n.connected ? down.1 : nil, color: lead(.network)) { TubesInstrument() } beside: {
                if n.connected {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(MenuBarText.upArrow + " ")
                        strong(up.0, " " + up.1)
                    }
                } else {
                    Text(L10n.Overview.disconnected)
                }
            }
        case .disk:
            let root = s.disk.root
            let free = Format.parts(Format.storage(root?.available ?? 0))
            ShelfPiece(module: m, value: free.0, unit: L10n.Monitor.unitFree(free.1), color: lead(.disk)) {
                PlatterInstrument(volume: root, io: s.disk.read + s.disk.write)
            } beside: { EmptyView() }
        case .battery:
            let b = s.battery
            ShelfPiece(module: m, value: b.hasBattery ? Format.percentNumber(b.level) : L10n.Common.dash, unit: b.hasBattery ? "%" : nil,
                       color: b.hasBattery && b.level <= 0.2 && !b.onAC ? Theme.danger : Theme.text) {
                CellInstrument()
            } beside: {
                Text(b.hasBattery ? PanelText.batteryState(b) : L10n.Battery.noBattery)
            }
        case .bluetooth:
            let lowest = MenuBarText.lowestDevice(s)
            let low = lowest.map { BluetoothText.isLow($0, settings.prefs) } ?? false
            ShelfPiece(module: m, value: lowest?.level.map(Format.percentNumber) ?? L10n.Common.dash, unit: lowest == nil ? nil : "%", color: low ? Theme.danger : Theme.text) {
                PackInstrument()
            } beside: {
                if let lowest, let left = BluetoothText.estimate(lowest) {
                    Text(left).foregroundStyle(low ? Theme.danger : Theme.sub)
                }
            }
        case .sensors:
            let t = s.sensors
            let unit = settings.prefs.general.temperatureUnit
            ShelfPiece(module: m, value: t.cpuAverage.map { Format.temperatureNumber($0, unit: unit) } ?? L10n.Common.dash, unit: Format.temperatureSymbol(unit),
                       color: alerts.firing(.temperature) != nil ? Theme.danger : t.cpuAverage.map(TempZone.color) ?? Theme.text) {
                SensorInstrument()
            } beside: {
                // Read to the nearest ten: the last figure only ever jitters.
                if let f = t.fans.first {
                    let rpm = Format.parts(Format.rpm((f.rpm / 10).rounded() * 10))
                    strong(rpm.0, " " + rpm.1)
                }
            }
        }
    }

    /// A second reading's figure at full strength, the rest quiet.
    private func strong(_ figure: String, _ rest: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(figure).ui(12, 500).foregroundStyle(Theme.text)
            Text(rest)
        }
    }
}

/// One module on the shelf: its device on the rule, then its icon and name, the reading and what goes beside it.
private struct ShelfPiece<Device: View, Beside: View>: View {
    let module: Module
    var value: String
    var unit: String?
    var color: Color
    @ViewBuilder var device: Device
    @ViewBuilder var beside: Beside
    @State private var hovering = false

    var body: some View {
        Button { Navigator.shared.page = .monitor(module) } label: {
            VStack(alignment: .leading, spacing: 0) {
                device.frame(maxWidth: .infinity).frame(height: 176, alignment: .bottom)
                Rectangle().fill(Theme.low).frame(height: 1)
                HStack(spacing: 5) {
                    LineIcon(d: Icons.module(module), size: 14, lineWidth: 1.5).foregroundStyle(Theme.hue(module) ?? Theme.sub)
                    Text(module.title).ui(12, 500).lineLimit(1)
                }
                .frame(height: 18)
                .padding(.top, 12)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    BigValue(value: value, unit: unit, size: 34, color: color).layoutPriority(1)
                    beside.ui(12).foregroundStyle(Theme.sub).lineLimit(1).truncationMode(.tail)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background { if hovering { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.lgHover) } }
            .padding(.horizontal, -7)
            .hoverAnimation(hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.Panel.openMonitor(module.title))
    }
}
