import SwiftUI

// Building blocks: big tabular numbers, label / value pairs, thin level bars, stacked bars, and
// charts with their scale (dashed grid at the labelled levels, values in a gutter on the right,
// times underneath), drawn as smooth lines over a neutral wash.

// MARK: - Numbers

/// A reading at one of the big sizes (56 a page's lead, 44 / 36 figures, 22–28 small), tight
/// tracking, its unit 14 and grey beside it.
struct BigValue: View {
    var value: String
    var unit: String? = nil
    var size: CGFloat = 28
    var color: Color = Theme.text
    var unitSize: CGFloat = 14

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).ui(size, 500).kerning(-0.035 * size).foregroundStyle(color).lineLimit(1).fixedSize()
            // The unit gives way first when room runs out.
            if let unit, !unit.isEmpty { Text(unit).ui(unitSize).foregroundStyle(Theme.sub).lineLimit(1).truncationMode(.tail) }
        }
        // The system font's line is about 1.2 × its size; the design sets big figures solid.
        .padding(.vertical, size >= 20 ? -size * 0.075 : 0)
    }
}

/// "用户 15%": grey label, the value in 500, 6 apart; an optional color dot in front.
struct KeyValue: View {
    var label: String
    var value: String
    var valueColor: Color = Theme.text
    var key: Color? = nil
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 6) {
            if let key { Circle().fill(key).frame(width: 8, height: 8) }
            Text(label).ui(size).foregroundStyle(Theme.sub)
            if !value.isEmpty { Text(value).ui(size, 500).foregroundStyle(valueColor) }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Levels

/// A level as one thin rounded bar on a track (process lists, devices, temperatures); 4 tall
/// by default, the overview's device rows 6.
struct LevelBar: View {
    var fraction: Double
    var color: Color
    var height: CGFloat = 4
    var trackColor: Color = Theme.track

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(trackColor)
                .overlay(alignment: .leading) {
                    Capsule().fill(color).frame(width: geo.size.width * min(max(fraction, 0), 1))
                }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Parts side by side with 2 pt gaps in one thin rounded bar (CPU, memory, power).
struct SegmentBar: View {
    var parts: [(Double, Color)]
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let visible = parts.filter { $0.0 > 0 }
            let total = max(visible.map(\.0).reduce(0, +), 0.0001)
            let gaps = CGFloat(max(visible.count - 1, 0)) * 2
            HStack(spacing: 2) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, p in
                    Rectangle().fill(p.1).frame(width: max(0, (geo.size.width - gaps) * p.0 / total))
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Charts

extension TimeRange {
    /// Labels under a chart, oldest first, ending with "现在".
    var axisLabels: [String] {
        let ago: [String]
        switch self {
        case .m5: ago = [5, 4, 3, 2, 1].map { L10n.Chart.minutesAgo($0) }
        case .m30: ago = [30, 25, 20, 15, 10, 5].map { L10n.Chart.minutesAgo($0) }
        case .h1: ago = [60, 45, 30, 15].map { L10n.Chart.minutesAgo($0) }
        case .h24: ago = [24, 18, 12, 6].map { L10n.Chart.hoursAgo($0) }
        case .d7: ago = [7, 6, 5, 4, 3, 2, 1].map { L10n.Chart.daysAgo($0) }
        }
        return ago + [L10n.Range.now]
    }

    /// Longest step between two points that still reads as one line: a little over the
    /// slowest reading pace (15 s at rest) for the raw ranges, a few buckets for the others.
    var maxGap: TimeInterval {
        switch self {
        case .m5: return 30
        case .m30: return 60
        case .h1: return 120
        case .h24: return 180
        case .d7: return 900
        }
    }
}

/// A dashed rule across a chart at a level of its scale: an alert's limit (with a tag that opens
/// the rule) or a zone's edge.
struct ChartRule {
    var fraction: Double
    var color: Color
    var label: String? = nil
    var bell = false
    var help: String? = nil
    var action: (() -> Void)? = nil
}

/// A chart with its scale. Bars (one per time slot, series drawn from the baseline back to
/// front), an area, or mirrored bars (the first series up from the middle, the second down).
struct ConsoleChart: View {
    /// `mirroredArea`: the first series' area up from the middle, the second's down (the small charts).
    enum Kind { case bars, area, mirrored, mirroredArea }

    var kind: Kind
    var series: [ChartSeries]
    var span: TimeInterval
    var maxGap: TimeInterval = 30
    /// Top of the scale (the top half's when mirrored).
    var maxValue: Double
    /// The bottom half's scale when mirrored.
    var bottomMax: Double = 1
    /// nil fills the height it is offered.
    var height: CGFloat? = nil
    /// Values in the gutter on the right: (level 0...1, text).
    var yLabels: [(Double, String)] = []
    var gutter: CGFloat = 32
    /// Extra dashed levels; the labelled levels always get one.
    var grid: [Double] = []
    var baseline = false
    /// A mirrored chart's line through the middle.
    var midline = true
    var xLabels: [String]? = nil
    var rules: [ChartRule] = []
    var bands: [ClosedRange<Date>] = []
    var bandColor: Color = Theme.chargeBand
    var markers: [PeakMarker] = []
    var selectedMarker: Date? = nil
    var markerColor: Color = Theme.green
    var hoverText: ((Date) -> [String])? = nil
    var onTap: ((Date) -> Void)? = nil
    var pinnedTip: [String]? = nil
    /// Width of one bar's slot, the bar taking two thirds of it.
    var slot: CGFloat = 6
    @State private var hoverX: CGFloat?
    @Environment(\.chartTint) private var tint

    init(kind: Kind, series: [ChartSeries], range: TimeRange, maxValue: Double, bottomMax: Double = 1, height: CGFloat? = nil,
         yLabels: [(Double, String)] = [], gutter: CGFloat = 36, grid: [Double] = [], baseline: Bool = false,
         showTimes: Bool = true, rules: [ChartRule] = [], bands: [ClosedRange<Date>] = [], markers: [PeakMarker] = [],
         selectedMarker: Date? = nil, markerColor: Color = Theme.green, hoverText: ((Date) -> [String])? = nil,
         onTap: ((Date) -> Void)? = nil, pinnedTip: [String]? = nil) {
        self.kind = kind
        self.series = series
        span = range.seconds
        maxGap = range.maxGap
        self.maxValue = maxValue
        self.bottomMax = bottomMax
        self.height = height
        self.yLabels = yLabels
        self.gutter = gutter
        self.grid = grid
        self.baseline = baseline
        xLabels = showTimes ? range.axisLabels : nil
        self.rules = rules
        self.bands = bands
        self.markers = markers
        self.selectedMarker = selectedMarker
        self.markerColor = markerColor
        self.hoverText = hoverText
        self.onTap = onTap
        self.pinnedTip = pinnedTip
    }

    /// A short window (the dropdowns' last minute) with its own labels.
    init(kind: Kind, series: [ChartSeries], span: TimeInterval, maxValue: Double, bottomMax: Double = 1, height: CGFloat,
         xLabels: [String]?, grid: [Double] = [], baseline: Bool = false, midline: Bool = true, bands: [ClosedRange<Date>] = [], slot: CGFloat = 5) {
        self.kind = kind
        self.series = series
        self.span = span
        maxGap = max(30, span / 40)
        self.maxValue = maxValue
        self.bottomMax = bottomMax
        self.height = height
        gutter = 0
        self.grid = grid
        self.baseline = baseline
        self.midline = midline
        self.xLabels = xLabels
        self.bands = bands
        self.slot = slot
    }

    /// Any window with its own time labels and the full scale (a device's battery over 30 days).
    init(kind: Kind, series: [ChartSeries], span: TimeInterval, maxGap: TimeInterval, maxValue: Double, height: CGFloat,
         yLabels: [(Double, String)], xLabels: [String], rules: [ChartRule] = []) {
        self.kind = kind
        self.series = series
        self.span = span
        self.maxGap = maxGap
        self.maxValue = maxValue
        self.height = height
        self.yLabels = yLabels
        self.xLabels = xLabels
        self.rules = rules
    }

    /// A round top for a scale: 1, 2, 4 or 5 times a power of ten, at least `value`.
    static func niceMax(_ value: Double) -> Double {
        guard value > 0, value.isFinite else { return 1 }
        let p = pow(10, floor(log10(value)))
        for m in [1.0, 2, 4, 5, 10] where m * p >= value { return m * p }
        return 10 * p
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                plot
                    .frame(height: height)
                    .frame(maxHeight: height == nil ? .infinity : nil)
                if gutter > 0 {
                    yAxis.frame(width: gutter).frame(height: height).frame(maxHeight: height == nil ? .infinity : nil)
                }
            }
            if let xLabels {
                HStack(spacing: 0) {
                    ForEach(Array(xLabels.enumerated()), id: \.offset) { i, t in
                        if i > 0 { Spacer(minLength: 4) }
                        Text(t).lineLimit(1).fixedSize()
                    }
                }
                .ui(12)
                .foregroundStyle(Theme.sub)
                .padding(.trailing, gutter)
                .accessibilityHidden(true)
            }
        }
    }

    /// Each value centered on its level, like the design's scale.
    private var yAxis: some View {
        GeometryReader { geo in
            ForEach(Array(yLabels.enumerated()), id: \.offset) { _, label in
                Text(label.1).ui(12).foregroundStyle(Theme.sub).lineLimit(1).fixedSize()
                    .frame(width: gutter, alignment: .trailing)
                    .position(x: gutter / 2, y: geo.size.height * (1 - label.0))
            }
        }
        .accessibilityHidden(true)
    }

    private var plot: some View {
        GeometryReader { geo in
            let size = geo.size
            let end = Date()
            let start = end.addingTimeInterval(-span)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    drawGrid(&ctx, size)
                    drawBands(&ctx, size, start: start)
                    switch kind {
                    case .bars: drawBars(&ctx, size, start: start)
                    case .area: drawArea(&ctx, size, start: start)
                    case .mirrored: drawMirrored(&ctx, size, start: start)
                    case .mirroredArea: drawMirroredArea(&ctx, size, start: start)
                    }
                    drawMarkers(&ctx, size, start: start)
                    if let hoverX {
                        ctx.fill(Path(CGRect(x: hoverX - 0.5, y: 0, width: 1, height: size.height)), with: .color(Theme.cross))
                    }
                }
                ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                    ruleView(rule, size: size)
                }
                if hoverText != nil || onTap != nil {
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let p): hoverX = min(max(p.x, 0), size.width)
                            case .ended: hoverX = nil
                            }
                        }
                        .onTapGesture { p in
                            onTap?(start.addingTimeInterval(span * Double(p.x / max(size.width, 1))))
                        }
                }
                if let hoverText, let hoverX {
                    tip(hoverText(start.addingTimeInterval(span * Double(hoverX / max(size.width, 1)))), x: hoverX, size: size)
                } else if let pinnedTip, let selectedMarker {
                    tip(pinnedTip, x: CGFloat(selectedMarker.timeIntervalSince(start) / span) * size.width, size: size)
                }
            }
        }
    }

    private func tip(_ lines: [String], x: CGFloat, size: CGSize) -> some View {
        let left = x + 16 + 176 > size.width ? x - 16 - 176 : x + 16
        return ChartTooltip(lines: lines)
            .fixedSize()
            .position(x: max(88, left + 88), y: min(46, size.height / 2))
            .allowsHitTesting(false)
    }

    /// A dashed line across the plot; its words, if any, sit just above it on the left and open the rule.
    private func ruleView(_ rule: ChartRule, size: CGSize) -> some View {
        let y = (size.height * (1 - min(max(rule.fraction, 0), 1))).rounded() + 0.5
        return ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
            }
            .stroke(rule.color, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            if let label = rule.label {
                Button { rule.action?() } label: {
                    HStack(spacing: 3) {
                        if rule.bell { LineIcon(d: Icons.bell, size: 11, lineWidth: 1.6) }
                        Text(label).ui(12)
                    }
                    .foregroundStyle(rule.color)
                    .frame(height: 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(rule.help ?? "")
                .fixedSize()
                // A line near the top of a short chart puts its words in the gap above the plot.
                .offset(y: max(-12, y - 20))
            }
        }
    }

    // MARK: Drawing

    private func dashed(_ ctx: inout GraphicsContext, y: CGFloat, width: CGFloat, color: Color) {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: y))
        p.addLine(to: CGPoint(x: width, y: y))
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    private func drawGrid(_ ctx: inout GraphicsContext, _ size: CGSize) {
        for g in Set(grid + yLabels.map(\.0)) {
            dashed(&ctx, y: min(size.height - 0.5, (size.height * (1 - g)).rounded() + 0.5), width: size.width, color: Theme.grid)
        }
        if baseline { ctx.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)), with: .color(Theme.grid)) }
        if midline && (kind == .mirrored || kind == .mirroredArea) {
            ctx.fill(Path(CGRect(x: 0, y: (size.height / 2).rounded() - 0.5, width: size.width, height: 1)), with: .color(Theme.grid))
        }
    }

    private func drawBands(_ ctx: inout GraphicsContext, _ size: CGSize, start: Date) {
        for band in bands {
            let x0 = CGFloat(band.lowerBound.timeIntervalSince(start) / span) * size.width
            let x1 = CGFloat(band.upperBound.timeIntervalSince(start) / span) * size.width
            let r = CGRect(x: max(0, x0), y: 0, width: max(0, min(size.width, x1) - max(0, x0)), height: size.height)
            ctx.fill(Path(r), with: .color(bandColor))
        }
    }

    /// Each series averaged into the chart's time slots; nil where nothing was read.
    private func binned(_ points: [ChartPoint], count: Int, start: Date) -> [Double?] {
        var sum = [Double](repeating: 0, count: count), n = [Int](repeating: 0, count: count)
        let width = span / Double(count)
        for p in points {
            let t = p.date.timeIntervalSince(start)
            guard t >= 0, !p.value.isNaN else { continue }
            let i = min(count - 1, Int(t / width))
            sum[i] += p.value
            n[i] += 1
        }
        return (0..<count).map { n[$0] > 0 ? sum[$0] / Double(n[$0]) : nil }
    }

    private func drawBars(_ ctx: inout GraphicsContext, _ size: CGSize, start: Date) {
        let count = max(10, Int(size.width / slot))
        let w = size.width / CGFloat(count)
        let top = max(maxValue, 0.0001)
        for s in series {
            let bins = binned(s.points, count: count, start: start)
            for (i, v) in bins.enumerated() {
                guard let v, v > 0 else { continue }
                let h = min(1, v / top) * size.height
                let r = CGRect(x: CGFloat(i) * w + w * 0.17, y: size.height - h, width: w * 0.66, height: h)
                ctx.fill(Path(r), with: .color(s.color.opacity(s.opacity)))
            }
        }
    }

    private func drawMirrored(_ ctx: inout GraphicsContext, _ size: CGSize, start: Date) {
        let count = max(10, Int(size.width / slot))
        let w = size.width / CGFloat(count)
        let half = size.height / 2 - 1
        for (k, s) in series.prefix(2).enumerated() {
            let top = max(k == 0 ? maxValue : bottomMax, 0.0001)
            let bins = binned(s.points, count: count, start: start)
            for (i, v) in bins.enumerated() {
                guard let v, v > 0 else { continue }
                let h = max(1, min(1, v / top) * half)
                let y = k == 0 ? size.height / 2 - 1 - h : size.height / 2 + 1
                ctx.fill(Path(CGRect(x: CGFloat(i) * w + w * 0.17, y: y, width: w * 0.66, height: h)), with: .color(s.color))
            }
        }
    }

    /// Series drawn in order, so a stack is the total first and its lower part over it.
    private func drawArea(_ ctx: inout GraphicsContext, _ size: CGSize, start: Date) {
        for s in series {
            drawRuns(&ctx, s, runs(s, top: maxValue, width: size.width, start: start), base: size.height, extent: size.height)
        }
    }

    private func drawMirroredArea(_ ctx: inout GraphicsContext, _ size: CGSize, start: Date) {
        let half = size.height / 2 - 1
        for (k, s) in series.prefix(2).enumerated() {
            let r = runs(s, top: k == 0 ? maxValue : bottomMax, width: size.width, start: start)
            drawRuns(&ctx, s, r, base: size.height / 2, extent: k == 0 ? half : -half)
        }
    }

    /// A series' readings as (x, share of `top`), split into runs where readings stop for longer than `maxGap`.
    private func runs(_ s: ChartSeries, top: Double, width: CGFloat, start: Date) -> [[(x: CGFloat, level: CGFloat)]] {
        let top = max(top, 0.0001)
        var out: [[(x: CGFloat, level: CGFloat)]] = []
        var last: Date?
        for p in s.points where !p.value.isNaN {
            let x = CGFloat(p.date.timeIntervalSince(start) / span) * width
            guard x >= -1 else { continue }
            let level = CGFloat(min(max(p.value / top, 0), 1))
            if let l = last, p.date.timeIntervalSince(l) <= maxGap, !out.isEmpty {
                out[out.count - 1].append((x, level))
            } else {
                out.append([(x, level)])
            }
            last = p.date
        }
        return out.map { downsample($0, width: width) }
    }

    /// Readings averaged into about `points` steps across the plot, so a second-by-second series
    /// draws as a calm curve rather than a scribble.
    var points = 72

    private func downsample(_ run: [(x: CGFloat, level: CGFloat)], width: CGFloat) -> [(x: CGFloat, level: CGFloat)] {
        let step = max(width / CGFloat(max(points, 2)), 1)
        guard run.count > 2, let last = run.last, last.x - run[0].x > step * 2, CGFloat(run.count) > (last.x - run[0].x) / step else { return run }
        var out: [(x: CGFloat, level: CGFloat)] = []
        var bin = Int((run[0].x / step).rounded(.down)), sx: CGFloat = 0, sl: CGFloat = 0, n: CGFloat = 0
        for p in run {
            let b = Int((p.x / step).rounded(.down))
            if b != bin, n > 0 {
                out.append((sx / n, sl / n))
                sx = 0; sl = 0; n = 0
                bin = b
            }
            sx += p.x; sl += p.level; n += 1
        }
        if n > 0 { out.append((sx / n, sl / n)) }
        // Keep the run's ends where they are, so the curve still reaches "现在".
        if let f = run.first, out.first?.x != f.x { out.insert(f, at: 0) }
        out[out.count - 1] = last
        return out
    }

    /// Fills each run back to `base` with the wash (on white a faint tint of the page's module, when
    /// it has one; neutral when dark) and strokes its edge as a smooth curve;
    /// `extent` is how far a full level reaches (negative draws downward). A series with no line
    /// width is a fill alone; one with no fill a line alone.
    private func drawRuns(_ ctx: inout GraphicsContext, _ s: ChartSeries, _ runs: [[(x: CGFloat, level: CGFloat)]], base: CGFloat, extent: CGFloat) {
        for run in runs where run.count > 1 {
            let points = run.map { CGPoint(x: $0.x, y: base - $0.level * extent) }
            let line = Self.smooth(points)
            if s.fill > 0 {
                var fill = line
                fill.addLine(to: CGPoint(x: points[points.count - 1].x, y: base))
                fill.addLine(to: CGPoint(x: points[0].x, y: base))
                fill.closeSubpath()
                let wash = ctx.environment.colorScheme == .light ? tint.map { $0.opacity(0.08) } : nil
                ctx.fill(fill, with: .color(wash ?? Theme.area))
            }
            if s.lineWidth > 0 {
                ctx.stroke(line, with: .color(s.color.opacity(s.opacity)),
                           style: StrokeStyle(lineWidth: s.lineWidth, lineCap: .round, lineJoin: .round, dash: s.dash))
            }
        }
    }

    /// A Catmull-Rom curve through the points, as cubic Béziers.
    static func smooth(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        let n = pts.count - 1
        for i in 0..<n {
            let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, n)]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        return path
    }

    private func drawMarkers(_ ctx: inout GraphicsContext, _ size: CGSize, start: Date) {
        let top = max(maxValue, 0.0001)
        for m in markers {
            let x = CGFloat(m.date.timeIntervalSince(start) / span) * size.width
            let y = size.height - CGFloat(min(max(m.value / top, 0), 1)) * size.height
            let r: CGFloat = m.date == selectedMarker ? 5 : 3
            ctx.fill(Path(ellipseIn: CGRect(x: x - r - 2, y: y - r - 2, width: (r + 2) * 2, height: (r + 2) * 2)), with: .color(Theme.panel))
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(markerColor))
        }
    }
}

