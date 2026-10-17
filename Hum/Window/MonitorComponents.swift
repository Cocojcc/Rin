import SwiftUI

/// Page title row: icon chip, 22 pt title, headline value on the right.
struct PageHeader<Value: View>: View {
    var icon: String?
    var title: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 10) {
            if let icon { IconChip(d: icon, size: 30, iconSize: 16, radius: 8) }
            Text(title).font(.system(size: 22, weight: .bold)).kerning(-0.4).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            value
        }
        .frame(height: 34)
    }
}

extension PageHeader where Value == EmptyView {
    init(icon: String?, title: String) {
        self.init(icon: icon, title: title) { EmptyView() }
    }
}

struct RangePicker: View {
    @Binding var range: TimeRange
    var options: [TimeRange] = TimeRange.allCases

    var body: some View {
        SegmentedPicker(label: L10n.Range.label, options: options.map { ($0, $0.title) }, selection: $range)
            .fixedSize()
    }
}

/// Row of value-over-label stats under a chart.
struct StatsRow: View {
    var items: [(String, String)]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                StatBlock(value: item.0, label: item.1)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct CardTitle: View {
    var text: String
    var right: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.sub)
            Spacer()
            if let right { Text(right).font(.system(size: 11)).foregroundStyle(Theme.faint) }
        }
    }
}

/// "占用 CPU 最多" list on monitor pages: icon, name, bar, value; quit controls on hover / right click.
struct WindowProcessList: View {
    var title: String
    var right: String? = nil
    var processes: [ProcessUsage]
    var metric: ProcessMetric
    var color: Color
    var quitCenter = QuitCenter.shared
    @State private var hovered: String?

    var body: some View {
        Card(padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.sub)
                Spacer()
                if let right { Text(right).font(.system(size: 11)).foregroundStyle(Theme.faint) }
            }
            .frame(height: 30)
            if processes.isEmpty {
                Text(L10n.Panel.noProcesses).foregroundStyle(Theme.faint).frame(height: 32)
            }
            let maxValue = max(processes.map(metric.value).max() ?? 1, 0.0001)
            ForEach(processes) { p in
                if quitCenter.states[p.id] == .unresponsive {
                    ConfirmForceQuitRow(process: p, value: metric.text(p)).padding(.vertical, 3)
                } else {
                    row(p, fraction: metric.value(p) / maxValue)
                }
            }
            if let toast = quitCenter.toast {
                QuitToast(toast: toast).padding(.vertical, 4)
            }
        }
    }

    private func row(_ p: ProcessUsage, fraction: Double) -> some View {
        let isHover = hovered == p.id && !p.isSystem
        return HStack(spacing: 10) {
            ProcessIcon(process: p, size: 22)
            Text(p.name).lineLimit(1).truncationMode(.tail).frame(width: 150, alignment: .leading)
            MeterBar(fraction: fraction, color: color)
            if isHover {
                Button(quitCenter.states[p.id] == .quitting ? L10n.Panel.quitting : L10n.Panel.quit) { quitCenter.quit(p) }
                    .controlSize(.small)
                    .accessibilityLabel(L10n.Panel.quitNamed(p.name))
            }
            Text(metric.text(p)).fontWeight(.semibold).monospacedDigit().frame(width: 72, alignment: .trailing)
        }
        .frame(height: 32)
        .overlay(alignment: .top) { Hairline() }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = p.id } else if hovered == p.id { hovered = nil }
        }
        .contextMenu { ProcessContextMenu(process: p) }
        .accessibilityElement(children: .combine)
    }
}

/// Circular gauge with the percentage in the middle (overview cards, disk page).
struct RingGauge: View {
    var fraction: Double
    var color: Color
    var size: CGFloat = 64
    var lineWidth: CGFloat = 7
    var label: String

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label).font(Fonts.big(size * 0.23)).foregroundStyle(color).monospacedDigit()
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Monitor pages observe the clock tick so charts advance even when values are flat.
struct LiveTick {
    static func touch() { _ = Monitor.shared.tick }
}
