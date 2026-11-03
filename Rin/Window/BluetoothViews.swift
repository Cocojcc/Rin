import SwiftUI

// MARK: - Shared

enum BluetoothText {
    /// "约 6 周", "约 2 天", "约 4 小时" from the store's discharge estimate.
    static func estimate(_ d: BluetoothDevice) -> String? {
        guard let level = d.level, let seconds = BluetoothStore.shared.timeLeft(d.id, level: level) else { return nil }
        return AlertText.estimate(seconds)
    }

    /// "昨天 18:20", or "3 天前" further back.
    static func lastSeen(_ date: Date?) -> String? {
        guard let date else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(date) || cal.isDateInYesterday(date) { return Format.dayAndTime(date) }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day ?? 0
        return L10n.Bluetooth.daysAgo(max(2, days))
    }

    static func a11y(_ d: BluetoothDevice, low: Bool) -> String {
        var text = L10n.Bluetooth.deviceA11y(d.name, d.level.map(Format.percent) ?? L10n.Common.dash)
        if d.charging { text += L10n.Battery.chargingA11y } else if low { text += L10n.Bluetooth.lowA11y }
        return text
    }

    static func buds(_ d: BluetoothDevice) -> [(String, String)] {
        [(d.left, L10n.Bluetooth.left), (d.right, L10n.Bluetooth.right), (d.caseLevel, L10n.Bluetooth.caseLabel)]
            .compactMap { level, label in level.map { (Format.percent($0), label) } }
    }

    static func isLow(_ d: BluetoothDevice, _ prefs: Preferences) -> Bool { (d.level ?? 1) <= prefs.bluetooth.lowLevel }

    /// The device a module's reading follows, and how long it has left: "Magic Trackpad 约 3 周".
    static func lowestLine(_ d: BluetoothDevice) -> String {
        estimate(d).map { d.name + " " + $0 } ?? d.name
    }
}

// MARK: - Dropdown

