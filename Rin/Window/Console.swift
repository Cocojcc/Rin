import SwiftUI

// Building blocks: big numbers, label / value pairs, thin level bars, stacked bars, and charts:
// smooth lines over a faint wash of their own color, with no grid or times, only what means
// something on them (an alert's limit, the scale's top).

// MARK: - Numbers

/// A reading at one of the big sizes: a page's lead at 56, a dropdown's at 44, figures at 48 / 36 / 34 / 28 / 26 / 22.
/// The larger, the lighter, with tight tracking; its unit quiet beside it. A big lead reading sets
/// its figures proportionally, so "31" has no hole in it.
struct BigValue: View {
    static let lead: CGFloat = 56, panelLead: CGFloat = 44

    var value: String
    var unit: String? = nil
    var size: CGFloat = 28
    var color: Color = Theme.text
    /// nil: only the big ones; a clock keeps its figures even so they don't jitter.
    var proportional: Bool? = nil

    private var weight: CGFloat { size >= 44 ? 300 : size >= 24 ? 400 : 500 }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: unit == "%" || unit == "°" ? 2 : 4) {
            Text(value).ui(size, weight, proportional: proportional ?? (size >= 34)).kerning(-0.04 * size).foregroundStyle(color).lineLimit(1).fixedSize()
            // The unit gives way first when room runs out.
            if let unit, !unit.isEmpty { Text(unit).ui(max(13, (size / 4).rounded(.down))).foregroundStyle(Theme.sub).lineLimit(1).truncationMode(.tail) }
        }
        // The system font's line is about 1.2 × its size; the design sets big figures solid.
        .padding(.vertical, size >= 20 ? -size * 0.08 : 0)
    }
}

/// A figure at full strength with its unit quiet ("88.8%", "4.4 GB", "↓ 1.1 MB/s"): an arrow in
/// front stays grey too. Text that isn't a figure and a unit shows as it is.
struct Reading: View {
    var text: String
    var size: CGFloat = 14
    var weight: CGFloat = 500
    var color: Color = Theme.text

    private static let units: Set<String> = ["%", "°", "°C", "°F", "B/s", "KB/s", "MB/s", "GB/s", "bps", "Kbps", "Mbps", "Gbps", "KB", "MB", "GB", "TB", "W", "rpm", "MHz", "GHz", "ms"]

    /// (grey lead, figure, grey unit); nil when the text isn't a figure and a unit.
    static func split(_ text: String) -> (String, String, String)? {
        var rest = Substring(text)
        var lead = ""
        if let first = rest.first, first == "↓" || first == "↑" {
            lead = String(first) + " "
            rest = rest.dropFirst().drop { $0 == " " }
        }
        let figure = rest.prefix { $0.isNumber || $0 == "." || $0 == "," }
        let unit = rest.dropFirst(figure.count)
        guard !figure.isEmpty, units.contains(unit.trimmingCharacters(in: .whitespaces)) else { return nil }
        return (lead, String(figure), String(unit))
    }

    var body: some View {
        if let (lead, figure, unit) = Self.split(text) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if !lead.isEmpty { Text(lead).ui(size).foregroundStyle(Theme.sub) }
                Text(figure).ui(size, weight).foregroundStyle(color)
                Text(unit).ui(size).foregroundStyle(Theme.sub)
            }
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .combine)
        } else {
            Text(text).ui(size, weight).foregroundStyle(color).lineLimit(1)
        }
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
    var height: CGFloat = 2
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
    var height: CGFloat = 2

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

/// A chart: bars (one per time slot, series drawn from the baseline back to front), an area, or
/// mirrored (the first series up from the middle, the second down).
struct ConsoleChart: View {
    /// `mirroredArea`: the first series' area up from the middle, the second's down.
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
    /// Words on the chart, right aligned: (level 0...1, text).
    var labels: [(Double, String)] = []
    /// How far the chart's words sit in from its edges: it runs to the window's, the page's text doesn't.
    var inset: CGFloat = 0
    /// A mirrored chart's line through the middle.
    var midline = true
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

    /// Leaves the room a line needs at the top and bottom of the plot.
    private static let pad: CGFloat = 2

    /// A page's main curve: its time range, across the whole window.
    init(kind: Kind, series: [ChartSeries], range: TimeRange, maxGap: TimeInterval? = nil, maxValue: Double, bottomMax: Double = 1, height: CGFloat,
         labels: [(Double, String)] = [], rules: [ChartRule] = [], bands: [ClosedRange<Date>] = [], markers: [PeakMarker] = [],
         selectedMarker: Date? = nil, markerColor: Color = Theme.green, hoverText: ((Date) -> [String])? = nil,
         onTap: ((Date) -> Void)? = nil, pinnedTip: [String]? = nil) {
        self.kind = kind
        self.series = series
        span = range.seconds
        self.maxGap = maxGap ?? range.maxGap
        self.maxValue = maxValue
        self.bottomMax = bottomMax
        self.height = height
        self.labels = labels
        inset = 32
        self.rules = rules
        self.bands = bands
        self.markers = markers
        self.selectedMarker = selectedMarker
        self.markerColor = markerColor
        self.hoverText = hoverText
        self.onTap = onTap
        self.pinnedTip = pinnedTip
    }

