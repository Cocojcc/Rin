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
    var minWidth: CGFloat = 76
    var hSpacing: CGFloat = 4
    var vSpacing: CGFloat = 16

    private func metrics(_ width: CGFloat, _ count: Int) -> (cols: Int, item: CGFloat) {
        let fit = Int((width + hSpacing) / (minWidth + hSpacing))
        let cols = max(1, columns ?? min(max(1, fit), max(1, count)))
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

/// A device's battery over time: grid, a dashed line at the low level, area and line.
struct DeviceBatteryChart: View {
    var points: [BluetoothStore.Point]
    var start: Date
    var end: Date
    var low: Double

    var body: some View {
        chart.overlay {
            if !points.contains(where: { $0.date >= start }) && !points.contains(where: { $0.date < start }) {
                Text(L10n.Bluetooth.noHistory).ui(12).foregroundStyle(Theme.faint)
            }
        }
    }

    private var chart: some View {
        Canvas { ctx, size in
            for f in [0.25, 0.5, 0.75] {
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: size.height * f))
                grid.addLine(to: CGPoint(x: size.width, y: size.height * f))
                ctx.stroke(grid, with: .color(Theme.grid), lineWidth: 1)
            }
            var lowLine = Path()
            lowLine.move(to: CGPoint(x: 0, y: size.height * (1 - low)))
            lowLine.addLine(to: CGPoint(x: size.width, y: size.height * (1 - low)))
            ctx.stroke(lowLine, with: .color(Theme.danger), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            let span = max(1, end.timeIntervalSince(start))
            let visible = points.filter { $0.date >= start }
            // Carry the last level from before the range in from the left edge.
            var series = visible.map { CGPoint(x: size.width * CGFloat($0.date.timeIntervalSince(start) / span), y: size.height * (1 - $0.level)) }
            if let before = points.last(where: { $0.date < start }) { series.insert(CGPoint(x: 0, y: size.height * (1 - before.level)), at: 0) }
            guard let first = series.first, let last = series.last else { return }
            series.append(CGPoint(x: size.width, y: last.y))
            var line = Path()
            line.move(to: first)
            for p in series.dropFirst() { line.addLine(to: p) }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: first.x, y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .color(Theme.bat.opacity(0.16)))
            ctx.stroke(line, with: .color(Theme.bat), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

enum DeviceRange: CaseIterable {
    case h24, d7, d30

    var seconds: TimeInterval { [86_400, 7 * 86_400, 30 * 86_400][index] }
    var title: String { [L10n.Range.h24, L10n.Range.d7, L10n.Range.d30][index] }
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
        PanelHeader(module: .bluetooth, subtitle: L10n.Bluetooth.deviceCount(bt.connected.count))
        if bt.withBattery.isEmpty {
            Well { Text(L10n.Bluetooth.noDevices).foregroundStyle(Theme.faint).frame(height: 36).padding(.horizontal, 12) }
        } else {
            EvenGrid(columns: 3, hSpacing: 8, vSpacing: 14) {
                ForEach(bt.withBattery) { d in
                    let low = BluetoothText.isLow(d, prefs)
                    VStack(spacing: 6) {
                        ZStack {
                            Ring(fraction: d.level ?? 0, color: low ? Theme.danger : Theme.bat, size: 52, lineWidth: 4)
                            HStack(spacing: 2) {
                                if d.charging { FilledIcon(d: Icons.chargingBolt, width: 8, height: 11).foregroundStyle(Theme.bat) }
                                Text(Format.percent(d.level ?? 0)).ui(14, 500).kerning(-0.28)
                            }
                            .foregroundStyle(low ? Theme.danger : Theme.text)
                        }
                        Text(d.name).ui(12).foregroundStyle(Theme.sub).lineLimit(1).truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(BluetoothText.a11y(d, low: low))
                }
            }
            .padding(.top, 2)
        }
        if p.showBuds {
            ForEach(bt.connected.filter(\.hasBuds)) { d in
                PanelSection(title: d.name) {
                    CellStrip(cells: BluetoothText.buds(d), fill: Theme.well, radius: 12, compact: true)
                }
            }
        }
        if p.showHistory, let d = MenuBarText.lowestDevice(monitor.snapshot) {
            PanelSection(title: d.name, right: L10n.Range.last24h) {
                Well {
                    WellChart(labels: [L10n.Range.ago24h, L10n.Range.ago12h, L10n.Range.now]) {
                        DeviceBatteryChart(points: BluetoothStore.shared.history(d.id), start: Date().addingTimeInterval(-86_400), end: Date(), low: p.lowLevel)
                            .accessibilityLabel(L10n.Bluetooth.chartA11y(d.name, L10n.Range.h24, Format.percent(p.lowLevel)))
                    }
                }
            }
        }
        if p.showDisconnected && !bt.disconnected.isEmpty {
            PanelSection(title: L10n.Bluetooth.disconnected) {
                Well(padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)) {
                    ForEach(bt.disconnected) { d in
                        HStack(spacing: 10) {
                            LineIcon(d: Icons.device(d.kind), size: 16, lineWidth: 1.3)
                            Text(d.name).foregroundStyle(Theme.text).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            if let seen = BluetoothText.lastSeen(d.lastSeen) { Text(seen).ui(12).lineLimit(1) }
                        }
                        .foregroundStyle(Theme.sub)
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
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
    @State private var range: DeviceRange = .d7
    @State private var chosen: String?

    var body: some View {
        let bt = monitor.snapshot.bluetooth
        let prefs = settings.prefs
        let low = prefs.bluetooth.lowLevel
        MonitorPageLayout(module: .bluetooth) {
            VStack(alignment: .leading, spacing: 0) {
                if bt.withBattery.isEmpty {
                    Text(L10n.Bluetooth.noDevices).ui(13).foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity, alignment: .leading).frame(height: 40)
                } else {
                    EvenGrid(minWidth: 76, hSpacing: 4, vSpacing: 16) {
                        ForEach(bt.withBattery) { DeviceTile(device: $0, low: BluetoothText.isLow($0, prefs)) }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))

            ForEach(bt.connected.filter(\.hasBuds)) { d in
                Section(title: d.name) {
                    CellStrip(cells: BluetoothText.buds(d))
                }
            }

            let devices = bt.connected + bt.disconnected
            if let device = devices.first(where: { $0.id == chosen }) ?? MenuBarText.lowestDevice(monitor.snapshot) ?? devices.first {
                VStack(alignment: .leading, spacing: 12) {
                    RangeRow {
                        Segmented(label: L10n.Range.label, options: DeviceRange.allCases.map { ($0, $0.title) }, selection: $range, style: .range)
                            .fixedSize()
                    } trailing: {
                        MenuPill(label: L10n.Bluetooth.device, options: devices.map { ($0.id, $0.name) },
                                 selection: Binding(get: { device.id }, set: { chosen = $0 }))
                    }
                    let end = Date()
                    ChartPanel(height: 124, alert: .bluetoothLow, alertLine: low) {
                        DeviceBatteryChart(points: BluetoothStore.shared.history(device.id), start: end.addingTimeInterval(-range.seconds), end: end, low: low)
                            .accessibilityElement()
                            .accessibilityLabel(L10n.Bluetooth.chartA11y(device.name, range.title, Format.percent(low)))
                    }
                }
            }

            if !bt.disconnected.isEmpty {
                Section(title: L10n.Bluetooth.disconnected, right: L10n.Battery.deviceCount(bt.disconnected.count)) {
                    VStack(spacing: 0) {
                        DividedRows {
                            ForEach(bt.disconnected) { DisconnectedRow(device: $0) }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
                }
            }
        }
    }
}

/// Ring with the device's icon, then its name, battery and time left.
private struct DeviceTile: View {
    var device: BluetoothDevice
    var low: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Ring(fraction: device.level ?? 0, color: low ? Theme.danger : Theme.bat, size: 56, lineWidth: 4, forceButt: true)
                LineIcon(d: Icons.device(device.kind), size: 18, lineWidth: 1.4)
            }
            VStack(spacing: 0) {
                Text(device.name).ui(12).lineLimit(1).truncationMode(.tail)
                HStack(spacing: 4) {
                    if device.charging { FilledIcon(d: Icons.chargingBolt, width: 8, height: 11).foregroundStyle(Theme.bat) }
                    Text(Format.percent(device.level ?? 0)).ui(15, 500)
                }
                .foregroundStyle(low ? Theme.danger : Theme.text)
                .frame(height: 20)
                .padding(.top, 2)
                if let estimate = BluetoothText.estimate(device) {
                    Text(estimate).ui(12).foregroundStyle(low ? Theme.danger : Theme.sub).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BluetoothText.a11y(device, low: low))
    }
}

/// A paired device that isn't connected: when Hum last saw it, and its battery then.
private struct DisconnectedRow: View {
    var device: BluetoothDevice

    var body: some View {
        HStack(spacing: 12) {
            LineIcon(d: Icons.device(device.kind), size: 16, lineWidth: 1.4)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.well))
            VStack(alignment: .leading, spacing: 0) {
                Text(device.name).foregroundStyle(Theme.text).lineLimit(1)
                if let seen = BluetoothText.lastSeen(device.lastSeen) { Text(L10n.Bluetooth.lastConnected(seen)).ui(12) }
            }
            Spacer(minLength: 8)
            if let level = device.level {
                HStack(spacing: 10) {
                    BatteryGlyph(level: level, fill: Theme.faint, rim: Theme.faint, rimOpacity: 1)
                        .frame(width: 25, height: 12)
                    Text(Format.percent(level)).frame(width: 40, alignment: .trailing)
                }
            }
        }
        .foregroundStyle(Theme.sub)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Overview

/// The overview's Bluetooth card content: up to four devices, the lowest first.
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