struct BluetoothPanel: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared

    var body: some View {
        let bt = monitor.snapshot.bluetooth
        let prefs = settings.prefs
        let p = prefs.bluetooth
        let _ = monitor.tick
        let lowest = MenuBarText.lowestDevice(monitor.snapshot)
        let lowestIsLow = lowest.map { BluetoothText.isLow($0, prefs) } ?? false
        PanelHeader(module: .bluetooth)
        if let lowest {
            PanelStand {
                BigValue(value: Format.percentNumber(lowest.level ?? 0), unit: "%", size: BigValue.panelLead, color: lowestIsLow ? Theme.danger : Theme.text)
            } foot: {
                Text(BluetoothText.lowestLine(lowest)).foregroundStyle(lowestIsLow ? Theme.danger : Theme.sub).truncationMode(.middle)
            }
        }
        VStack(spacing: 0) {
            if bt.withBattery.isEmpty {
                Text(L10n.Bluetooth.noDevices).ui(14).foregroundStyle(Theme.sub).frame(maxWidth: .infinity, alignment: .leading).frame(height: 34)
            }
            ForEach(bt.withBattery) { d in
                let low = BluetoothText.isLow(d, prefs)
                HStack(spacing: 8) {
                    LineIcon(d: Icons.device(d.kind), size: 16, lineWidth: 1.4).foregroundStyle(Theme.sub)
                    Text(d.name).ui(14).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 8)
                    if d.charging { FilledIcon(d: Icons.chargingBolt, width: 7, height: 10) }
                    Reading(text: Format.percent(d.level ?? 0), color: low ? Theme.danger : Theme.text)
                }
                .frame(height: 34)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(BluetoothText.a11y(d, low: low))
                if p.showBuds, d.hasBuds {
                    HStack(spacing: 12) {
                        ForEach(Array(BluetoothText.buds(d).enumerated()), id: \.offset) { _, b in KeyValue(label: b.1, value: b.0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 22)
                    .padding(.leading, 24)
                }
                if d.connection == .receiver {
                    Text(L10n.Bluetooth.receiver).ui(12).foregroundStyle(Theme.sub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 22)
                        .padding(.leading, 24)
                }
            }
        }
        .padding(.top, 8)
        if p.showHistory, let d = lowest {
            PanelSection(title: d.name, right: L10n.Range.last24h, top: 16) {
                ConsoleChart(kind: .area, series: ChartSeries.line(levels(d), BluetoothText.isLow(d, prefs) ? Theme.danger : Theme.mid),
                             span: 86_400, maxGap: .infinity, maxValue: 100, height: 48,
                             rules: [ChartRule(fraction: p.lowLevel, color: Theme.danger)])
                    .padding(.top, 8)
                    .accessibilityElement()
                    .accessibilityLabel(L10n.Bluetooth.chartA11y(d.name, L10n.Range.h24, Format.percent(p.lowLevel)))
            }
        }
        if p.showDisconnected && !bt.disconnected.isEmpty {
            PanelSection(title: L10n.Bluetooth.disconnected, top: 16) {
                VStack(spacing: 0) {
                    ForEach(bt.disconnected) { d in
                        HStack(spacing: 8) {
                            LineIcon(d: Icons.device(d.kind), size: 16, lineWidth: 1.4)
                            Text(d.name).ui(14).lineLimit(1)
                            Spacer(minLength: 8)
                            if let seen = BluetoothText.lastSeen(d.lastSeen) { Text(seen).ui(12).lineLimit(1) }
                        }
                        .foregroundStyle(Theme.sub)
                        .frame(height: 32)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func levels(_ device: BluetoothDevice) -> [ChartPoint] {
        let all = BluetoothStore.shared.history(device.id)
        let end = Date(), start = end.addingTimeInterval(-86_400)
        var pts = all.filter { $0.date >= start }.map { ChartPoint(date: $0.date, value: $0.level * 100) }
        if let before = all.last(where: { $0.date < start }) { pts.insert(ChartPoint(date: start, value: before.level * 100), at: 0) }
        if let last = pts.last { pts.append(ChartPoint(date: end, value: device.level.map { $0 * 100 } ?? last.value)) }
        return pts
    }
}

/// A small filled glyph (the charging bolt).
struct FilledIcon: View {
    var d: String
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        SVGShape(d: d, viewBox: CGSize(width: width, height: height)).fill(.foreground).frame(width: width, height: height)
    }
}

// MARK: - Monitor page

/// The lowest device's level, then one row per device: connected ones with their level, then the
/// paired ones that aren't connected, greyed, with when Rin last saw them.
/// The list is the whole page, so its rows take the height there is.
struct BluetoothPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    @Environment(\.pageExtra) private var extra

    private static let room: CGFloat = 509

    var body: some View {
        let bt = monitor.snapshot.bluetooth
        let prefs = settings.prefs
        let _ = monitor.tick
        let lowest = MenuBarText.lowestDevice(monitor.snapshot)
        let low = lowest.map { BluetoothText.isLow($0, prefs) } ?? false
        let shown = bt.withBattery.count + bt.disconnected.count
        let height = min(114, max(52, (Self.room + extra - (bt.disconnected.isEmpty ? 0 : 48)) / CGFloat(max(shown, 1))))
        VStack(alignment: .leading, spacing: 0) {
            if let lowest {
                Stand {
                    VStack(alignment: .leading, spacing: 8) {
                        BigValue(value: Format.percentNumber(lowest.level ?? 0), unit: "%", size: BigValue.lead, color: low ? Theme.danger : Theme.text)
                        Text(BluetoothText.lowestLine(lowest)).ui(13).foregroundStyle(low ? Theme.danger : Theme.sub).lineLimit(1)
                    }
                }
            }
            if bt.withBattery.isEmpty {
                Text(L10n.Bluetooth.noDevices).ui(14).foregroundStyle(Theme.sub).padding(.top, 28)
            } else {
                ForEach(bt.withBattery) { DeviceRow(device: $0, low: BluetoothText.isLow($0, prefs), height: height) }
            }
            if !bt.disconnected.isEmpty {
                HeadRow(title: L10n.Bluetooth.disconnected).padding(.top, 26)
                ForEach(bt.disconnected) { DeviceRow(device: $0, low: false, away: true, height: height) }
            }
        }
    }
}

/// A device on one row: icon and name (AirPods' buds and case, or the receiver it's on, under it),
/// the level as a number (red when low), then the time it has left, or for one that isn't
/// connected, when it was last seen.
private struct DeviceRow: View {
    var device: BluetoothDevice
    var low: Bool
    var away = false
    var height: CGFloat

    var body: some View {
        let detail = !away && (device.hasBuds || device.connection == .receiver)
        HStack(spacing: 20) {
            HStack(spacing: 12) {
                LineIcon(d: Icons.device(device.kind), size: 20, lineWidth: 1.4).foregroundStyle(Theme.sub)
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name).ui(14).foregroundStyle(away ? Theme.sub : Theme.text).lineLimit(1).truncationMode(.tail)
                    if detail && device.hasBuds {
                        KeyValues(pairs: BluetoothText.buds(device).map { ($0.1, $0.0) }, spacing: 8)
                    } else if detail {
                        Text(L10n.Bluetooth.receiver).foregroundStyle(Theme.sub)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) {
                if device.charging && !away { FilledIcon(d: Icons.chargingBolt, width: 7, height: 10) }
                Reading(text: device.level.map(Format.percent) ?? L10n.Common.dash, weight: away ? 400 : 500, color: low ? Theme.danger : away ? Theme.sub : Theme.text)
            }
            .frame(width: 44, alignment: .trailing)
            Text(trailing).ui(13).foregroundStyle(Theme.sub).lineLimit(1).fixedSize().frame(minWidth: 92, alignment: .trailing)
        }
        .frame(height: detail ? height + 10 : height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BluetoothText.a11y(device, low: low))
    }

    private var trailing: String {
        if away { return BluetoothText.lastSeen(device.lastSeen) ?? "" }
        return device.charging ? L10n.Battery.charging : (BluetoothText.estimate(device) ?? "")
    }
}