/// The 0 / 50 / 100 scale most percent charts use.
enum ChartScale {
    static let percent: [(Double, String)] = [(1, "100"), (0.5, "50"), (0, "0")]
}

private struct ShareKey: LayoutValueKey { static let defaultValue: CGFloat = 0 }

extension View {
    /// This child's share of a `ShareRow`'s width; 0 keeps its own width (rules between groups).
    func share(_ weight: CGFloat) -> some View { layoutValue(key: ShareKey.self, value: weight) }
}

/// Children side by side, the width left after the fixed ones split by their shares.
struct ShareRow: Layout {
    var spacing: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 400
        let widths = self.widths(width, subviews)
        let height = zip(subviews, widths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (view, w) in zip(subviews, widths(bounds.width, subviews)) {
            view.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w + spacing
        }
    }

    private func widths(_ total: CGFloat, _ subviews: Subviews) -> [CGFloat] {
        let fixed = subviews.map { $0[ShareKey.self] == 0 ? $0.sizeThatFits(.unspecified).width : 0 }
        let weights = subviews.map { $0[ShareKey.self] }
        let room = max(0, total - fixed.reduce(0, +) - spacing * CGFloat(max(subviews.count - 1, 0)))
        let sum = max(weights.reduce(0, +), 0.0001)
        return zip(fixed, weights).map { $1 > 0 ? room * $1 / sum : $0 }
    }
}

/// The module whose page or dropdown a chart is on: on white its fills take a faint tint of it.
private struct ChartTintKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var chartTint: Color? {
        get { self[ChartTintKey.self] }
        set { self[ChartTintKey.self] = newValue }
    }
}
