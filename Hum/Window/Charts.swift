import Charts
import SwiftUI

struct ChartSeries: Identifiable {
    var id: String
    var points: [ChartPoint]
    var color: Color
    var fill: Double = 0.14
    var lineWidth: CGFloat = 1.5
}

/// Single-series time chart with a soft fill and three grid lines, no axes.
struct TimeChart: View {
    var points: [ChartPoint]
    var range: TimeRange
    var color: Color
    var maxValue: Double

    var body: some View {
        MonitorChart(series: [ChartSeries(id: "v", points: points, color: color)], range: range, maxValue: maxValue, showTimeAxis: false)
    }
}

/// Time chart for monitor pages: area + line series over a fixed time window, optional hover
/// readout. `maxValue` nil scales to the data (used for throughput).
struct MonitorChart: View {
    var series: [ChartSeries]
    var range: TimeRange
    var maxValue: Double?
    var showTimeAxis = true
    var markers: [PeakMarker] = []
    var selectedMarker: Date? = nil
    var markerColor: Color = Theme.cpu
    var hoverText: ((Date) -> [String])? = nil
    var onTap: ((Date) -> Void)? = nil
    @State private var hoverDate: Date?

    private var now: Date { Date() }

    var body: some View {
        let end = Date()
        let start = end.addingTimeInterval(-range.seconds)
        let peak = maxValue ?? max(series.flatMap { $0.points.map(\.value) }.max() ?? 1, 1) * 1.15
        Chart {
            ForEach(series) { s in
                ForEach(s.points) { p in
                    AreaMark(x: .value("t", p.date), yStart: .value("v0", 0), yEnd: .value("v", min(p.value, peak)), series: .value("s", s.id))
                        .foregroundStyle(s.color.opacity(s.fill))
                        .interpolationMethod(.linear)
                    LineMark(x: .value("t", p.date), y: .value("v", min(p.value, peak)), series: .value("s", s.id))
                        .foregroundStyle(s.color)
                        .lineStyle(StrokeStyle(lineWidth: s.lineWidth, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.linear)
                }
            }
            if let selectedMarker {
                RuleMark(x: .value("t", selectedMarker))
                    .foregroundStyle(Theme.cross)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(markers) { m in
                PointMark(x: .value("t", m.date), y: .value("v", min(m.value, peak)))
                    .symbol {
                        if m.date == selectedMarker {
                            Circle().fill(markerColor).frame(width: 10, height: 10)
                                .overlay(Circle().stroke(markerColor.opacity(0.28), lineWidth: 4).frame(width: 14, height: 14))
                        } else {
                            Circle().fill(Theme.group).frame(width: 8, height: 8)
                                .overlay(Circle().strokeBorder(markerColor, lineWidth: 2))
                        }
                    }
            }
            if let hoverDate {
                RuleMark(x: .value("t", hoverDate))
                    .foregroundStyle(Theme.cross)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...peak)
        .chartYAxis {
            AxisMarks(values: [peak * 0.25, peak * 0.5, peak * 0.75]) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Theme.grid)
            }
        }
        .chartXAxis {
            if showTimeAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisValueLabel {
                        if let d = value.as(Date.self) { Text(axisLabel(d)).font(.system(size: 10)).foregroundStyle(Theme.faint) }
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            if let hoverText {
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let onTap, let frame = proxy.plotFrame,
                                  let date: Date = proxy.value(atX: location.x - geo[frame].origin.x) else { return }
                            onTap(date)
                        }
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let frame = proxy.plotFrame else { return }
                                let x = location.x - geo[frame].origin.x
                                hoverDate = proxy.value(atX: x, as: Date.self)
                            case .ended:
                                hoverDate = nil
                            }
                        }
                    if let hoverDate, let frame = proxy.plotFrame, let x = proxy.position(forX: hoverDate) {
                        let lines = hoverText(hoverDate)
                        let plot = geo[frame]
                        let left = x + plot.origin.x
                        ChartTooltip(lines: lines)
                            .fixedSize()
                            .position(x: min(max(left + (left > plot.width * 0.6 ? -94 : 94), 90), plot.maxX - 90), y: plot.minY + 40)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private func axisLabel(_ d: Date) -> String {
        range == .d7 ? d.formatted(.dateTime.month(.defaultDigits).day()) : Format.time(d)
    }
}

/// Floating readout: first line is the time, the rest are values.
struct ChartTooltip: View {
    var lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                Text(line)
                    .font(.system(size: 12, weight: i == 0 ? .regular : .semibold))
                    .foregroundStyle(i == 0 ? Theme.sub : Theme.text)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 168, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.tip).shadow(color: .black.opacity(0.16), radius: 10, y: 6))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.tipRim, lineWidth: 0.5))
    }
}
