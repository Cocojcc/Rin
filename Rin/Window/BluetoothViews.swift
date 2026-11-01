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
}

/// Lays children out in equal columns: a fixed count, or as many as fit `minWidth`.
struct EvenGrid: Layout {
    var columns: Int? = nil
    /// With `columns` nil, never more than this many to a row.
    var maxColumns = Int.max
    var minWidth: CGFloat = 76
    var hSpacing: CGFloat = 4
    var vSpacing: CGFloat = 16

    private func metrics(_ width: CGFloat, _ count: Int) -> (cols: Int, item: CGFloat) {
        let fit = Int((width + hSpacing) / (minWidth + hSpacing))
        let cols = max(1, columns ?? min(max(1, fit), max(1, count), maxColumns))
        return (cols, (width - CGFloat(cols - 1) * hSpacing) / CGFloat(cols))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 400
        let m = metrics(width, subviews.count)
        var height: CGFloat = 0
        for row in stride(from: 0, to: subviews.count, by: m.cols) {
            let h = subviews[row..<min(row + m.cols, subviews.count)].map { $0.sizeThatFits(ProposedViewSize(width: m.item, height: nil)).height }.max() ?? 0
            height += h + (row > 0 ? vSpacing : 0)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let m = metrics(bounds.width, subviews.count)
        var y = bounds.minY
        for row in stride(from: 0, to: subviews.count, by: m.cols) {
            let items = subviews[row..<min(row + m.cols, subviews.count)]
            let h = items.map { $0.sizeThatFits(ProposedViewSize(width: m.item, height: nil)).height }.max() ?? 0
            for (i, view) in items.enumerated() {
                view.place(at: CGPoint(x: bounds.minX + CGFloat(i) * (m.item + hSpacing), y: y), anchor: .topLeading,
                           proposal: ProposedViewSize(width: m.item, height: h))
            }
            y += h + vSpacing
        }
    }
}

enum DeviceRange: CaseIterable {
    case h24, d7, d30