    /// A short window (the dropdowns' last minute).
    init(kind: Kind, series: [ChartSeries], span: TimeInterval, maxGap: TimeInterval? = nil, maxValue: Double, bottomMax: Double = 1, height: CGFloat,
         midline: Bool = true, rules: [ChartRule] = [], bands: [ClosedRange<Date>] = [], slot: CGFloat = 5) {
        self.kind = kind
        self.series = series
        self.span = span
        self.maxGap = maxGap ?? max(30, span / 40)
        self.maxValue = maxValue
        self.bottomMax = bottomMax
        self.height = height
        self.midline = midline
        self.rules = rules
        self.bands = bands
        self.slot = slot
    }

    /// A round top for a scale: 1, 2, 4 or 5 times a power of ten, at least `value`.
    static func niceMax(_ value: Double) -> Double {
        guard value > 0, value.isFinite else { return 1 }
        let p = pow(10, floor(log10(value)))
        for m in [1.0, 2, 4, 5, 10] where m * p >= value { return m * p }
        return 10 * p
    }

    var body: some View {
        plot
            .frame(height: height)
            .frame(maxHeight: height == nil ? .infinity : nil)
    }

    private var plot: some View {
        GeometryReader { geo in
            let size = geo.size
            let end = Date()
            let start = end.addingTimeInterval(-span)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    drawBands(&ctx, size, start: start)
                    switch kind {
                    case .bars: drawBars(&ctx, size, start: start)
                    case .area: drawArea(&ctx, size, start: start)
                    case .mirrored: drawMirrored(&ctx, size, start: start)
                    case .mirroredArea: drawMirroredArea(&ctx, size, start: start)
                    }
                    drawMarkers(&ctx, size, start: start)
                    if midline && (kind == .mirrored || kind == .mirroredArea) {
                        ctx.fill(Path(CGRect(x: 0, y: (size.height / 2).rounded() - 0.5, width: size.width, height: 1)), with: .color(Theme.line))
                    }
                    if let hoverX {
                        ctx.fill(Path(CGRect(x: hoverX - 0.5, y: 0, width: 1, height: size.height)), with: .color(Theme.cross))
                    }
                }
                ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                    ruleView(rule, size: size)
                }
                ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                    Text(label.1).ui(12).foregroundStyle(Theme.sub).lineLimit(1).fixedSize()
                        .frame(width: size.width - inset, alignment: .trailing)
                        .position(x: (size.width - inset) / 2, y: size.height * (1 - label.0))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
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
            .stroke(rule.color, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
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
                .offset(x: inset, y: max(-12, y - 20))
            }
        }
    }

    // MARK: Drawing

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
            drawRuns(&ctx, s, runs(s, top: maxValue, width: size.width, start: start),
                     base: size.height - Self.pad, extent: size.height - Self.pad * 2, floor: size.height)
        }
    }

    private func drawMirroredArea(_ ctx: inout GraphicsContext, _ size: CGSize, start: Date) {
        let half = size.height / 2 - Self.pad
        for (k, s) in series.prefix(2).enumerated() {
            let r = runs(s, top: k == 0 ? maxValue : bottomMax, width: size.width, start: start)
            drawRuns(&ctx, s, r, base: size.height / 2, extent: k == 0 ? half : -half, floor: size.height / 2)
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

    /// Fills each run back to `floor` with a faint wash of its own color and strokes its edge as a
    /// smooth curve; `extent` is how far a full level reaches from `base` (negative draws downward).
    /// A series with no line width is a fill alone; one with no fill a line alone.
    private func drawRuns(_ ctx: inout GraphicsContext, _ s: ChartSeries, _ runs: [[(x: CGFloat, level: CGFloat)]], base: CGFloat, extent: CGFloat, floor: CGFloat) {
        for run in runs where run.count > 1 {
            let points = run.map { CGPoint(x: $0.x, y: base - $0.level * extent) }
            let line = Self.smooth(points)
            if s.fill > 0 {
                var fill = line
                fill.addLine(to: CGPoint(x: points[points.count - 1].x, y: floor))
                fill.addLine(to: CGPoint(x: points[0].x, y: floor))
                fill.closeSubpath()
                ctx.fill(fill, with: .color(s.color.opacity(ctx.environment.colorScheme == .light ? 0.05 : 0.08)))
            }
            if s.lineWidth > 0 {
                ctx.stroke(line, with: .color(s.color.opacity(s.opacity)),
                           style: StrokeStyle(lineWidth: s.lineWidth, lineCap: .round, lineJoin: .round, dash: s.dash))
            }
        }
        // A reading on its own has no line to draw, so it shows as a dot.
        for run in runs where run.count == 1 && s.lineWidth > 0 {
            let p = CGPoint(x: run[0].x, y: base - run[0].level * extent), r = s.lineWidth
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(s.color))
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
