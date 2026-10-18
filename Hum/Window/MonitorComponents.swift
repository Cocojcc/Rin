import SwiftUI

/// Plain page title (20 / 600) for pages without a module header.
struct PageTitle<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(title).ui(20, 600).kerning(-0.2).accessibilityAddTraits(.isHeader)
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

    var body: some View {
        Segmented(label: L10n.Range.label, options: options.map { ($0, $0.title) }, selection: $range, style: .range)
            .fixedSize()
    }
}

/// Range control on the left, legend or a link on the right; the chart panel underneath.
struct RangeRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) { leading }
            Spacer(minLength: 0)
            trailing
        }
    }
}

/// Legend items under the range control (12 pt, 16 apart, 14 from the right edge).
struct ChartLegend: View {
    var items: [LegendItem]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    item.swatch
                    Text(item.label).foregroundStyle(Theme.sub)
                    if let value = item.value { Text(value).fontWeight(.medium).foregroundStyle(Theme.text) }
                }
                .fixedSize()
            }
        }
        .ui(12)
        .padding(.trailing, 14)
    }
}

struct LegendItem {
    enum Shape { case dot, bar, square, outline }
    var color: Color
    var label: String
    var value: String? = nil
    var shape: Shape = .dot
    var opacity: Double = 1

    @ViewBuilder var swatch: some View {
        switch shape {
        case .dot: Circle().fill(color.opacity(opacity)).frame(width: 8, height: 8)
        case .bar: RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color.opacity(opacity)).frame(width: 12, height: 8)
        case .square: RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color.opacity(opacity)).frame(width: 8, height: 8)
        case .outline: RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Theme.faint, lineWidth: 1.5).frame(width: 8, height: 8)
        }
    }
}

/// Chart in an 18 pt panel that bleeds to the edges (12 pt above the plot).
struct ChartPanel<Chart: View>: View {
    var height: CGFloat
    @ViewBuilder var chart: Chart

    var body: some View {
        chart
            .frame(height: height)
            .padding(.top, 12)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Parts side by side with 2 pt gaps, each a rounded 6 pt bar (CPU, memory, power, volumes).
struct StackedBar: View {
    var parts: [(Double, Color)]
    var height: CGFloat = 6
    var gap: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let visible = parts.filter { $0.0 > 0 }
            let total = max(visible.map(\.0).reduce(0, +), 0.0001)
            let gaps = CGFloat(max(visible.count - 1, 0)) * gap
            HStack(spacing: gap) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, p in
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous).fill(p.1)
                        .frame(width: max(0, (geo.size.width - gaps) * p.0 / total))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Label left, value right (13 pt; the value 500).
struct ValueLine: View {
    var label: String
    var value: String
    var labelColor: Color = Theme.text
    var valueColor: Color = Theme.text
    var swatch: LegendItem? = nil
    var height: CGFloat? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: 6) {
                if let swatch { swatch.swatch.alignmentGuide(.firstTextBaseline) { $0[.bottom] - 0.5 } }
                Text(label).foregroundStyle(swatch == nil ? labelColor : Theme.sub).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(value).fontWeight(.medium).foregroundStyle(valueColor).lineLimit(1).fixedSize()
        }
        .ui(13)
        .frame(height: height)
        .accessibilityElement(children: .combine)
    }
}

/// Zones along a 3 pt track with a knob at the current value (memory pressure, temperatures).
struct ZoneTrack: View {
    var zones: [(Double, Color)]
    var position: Double
    var knob: Color
    var zoneOpacity: Double = 0.45

    var body: some View {
        GeometryReader { geo in
            let total = max(zones.map(\.0).reduce(0, +), 0.0001)
            let gaps = CGFloat(max(zones.count - 1, 0)) * 2
            ZStack(alignment: .topLeading) {
                HStack(spacing: 2) {
                    ForEach(Array(zones.enumerated()), id: \.offset) { _, z in
                        Capsule().fill(z.1.opacity(zoneOpacity)).frame(width: (geo.size.width - gaps) * z.0 / total)
                    }
                }
                .frame(height: 3)
                .padding(.top, 2.5)
                Circle().fill(knob)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(Theme.raised, lineWidth: 2).padding(-2))
                    .offset(x: geo.size.width * min(1, max(0, position)) - 4)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// Four equal segments, the first `level + 1` lit (thermal state).
struct LevelSegments: View {
    var level: Int
    var color: Color
    var height: CGFloat = 4
    var gap: CGFloat = 4

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(i <= level ? color : Theme.track).frame(height: height)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Ring with a centered value (rings on the overview, CPU, GPU and memory pages).
struct PageRing: View {
    var segments: [Ring.Segment]
    var size: CGFloat
    var lineWidth: CGFloat
    var text: String
    var textSize: CGFloat = 15

    var body: some View {
        ZStack {
            Ring(segments: segments, size: size, lineWidth: lineWidth, forceButt: true)
            Text(text).ui(textSize, 500).lineLimit(1)
        }
        .frame(width: size, height: size)
    }
}

/// Top processes on a monitor page: rows split by hairlines, name column, meter, one or two values.
/// Hovering a row swaps the meter for Quit; right click has the rest.
struct ProcessTable: View {
    var processes: [ProcessUsage]
    var fraction: (ProcessUsage) -> Double
    var color: Color
    var value: (ProcessUsage) -> String
    var valueWidth: CGFloat = 72
    var secondary: ((ProcessUsage) -> String)? = nil
    var secondaryWidth: CGFloat = 72
    var rowHeight: CGFloat = 34
    var quitCenter = QuitCenter.shared
    @State private var hovered: String?

    var body: some View {
        let stuck = processes.filter { quitCenter.states[$0.id] == .unresponsive }
        let rest = processes.filter { quitCenter.states[$0.id] != .unresponsive }
        VStack(spacing: 6) {
            ForEach(stuck) { ConfirmForceQuitRow(process: $0, value: value($0)) }
            if !rest.isEmpty || stuck.isEmpty {
                VStack(spacing: 0) {
                    if processes.isEmpty {
                        Text(L10n.Panel.noProcesses).ui(13).foregroundStyle(Theme.faint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: rowHeight)
                    }
                    DividedRows {
                        ForEach(rest) { row($0) }
                    }
                }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            }
        }
    }

    private func row(_ p: ProcessUsage) -> some View {
        let isHover = hovered == p.id && !p.isSystem
        return HStack(spacing: 10) {
            HStack(spacing: 10) {
                ProcessIcon(process: p, size: 18)
                Text(p.name).lineLimit(1).truncationMode(.tail)
            }
            .frame(width: 158, alignment: .leading)
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
                MeterBar(fraction: fraction(p), color: color)
            }
            Text(value(p)).fontWeight(.medium).lineLimit(1).frame(width: valueWidth, alignment: .trailing)
            if let secondary {
                Text(secondary(p)).foregroundStyle(Theme.sub).lineLimit(1).frame(width: secondaryWidth, alignment: .trailing)
            }
        }
        .ui(13)
        .frame(height: rowHeight)
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
                    Text(label(d)).ui(12).foregroundStyle(Theme.sub).fixedSize()
                        .position(x: x, y: 7)
                }
                Text(L10n.Range.now).ui(12).foregroundStyle(Theme.sub).fixedSize()
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