    var seconds: TimeInterval { [86_400, 7 * 86_400, 30 * 86_400][index] }
    var title: String { [L10n.Range.h24, L10n.Range.d7, L10n.Range.d30][index] }
    var axisLabels: [String] {
        switch self {
        case .h24: return TimeRange.h24.axisLabels
        case .d7: return TimeRange.d7.axisLabels
        case .d30: return [30, 24, 18, 12, 6].map { L10n.Chart.daysAgo($0) } + [L10n.Range.now]
        }
    }
    private var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
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
        PanelHeader(module: .bluetooth, subtitle: L10n.Bluetooth.deviceCount(bt.connected.count))
        VStack(spacing: 0) {
            if bt.withBattery.isEmpty {
                Text(L10n.Bluetooth.noDevices).ui(14).foregroundStyle(Theme.sub).frame(maxWidth: .infinity, alignment: .leading).frame(height: 30)
            }
            ForEach(bt.withBattery) { d in
                let low = BluetoothText.isLow(d, prefs)
                HStack(spacing: 10) {
                    LineIcon(d: Icons.device(d.kind), size: 16, lineWidth: 1.4).foregroundStyle(Theme.sub).frame(width: 16)
                    Text(d.name).ui(14).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                    LevelBar(fraction: d.level ?? 0, color: low ? Theme.danger : Theme.bat).frame(width: 72)
                    HStack(spacing: 2) {
                        if d.charging { FilledIcon(d: Icons.chargingBolt, width: 7, height: 10).foregroundStyle(Theme.bat) }
                        Text(Format.percent(d.level ?? 0)).ui(14, 500)
                    }
                    .foregroundStyle(low ? Theme.danger : Theme.text)
                    .frame(width: 44, alignment: .trailing)
                }
                .frame(height: 30)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(BluetoothText.a11y(d, low: low))
                if p.showBuds, d.hasBuds {
                    HStack(spacing: 12) {
                        ForEach(Array(BluetoothText.buds(d).enumerated()), id: \.offset) { _, b in KeyValue(label: b.1, value: b.0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 22)
                    .padding(.leading, 26)
                }
            }
        }
        if p.showHistory, let d = MenuBarText.lowestDevice(monitor.snapshot) {
            ConsoleRule()
            VStack(alignment: .leading, spacing: 8) {
                PanelTitle(title: d.name) { Text(L10n.Range.last24h).ui(12) }
                ConsoleChart(kind: .area, series: [ChartSeries(id: "l", points: levels(d), color: BluetoothText.isLow(d, prefs) ? Theme.danger : Theme.bat, fill: 0.14, lineWidth: 1.5)],
                             span: 86_400, maxGap: .infinity, maxValue: 100, height: 56, yLabels: [], xLabels: [L10n.Range.ago24h, L10n.Range.ago12h, L10n.Range.now],
                             rules: [ChartRule(fraction: p.lowLevel, color: Theme.danger)])
                    .accessibilityElement()
                    .accessibilityLabel(L10n.Bluetooth.chartA11y(d.name, L10n.Range.h24, Format.percent(p.lowLevel)))
            }
        }
        if p.showDisconnected && !bt.disconnected.isEmpty {
            ConsoleRule()
            PanelSection(title: L10n.Bluetooth.disconnected) {
                VStack(spacing: 0) {
                    ForEach(bt.disconnected) { d in
                        HStack(spacing: 10) {
                            LineIcon(d: Icons.device(d.kind), size: 16, lineWidth: 1.3).frame(width: 16)
                            Text(d.name).ui(14).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            if let seen = BluetoothText.lastSeen(d.lastSeen) { Text(seen).ui(12).lineLimit(1) }
                        }
                        .foregroundStyle(Theme.sub)
                        .frame(height: 28)
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

struct BluetoothPage: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    @State private var range: DeviceRange = .h24
    @State private var chosen: String?

    var body: some View {
        let bt = monitor.snapshot.bluetooth
        let prefs = settings.prefs
        let low = prefs.bluetooth.lowLevel
        let _ = monitor.tick
        VStack(alignment: .leading, spacing: 10) {
            ModuleHeader(module: .bluetooth) {
                Segmented(label: L10n.Range.label, options: DeviceRange.allCases.map { ($0, $0.title) }, selection: $range, style: .range)
                    .fixedSize()
            }
            ConsolePanel {
                PanelTitle(title: L10n.Bluetooth.connected)
                VStack(spacing: 0) {
                    if bt.withBattery.isEmpty {
                        Text(L10n.Bluetooth.noDevices).ui(14).foregroundStyle(Theme.sub)
                            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 32)
                    }
                    ForEach(bt.withBattery) { d in
                        DeviceRow(device: d, low: BluetoothText.isLow(d, prefs))
                        if d.hasBuds {
                            HStack(spacing: 14) {
                                ForEach(Array(BluetoothText.buds(d).enumerated()), id: \.offset) { _, b in KeyValue(label: b.1, value: b.0) }
                            }
                            .frame(height: 20)
                            .padding(.leading, 26)
                        }
                    }
                }
                .padding(.top, 6)
            }

            let devices = bt.connected + bt.disconnected
            if let device = devices.first(where: { $0.id == chosen }) ?? MenuBarText.lowestDevice(monitor.snapshot) ?? devices.first {
                let isLow = BluetoothText.isLow(device, prefs)
                ConsolePanel {
                    PanelTitle(title: device.name) {
                        if devices.count > 1 {
                            MenuPill(label: L10n.Bluetooth.device, options: devices.map { ($0.id, $0.name) },
                                     selection: Binding(get: { device.id }, set: { chosen = $0 }))
                        }
                    }
                    ConsoleChart(kind: .area, series: [ChartSeries(id: "level", points: levels(device), color: isLow ? Theme.danger : Theme.bat, fill: 0.14, lineWidth: 1.5)],
                                 span: range.seconds, maxGap: .infinity, maxValue: 100, height: 155, yLabels: ChartScale.percent,
                                 xLabels: range.axisLabels,
                                 rules: AlertRules.chartRule(.bluetoothLow, fraction: low, prefs))
                        .alertBell(.bluetoothLow)
                        .padding(.top, 12)
                        .accessibilityElement()
                        .accessibilityLabel(L10n.Bluetooth.chartA11y(device.name, range.title, Format.percent(low)))
                }
            }

            if !bt.disconnected.isEmpty {
                ConsolePanel {
                    PanelTitle(title: L10n.Bluetooth.disconnected) { Text(L10n.Battery.deviceCount(bt.disconnected.count)) }
                    VStack(spacing: 0) {
                        ForEach(bt.disconnected) { DisconnectedRow(device: $0) }
                    }
                    .padding(.top, 6)
                }
            }
        }
    }

    /// The device's stored levels over the range, the last one from before it carried in from the
    /// left edge and the newest held up to now.
    private func levels(_ device: BluetoothDevice) -> [ChartPoint] {
        let all = BluetoothStore.shared.history(device.id)
        let end = Date()
        let start = end.addingTimeInterval(-range.seconds)
        var pts = all.filter { $0.date >= start }.map { ChartPoint(date: $0.date, value: $0.level * 100) }
        if let before = all.last(where: { $0.date < start }) { pts.insert(ChartPoint(date: start, value: before.level * 100), at: 0) }
        if let last = pts.last { pts.append(ChartPoint(date: end, value: (device.level.map { $0 * 100 }) ?? last.value)) }
        return pts
    }
}

/// A connected device: icon, name, its level as cells, the percentage, and the time it has left.
private struct DeviceRow: View {
    var device: BluetoothDevice
    var low: Bool

    var body: some View {
        HStack(spacing: 10) {
            LineIcon(d: Icons.device(device.kind), size: 16, lineWidth: 1.4).foregroundStyle(Theme.sub).frame(width: 16)
            Text(device.name).ui(14).lineLimit(1).frame(width: 120, alignment: .leading)
            LevelBar(fraction: device.level ?? 0, color: low ? Theme.danger : Theme.bat)
            HStack(spacing: 3) {
                if device.charging { FilledIcon(d: Icons.chargingBolt, width: 7, height: 10).foregroundStyle(Theme.bat) }
                Text(Format.percent(device.level ?? 0)).ui(14, 500).foregroundStyle(low ? Theme.danger : Theme.text)
            }
            .frame(width: 52, alignment: .trailing)
            Text(device.charging ? L10n.Battery.charging : (BluetoothText.estimate(device) ?? "")).ui(12).foregroundStyle(Theme.sub)
                .lineLimit(1).frame(width: 84, alignment: .trailing)
        }
        .frame(height: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BluetoothText.a11y(device, low: low))
    }
}

/// A paired device that isn't connected: its battery then, and when Rin last saw it.
private struct DisconnectedRow: View {
    var device: BluetoothDevice

    var body: some View {
        HStack(spacing: 10) {
            LineIcon(d: Icons.device(device.kind), size: 16, lineWidth: 1.4).frame(width: 16)
            Text(device.name).ui(14).lineLimit(1).frame(width: 120, alignment: .leading)
            LevelBar(fraction: device.level ?? 0, color: Theme.neutral.opacity(0.5))
            Text(device.level.map(Format.percent) ?? L10n.Common.dash).ui(14).frame(width: 52, alignment: .trailing)
            Text(BluetoothText.lastSeen(device.lastSeen).map { L10n.Bluetooth.lastConnected($0) } ?? "").ui(12)
                .lineLimit(1).frame(width: 140, alignment: .trailing)
        }
        .foregroundStyle(Theme.sub)
        .frame(height: 30)
        .accessibilityElement(children: .combine)
    }
}

struct BluetoothOverviewRows: View {
    var snapshot: Snapshot
    var prefs: Preferences

    var body: some View {
        let devices = snapshot.bluetooth.withBattery.sorted { ($0.level ?? 1) < ($1.level ?? 1) }
        VStack(alignment: .leading, spacing: 6) {
            if devices.isEmpty {
                Text(L10n.Bluetooth.noDevices).ui(12).foregroundStyle(Theme.faint).frame(height: 18)
            }
            ForEach(devices.prefix(4)) { d in
                let low = BluetoothText.isLow(d, prefs)
                HStack(spacing: 8) {
                    LineIcon(d: Icons.device(d.kind), size: 14, lineWidth: 1.3).foregroundStyle(Theme.sub)
                    Text(d.name).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 2) {
                        if d.charging { FilledIcon(d: Icons.chargingBolt, width: 8, height: 11).foregroundStyle(Theme.bat) }
                        Text(Format.percent(d.level ?? 0)).fontWeight(.medium)
                    }
                    .foregroundStyle(low ? Theme.danger : Theme.text)
                }
                .ui(12)
                .frame(height: 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
