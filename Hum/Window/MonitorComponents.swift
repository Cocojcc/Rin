import SwiftUI

/// Monitor page header: small grey title, 44 pt value, controls on the right (bottom aligned).
struct MonitorHeader<Trailing: View>: View {
    var title: String
    var value: String
    var unit: String
    var secondLine: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).ui(13, 500).foregroundStyle(Theme.sub).accessibilityAddTraits(.isHeader)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).ui(44, 500).kerning(-1.32).lineLimit(1)
                    if !unit.isEmpty { Text(unit).ui(18).foregroundStyle(Theme.sub).lineLimit(1) }
                }
                .padding(.top, 6)
                .fixedSize()
                if let secondLine {
                    Text(secondLine).ui(15).foregroundStyle(Theme.sub).padding(.top, 4).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 14)
    }
}

extension MonitorHeader where Trailing == EmptyView {
    init(title: String, value: String, unit: String, secondLine: String? = nil) {
        self.init(title: title, value: value, unit: unit, secondLine: secondLine) { EmptyView() }
    }
}

/// Plain page title (24 / 500) for pages without a headline value.
struct PageTitle<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(title).ui(24, 500).kerning(-0.48).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing
        }
        .frame(height: 36)
        .padding(.horizontal, 14)
    }
}

extension PageTitle where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

struct RangeControl: View {
    @Binding var range: TimeRange
    var options: [TimeRange] = TimeRange.allCases
    var width: CGFloat = 320

    var body: some View {
        Segmented(label: L10n.Range.label, options: options.map { ($0, $0.title) }, selection: $range, style: .range)
            .frame(width: width)
    }
}

/// Chart in an 18 pt panel that bleeds to the edges, legend underneath.
struct ChartBlock<Chart: View>: View {
    var height: CGFloat
    var legend: [(Color, String, String?)] = []
    @ViewBuilder var chart: Chart

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            chart
                .frame(height: height)
                .padding(.top, 12)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            if !legend.isEmpty {
                HStack(spacing: 16) {
                    ForEach(Array(legend.enumerated()), id: \.offset) { _, item in
                        LegendDot(color: item.0, label: item.1, value: item.2)
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal, 14)
            }
        }
    }
}

/// Stat row: value over label in equal columns (120 pt minimum).
struct StatsGrid: View {
    var items: [(String, String, Color?)]
    var valueSize: CGFloat = 18

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12, alignment: .leading)], alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                StatBlock(value: item.0, label: item.1, valueSize: valueSize, valueColor: item.2 ?? Theme.text)
            }
        }
        .padding(.horizontal, 14)
    }
}

/// Top-process list on a panel. Hovering a row raises it and offers Quit; right click has the rest.
struct ProcessListPanel: View {
    var processes: [ProcessUsage]
    var metric: ProcessMetric
    var color: Color
    var rowHeight: CGFloat = 34
    var nameWidth: CGFloat = 130
    var valueWidth: CGFloat = 60
    var rowPadding: CGFloat = 10
    var fill: Color = Theme.panel
    var radius: CGFloat = 16
    var quitCenter = QuitCenter.shared
    @State private var hovered: String?

    var body: some View {
        let maxValue = max(processes.map(metric.value).max() ?? 1, 0.0001)
        let stuck = processes.filter { quitCenter.states[$0.id] == .unresponsive }
        let rest = processes.filter { quitCenter.states[$0.id] != .unresponsive }
        VStack(spacing: 6) {
            // An app that didn't quit asks for confirmation above the list.
            ForEach(stuck) { ConfirmForceQuitRow(process: $0, value: metric.text($0)) }
            if !rest.isEmpty || stuck.isEmpty {
                VStack(spacing: 0) {
                    if processes.isEmpty {
                        Text(L10n.Panel.noProcesses).ui(13).foregroundStyle(Theme.faint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, rowPadding)
                            .frame(height: rowHeight)
                    }
                    ForEach(rest) { row($0, fraction: metric.value($0) / maxValue) }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            }
        }
    }

    private func row(_ p: ProcessUsage, fraction: Double) -> some View {
        let isHover = hovered == p.id && !p.isSystem
        return HStack(spacing: 10) {
            ProcessIcon(process: p, size: 18)
            Text(p.name).ui(13, isHover ? 500 : 400).lineLimit(1).truncationMode(.tail)
                .frame(width: nameWidth, alignment: .leading)
            if isHover {
                Spacer(minLength: 0)
                Button {
                    quitCenter.quit(p)
                } label: {
                    Text(quitCenter.states[p.id] == .quitting ? L10n.Panel.quitting : L10n.Panel.quit)
                        .ui(12)
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.well))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Panel.quitNamed(p.name))
            } else {
                MeterBar(fraction: fraction, color: color)
            }
            Text(metric.text(p)).ui(13, 500).lineLimit(1).frame(width: valueWidth, alignment: .trailing)
        }
        .padding(.horizontal, rowPadding)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHover ? Theme.raised : Color.clear)
                .raisedShadow(isHover)
        )
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = p.id } else if hovered == p.id { hovered = nil }
        }
        .contextMenu { ProcessContextMenu(process: p) }
        .accessibilityElement(children: .combine)
    }
}

/// Small time labels under a 24 h / 7 d chart.
struct TimeAxisLabels: View {
    var range: TimeRange

    var body: some View {
        GeometryReader { geo in
            let now = Date()
            let start = now.addingTimeInterval(-range.seconds)
            let marks = TimeAxisLabels.marks(range: range, now: now)
            ZStack(alignment: .topLeading) {
                ForEach(marks, id: \.self) { d in
                    let x = geo.size.width * CGFloat(d.timeIntervalSince(start) / range.seconds)
                    Text(label(d)).ui(11).foregroundStyle(Theme.sub).fixedSize()
                        .position(x: x, y: 7)
                }
                Text(L10n.Range.now).ui(11).foregroundStyle(Theme.sub).fixedSize()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    private func label(_ d: Date) -> String {
        range == .d7 ? d.formatted(.dateTime.month(.defaultDigits).day()) : Format.time(d)
    }

    static func marks(range: TimeRange, now: Date) -> [Date] {
        let cal = Calendar.current
        let start = now.addingTimeInterval(-range.seconds)
        var out: [Date] = []
        if range == .d7 {
            var d = cal.startOfDay(for: start).addingTimeInterval(86_400)
            while d < now.addingTimeInterval(-43_200) { out.append(d); d.addTimeInterval(86_400 * 2) }
        } else {
            // Every 6 hours on the clock, like 18:00 / 0:00 / 6:00 / 12:00.
            var d = cal.date(bySetting: .minute, value: 0, of: start) ?? start
            while cal.component(.hour, from: d) % 6 != 0 || d <= start { d.addTimeInterval(3600) }
            while d < now.addingTimeInterval(-3600) { out.append(d); d.addTimeInterval(6 * 3600) }
        }
        return out
    }
}
