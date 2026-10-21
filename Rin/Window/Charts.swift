import Charts
import SwiftUI

struct ChartSeries: Identifiable {
    var id: String
    var points: [ChartPoint]
    var color: Color
    var fill: Double = 0.13
    var lineWidth: CGFloat = 2
    var opacity: Double = 1
    var dash: [CGFloat] = []
}

/// Time chart for monitor pages: area + line series over a fixed time window, three grid
/// lines, no axes (the panel edge is the frame). Optional peak markers and hover readout.
struct MonitorChart: View {
    var series: [ChartSeries]
    var range: TimeRange
    /// nil scales to the data (throughput).
    var maxValue: Double?
    var markers: [PeakMarker] = []
    var selectedMarker: Date? = nil
    var markerColor: Color = Theme.cpu
    var hoverText: ((Date) -> [String])? = nil
    var onTap: ((Date) -> Void)? = nil
    /// Lines for a tooltip pinned to the selected marker (the peak lookback).
    var pinnedTip: [String]? = nil
    /// Fixed value domain (the mirrored network chart plots -1...1).
    var domain: ClosedRange<Double>? = nil
    /// Grid line values; three evenly spaced lines when nil.
    var gridValues: [Double]? = nil
    /// Horizontal rule at 0 (mirrored charts) and a dashed threshold line.
    var centerLine = false
    var threshold: (Double, Color)? = nil
    /// Shaded time spans behind the series (charging on the battery chart).
    var bands: [ClosedRange<Date>] = []
    var bandColor: Color = Theme.bat
    @State private var hoverDate: Date?

    /// Longest step between two points that still reads as one line: a little over the
    /// slowest reading pace (15 s at rest) for the raw ranges, a few buckets for the others.
    private var maxGap: TimeInterval {
        switch range {
        case .m5: return 30
        case .m30: return 60
        case .h1: return 120
        case .h24: return 180
        case .d7: return 900
        }
    }

    /// The points split wherever the gap between neighbours is longer than `maxGap`.
    private func runs(_ points: [ChartPoint]) -> [[ChartPoint]] {
        var out: [[ChartPoint]] = []
        for p in points {
            if let last = out.last?.last, p.date.timeIntervalSince(last.date) <= maxGap {
                out[out.count - 1].append(p)
            } else {
                out.append([p])
            }
        }
        return out
    }

    var body: some View {
        let end = Date()
        let start = end.addingTimeInterval(-range.seconds)
        let peak = domain?.upperBound ?? maxValue ?? max(series.flatMap { $0.points.map(\.value) }.max() ?? 1, 1) * 1.15
        let floor = domain?.lowerBound ?? 0
        Chart {
            ForEach(Array(bands.enumerated()), id: \.offset) { _, band in
                RectangleMark(xStart: .value("t0", band.lowerBound), xEnd: .value("t1", band.upperBound),
                              yStart: .value("v0", floor), yEnd: .value("v1", peak))
                    .foregroundStyle(bandColor.opacity(0.1))
            }
            ForEach(series) { s in
                // Each unbroken run is its own line, so time nothing was read stays empty.
                ForEach(Array(runs(s.points).enumerated()), id: \.offset) { k, run in
                    ForEach(run) { p in
                        let v = min(max(p.value, floor), peak)
                        let key = "\(s.id)#\(k)"
                        if s.fill > 0 {
                            AreaMark(x: .value("t", p.date), yStart: .value("v0", 0), yEnd: .value("v", v), series: .value("s", key))
                                .foregroundStyle(s.color.opacity(s.fill))
                                .interpolationMethod(.linear)
                        }
                        LineMark(x: .value("t", p.date), y: .value("v", v), series: .value("s", key))
                            .foregroundStyle(s.color.opacity(s.opacity))
                            .lineStyle(StrokeStyle(lineWidth: s.lineWidth, lineCap: s.dash.isEmpty ? .round : .butt, lineJoin: .round, dash: s.dash))
                            .interpolationMethod(.linear)
                    }
                }
            }
            if centerLine {
                RuleMark(y: .value("c", 0)).foregroundStyle(Theme.cross).lineStyle(StrokeStyle(lineWidth: 1))
            }
            if let threshold {
                RuleMark(y: .value("th", threshold.0)).foregroundStyle(threshold.1).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
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
                                .background(Circle().fill(Theme.raised).frame(width: 16, height: 16))
                                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        } else {
                            Circle().fill(Theme.raised).frame(width: 7, height: 7)
                                .overlay(Circle().strokeBorder(markerColor, lineWidth: 1.5))
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
        .chartYScale(domain: floor...peak)
        .chartYAxis {
            AxisMarks(values: gridValues ?? [peak * 0.25, peak * 0.5, peak * 0.75]) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Theme.grid)
            }
        }
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { $0.frame(maxWidth: .infinity, maxHeight: .infinity) }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plotFrame = proxy.plotFrame {
                    let plot = geo[plotFrame]
                    if let hoverText {
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { location in
                                guard let onTap, let date: Date = proxy.value(atX: location.x - plot.origin.x) else { return }
                                onTap(date)
                            }
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location): hoverDate = proxy.value(atX: location.x - plot.origin.x, as: Date.self)
                                case .ended: hoverDate = nil
                                }
                            }
                        if let hoverDate, let x = proxy.position(forX: hoverDate) {
                            tip(hoverText(hoverDate), anchorX: x + plot.origin.x, plot: plot)
                        }
                    }
                    if hoverDate == nil, let pinnedTip, let selectedMarker, let x = proxy.position(forX: selectedMarker) {
                        tip(pinnedTip, anchorX: x + plot.origin.x, plot: plot)
                    }
                }
            }
        }
    }

    private func tip(_ lines: [String], anchorX: CGFloat, plot: CGRect) -> some View {
        let left = anchorX + 16 + 176 > plot.maxX ? anchorX - 16 - 176 : anchorX + 16
        return ChartTooltip(lines: lines)
            .fixedSize()
            .position(x: max(plot.minX + 88, left + 88), y: plot.minY + 6 + 40)
            .allowsHitTesting(false)
    }
}

/// Raised readout: first line is the time with the value on the right, then process rows.
struct ChartTooltip: View {
    var lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                let parts = line.components(separatedBy: "\t")
                HStack(alignment: .firstTextBaseline) {
                    Text(parts[0]).foregroundStyle(i == 0 ? Theme.sub : Theme.text)
                    Spacer(minLength: 8)
                    if parts.count > 1 { Text(parts[1]).ui(i == 0 ? 15 : 12, 500) }
                }
                .ui(12)
                .padding(.bottom, i == 0 && lines.count > 1 ? 5 : 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 176, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.raised).raisedShadow())
    }
}
