import SwiftUI

/// How loud a menu bar item should be. Color in the menu bar is reserved for warnings.
enum BarTone {
    case normal, warn, crit, dim

    var color: Color? {
        switch self {
        case .normal: return nil
        case .warn: return Color(nsColor: Theme.barWarn)
        case .crit: return Color(nsColor: Theme.barCrit)
        case .dim: return Theme.barInk.opacity(0.45)
        }
    }

    var emphasized: Bool { self == .warn || self == .crit }
}

/// Fixed-width text so the item doesn't change width as numbers change.
struct FixedText: View {
    var text: String
    var template: String
    var font: BarFontSpec
    var alignment: Alignment = .trailing

    var body: some View {
        BarText(template, font: font).hidden()
            .overlay(alignment: alignment) { BarText(text, font: font) }
    }
}

/// Text in a widget: in the menu bar it is drawn by `SmoothText`, in settings previews it is
/// ordinary SwiftUI text in the UI font.
struct BarText: View {
    var text: String
    var font: BarFontSpec
    var kerning: CGFloat = 0
    @Environment(\.barTypeface) private var typeface

    init(_ text: String, font: BarFontSpec, kerning: CGFloat = 0) {
        self.text = text
        self.font = font
        self.kerning = kerning
    }

    var body: some View {
        if font.ui {
            Text(text).font(font.font).kerning(kerning).lineLimit(1).fixedSize()
        } else {
            SmoothText(text: text, font: font.nsFont(typeface), kerning: kerning)
        }
    }
}

/// Menu bar text drawn with CoreText and font smoothing on, the way the system and Stats draw
/// theirs. The app turns smoothing off for its windows, and SwiftUI text follows that setting
/// even in an image, which left the small menu bar figures thin and grey.
struct SmoothText: View {
    private let line: CTLine
    private let width: CGFloat
    private let height: CGFloat
    private let baseline: CGFloat
    @Environment(\.colorScheme) private var scheme

    init(text: String, font: NSFont, kerning: CGFloat = 0) {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        if kerning != 0 { attributes[.kern] = kerning }
        line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        width = ceil(CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading)))
        height = ceil(ascent + descent + leading)
        baseline = descent + leading / 2
    }

    var body: some View {
        let line = line, baseline = baseline
        // Smoothing thickens light text on a dark bar more than dark text on a light one, so the
        // glyphs are drawn in the bar's own text color before being painted.
        let ink = CGColor(gray: scheme == .dark ? 1 : 0, alpha: 1)
        Canvas { ctx, size in
            // Draw the glyphs, then paint them with the current foreground style.
            ctx.drawLayer { layer in
                layer.withCGContext { cg in
                    cg.setAllowsFontSmoothing(true)
                    cg.setShouldSmoothFonts(true)
                    cg.setFillColor(ink)
                    cg.textMatrix = .identity
                    cg.translateBy(x: 0, y: size.height)
                    cg.scaleBy(x: 1, y: -1)
                    cg.textPosition = CGPoint(x: 0, y: baseline)
                    CTLineDraw(line, cg)
                }
                layer.blendMode = .sourceIn
                layer.fill(Path(CGRect(origin: .zero, size: size)), with: .foreground)
            }
        }
        .frame(width: width, height: height)
    }
}

/// A widget font: the system font (tabular digits) in the menu bar, Space Grotesk in previews.
struct BarFontSpec {
    var size: CGFloat
    var weight: CGFloat = 400
    var ui = false
    var monospaced = true

    var font: Font {
        if ui { return Fonts.ui(size, weight) }
        let w: Font.Weight = weight >= 600 ? .semibold : weight >= 500 ? .medium : weight <= 300 ? .light : .regular
        return monospaced ? .system(size: size, weight: w).monospacedDigit() : .system(size: size, weight: w)
    }

    /// The menu bar font: SF with tabular digits, or SF Mono when the menu bar is set to monospaced.
    func nsFont(_ typeface: BarTypeface = .system) -> NSFont {
        let w: NSFont.Weight = weight >= 600 ? .semibold : weight >= 500 ? .medium : weight <= 300 ? .light : .regular
        if typeface == .monospaced { return .monospacedSystemFont(ofSize: size, weight: w) }
        return monospaced ? .monospacedDigitSystemFont(ofSize: size, weight: w) : .systemFont(ofSize: size, weight: w)
    }
}

private struct WidgetUIFontKey: EnvironmentKey { static let defaultValue = false }
private struct BarTypefaceKey: EnvironmentKey { static let defaultValue = BarTypeface.system }

extension EnvironmentValues {
    /// Widgets draw in the system font in the menu bar and in Space Grotesk where the settings
    /// window previews them (the design draws the widget strip in the UI font).
    var widgetUIFont: Bool {
        get { self[WidgetUIFontKey.self] }
        set { self[WidgetUIFontKey.self] = newValue }
    }

    /// The menu bar typeface chosen in settings.
    var barTypeface: BarTypeface {
        get { self[BarTypefaceKey.self] }
        set { self[BarTypefaceKey.self] = newValue }
    }
}

enum BarFont {
    static func font(_ size: CGFloat, _ weight: CGFloat = 400, ui: Bool) -> BarFontSpec {
        BarFontSpec(size: size, weight: weight, ui: ui)
    }

    static func value(_ emphasized: Bool = false, ui: Bool = false) -> BarFontSpec { font(13, emphasized ? 600 : 400, ui: ui) }
    /// Two stacked rows (speeds, used / free, read / write): 9 pt light on 9 pt rows, as Stats
    /// draws them.
    static func twoLine(ui: Bool) -> BarFontSpec { font(9, 300, ui: ui) }
    static let twoLineRow: CGFloat = 9
}

/// Mini graph tile (28 × 16): area + line, used by the line and chart widgets.
struct GraphTile: View {
    var values: [Double]
    var secondary: [Double]? = nil
    var color: Color
    var secondaryColor: Color? = nil
    var boxed = true
    var points = 30

    var body: some View {
        Sparkline(values: values, color: color, lineWidth: 1.25, fillOpacity: 0.25, secondary: secondary,
                  secondaryColor: secondaryColor, minCount: points)
            .frame(width: 28, height: 16)
            .background(boxed ? Theme.barInk.opacity(0.08) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Two series in one tile: the first rises from the bottom, the second hangs from the top.
struct MirrorTile: View {
    var first: [Double]
    var second: [Double]
    var firstColor: Color
    var secondColor: Color
    var boxed = true
    var points = 60

    var body: some View {
        Canvas { ctx, size in
            let half = size.height / 2
            func draw(_ data: [Double], _ color: Color, fromTop: Bool) {
                guard !data.isEmpty else { return }
                let count = max(data.count, points)
                let step = size.width / CGFloat(max(count - 1, 1))
                let offset = CGFloat(count - data.count) * step
                var line = Path()
                for (i, v) in data.enumerated() {
                    let h = CGFloat(min(1, max(0, v))) * half
                    let p = CGPoint(x: offset + CGFloat(i) * step, y: fromTop ? h : size.height - h)
                    if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
                }
                var area = line
                area.addLine(to: CGPoint(x: offset + CGFloat(data.count - 1) * step, y: fromTop ? 0 : size.height))
                area.addLine(to: CGPoint(x: offset, y: fromTop ? 0 : size.height))
                area.closeSubpath()
                ctx.fill(area, with: .color(color.opacity(0.3)))
                ctx.stroke(line, with: .color(color), lineWidth: 1)
            }
            draw(first, firstColor, fromTop: false)
            draw(second, secondColor, fromTop: true)
        }
        .frame(width: 28, height: 16)
        .background(boxed ? Theme.barInk.opacity(0.08) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Horizontal capsule meter: 22 × 10 (memory) or 18 × 9 (disk).
struct PillMeter: View {
    var fraction: Double
    var color: Color
    var width: CGFloat = 22
    var height: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .strokeBorder(Theme.barInk.opacity(0.4), lineWidth: 1)
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: (height - 5) / 2, style: .continuous)
                    .fill(color)
                    .frame(width: max(1, (width - 5) * min(1, max(0, fraction))), height: height - 5)
                    .padding(.leading, 2.5)
            }
            .accessibilityHidden(true)
    }
}

/// Vertical bar (5 × 16) with a rim, filling from the bottom.
struct VerticalMeter: View {
    var fraction: Double
    var color: Color
    var boxed = true
    var radius: CGFloat = 1.5

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(boxed ? Theme.barInk.opacity(0.4) : .clear, lineWidth: 1)
            Rectangle().fill(color).frame(height: 16 * min(1, max(0, fraction)))
        }
        .frame(width: 5, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A ring (14 × 14) of segments laid end to end on a faint track: CPU system then user, or
/// one value. Each segment is the color at its own opacity.
struct SplitRing: View {
    var segments: [(fraction: Double, opacity: Double)]
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 14
            let center = CGPoint(x: 7 * s, y: 7 * s)
            let radius = 5.8 * s, width = 2.4 * s
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                       with: .color(color.opacity(0.22)), lineWidth: width)
            var start = 0.0
            for segment in segments {
                let f = min(max(0, segment.fraction), 1 - start)
                guard f > 0 else { continue }
                var arc = Path()
                arc.addArc(center: center, radius: radius, startAngle: .degrees(-90 + 360 * start), endAngle: .degrees(-90 + 360 * (start + f)), clockwise: false)
                ctx.stroke(arc, with: .color(color.opacity(segment.opacity)), lineWidth: width)
                start += f
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}

/// A battery (30 × 14) with the charge as a faint fill and the percentage written inside.
struct BatteryNumber: View {
    var level: Double
    var text: String
    var tint: Color?
    @Environment(\.widgetUIFont) private var ui

    var body: some View {
        Canvas { ctx, _ in
            var rim = ctx
            rim.opacity = 0.5
            rim.stroke(Path(roundedRect: CGRect(x: 0.75, y: 0.75, width: 25.5, height: 12.5), cornerRadius: 3.5), with: .foreground, lineWidth: 1)
            var cap = Path()
            cap.move(to: CGPoint(x: 28.2, y: 5))
            cap.addLine(to: CGPoint(x: 28.2, y: 9))
            rim.stroke(cap, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            var fill = ctx
            fill.opacity = 0.28
            let width = max(1, 22.5 * min(1, max(0, level)))
            fill.fill(Path(roundedRect: CGRect(x: 2.25, y: 2.25, width: width, height: 9.5), cornerRadius: 2),
                      with: tint.map { .color($0) } ?? .foreground)
        }
        .frame(width: 30, height: 14)
        .overlay(alignment: .leading) {
            BarText(text, font: BarFont.font(8.5, 600, ui: ui))
                .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.foreground))
                .frame(width: 27)
        }
        .accessibilityHidden(true)
    }
}

/// Thin bars side by side (3 × 16 each): cores for CPU, sensors for temperatures.
struct BarRow: View {
    var values: [Double]
    var colors: [Color]
    var boxed = true

    var body: some View {
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(values.indices, id: \.self) { i in
                ZStack(alignment: .bottom) {
                    Rectangle().fill(boxed ? Theme.barInk.opacity(0.08) : .clear)
                    Rectangle().fill(colors[min(i, colors.count - 1)]).frame(height: 16 * min(1, max(0, values[i])))
                }
                .frame(width: 3, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Ring meter (13 × 13).
struct RingMeter: View {
    var fraction: Double
    var color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Theme.barInk.opacity(0.4), lineWidth: 2)
            Circle().trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: 2))
                .rotationEffect(.degrees(-90))
        }
        .padding(1.07)
        .frame(width: 13, height: 13)
        .accessibilityHidden(true)
    }
}

/// Pie (15 × 15): a faint outline with a filled sector.
struct PieMeter: View {
    var fraction: Double
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 14
            let center = CGPoint(x: 7 * s, y: 7 * s)
            var rimCtx = ctx
            rimCtx.opacity = 0.45
            rimCtx.stroke(Path(ellipseIn: CGRect(x: 0.7 * s, y: 0.7 * s, width: 12.6 * s, height: 12.6 * s)), with: .foreground, lineWidth: s)
            let f = min(1, max(0, fraction))
            guard f > 0 else { return }
            var sector = Path()
            sector.move(to: center)
            sector.addArc(center: center, radius: 5.8 * s, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * f), clockwise: false)
            sector.closeSubpath()
            ctx.fill(sector, with: .color(color))
        }
        .frame(width: 15, height: 15)
        .accessibilityHidden(true)
    }
}

/// Speedometer (18 × 13): a faint arc, the value arc and a needle.
struct TachoMeter: View {
    var fraction: Double
    var color: Color

    var body: some View {
        Canvas { ctx, _ in
            let center = CGPoint(x: 9, y: 11)
            var track = Path()
            track.addArc(center: center, radius: 7, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            var faint = ctx
            faint.opacity = 0.35
            faint.stroke(track, with: .foreground, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            let f = min(1, max(0, fraction))
            let angle = Angle.degrees(180 + 180 * f)
            var value = Path()
            value.addArc(center: center, radius: 7, startAngle: .degrees(180), endAngle: angle, clockwise: false)
            ctx.stroke(value, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            var needle = Path()
            needle.move(to: center)
            needle.addLine(to: CGPoint(x: center.x + 5 * cos(angle.radians), y: center.y + 5 * sin(angle.radians)))
            ctx.stroke(needle, with: .color(color), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
        .frame(width: 18, height: 13)
        .accessibilityHidden(true)
    }
}

/// Letters stacked vertically (6.5 pt, 5.4 pt rows): the "label" widget and widget labels.
struct VerticalLabel: View {
    var text: String
    @Environment(\.widgetUIFont) private var ui

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(text.prefix(4).enumerated()), id: \.offset) { _, c in
                BarText(String(c), font: BarFont.font(6.5, 500, ui: ui)).frame(height: 5.4)
            }
        }
        .fixedSize()
    }
}

/// One small arrow per row beside each rate (9 pt light, 8 pt rows): the network speed layout.
struct ArrowRows: View {
    var top: String
    var bottom: String
    var topColor: Color = Theme.barInk
    var bottomColor: Color = Theme.barInk
    var upOnTop = true
    var template: String
    var glyph: SpeedGlyph = .arrows
    @Environment(\.widgetUIFont) private var ui

    var body: some View {
        let font = BarFont.twoLine(ui: ui)
        Grid(alignment: .trailing, horizontalSpacing: 3, verticalSpacing: 0) {
            GridRow {
                marker(top: true).foregroundStyle(topColor)
                FixedText(text: top, template: template, font: font).frame(height: BarFont.twoLineRow)
            }
            GridRow {
                marker(top: false).foregroundStyle(bottomColor)
                FixedText(text: bottom, template: template, font: font).frame(height: BarFont.twoLineRow)
            }
        }
    }

    private func marker(top: Bool) -> some View {
        SpeedMark(glyph: glyph, up: top == upOnTop, size: 6, letterSize: 8)
    }
}

/// The mark beside a rate: an arrow, a triangle, a ring (up) or dot (down), or U / D.
struct SpeedMark: View {
    var glyph: SpeedGlyph
    var up: Bool
    var size: CGFloat
    var letterSize: CGFloat
    @Environment(\.widgetUIFont) private var ui

    var body: some View {
        switch glyph {
        case .arrows:
            LineIcon(d: up ? Icons.arrowUpSmall : Icons.arrowDownSmall, size: size, viewBox: 6, lineWidth: 1.1)
        case .triangles:
            SpeedTriangle(up: up).fill(.foreground).frame(width: size, height: size)
        case .dots:
            Group {
                if up { Circle().strokeBorder(.foreground, lineWidth: 1) } else { Circle().fill(.foreground) }
            }
            .frame(width: size, height: size)
        case .letters:
            BarText(up ? L10n.Widget.uploadLetter : L10n.Widget.downloadLetter, font: BarFont.font(letterSize, 500, ui: ui))
        case .none:
            EmptyView()
        }
    }
}

/// A small filled triangle in a 6 × 6 box, pointing up or down.
struct SpeedTriangle: Shape {
    var up: Bool

    func path(in rect: CGRect) -> Path {
        let s = rect.width / 6
        var p = Path()
        if up {
            p.move(to: CGPoint(x: 3 * s, y: 0.9 * s))
            p.addLine(to: CGPoint(x: 5.4 * s, y: 5.1 * s))
            p.addLine(to: CGPoint(x: 0.6 * s, y: 5.1 * s))
        } else {
            p.move(to: CGPoint(x: 3 * s, y: 5.1 * s))
            p.addLine(to: CGPoint(x: 0.6 * s, y: 0.9 * s))
            p.addLine(to: CGPoint(x: 5.4 * s, y: 0.9 * s))
        }
        p.closeSubpath()
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Upload and download with their marks, on two rows or one line: the network speed widget.
struct SpeedPair: View {
    struct Item {
        var up: Bool
        var text: String
        var markColor: Color?
    }

    var items: [Item]
    var template: String
    var options: WidgetOptions
    @Environment(\.widgetUIFont) private var ui

    var body: some View {
        if options.layout == .twoLine {
            VStack(alignment: options.numberAlign == .leading ? .leading : .trailing, spacing: 0) {
                ForEach(items.indices, id: \.self) { i in
                    group(items[i], BarFont.twoLine(ui: ui), mark: 6, letter: 8).frame(height: BarFont.twoLineRow)
                }
            }
        } else {
            HStack(spacing: 8) {
                ForEach(items.indices, id: \.self) { i in
                    group(items[i], BarFont.font(12, 400, ui: ui), mark: 8, letter: 10)
                }
            }
        }
    }

    private func group(_ item: Item, _ font: BarFontSpec, mark: CGFloat, letter: CGFloat) -> some View {
        let glyph = SpeedMark(glyph: options.glyph, up: item.up, size: mark, letterSize: letter)
            .foregroundStyle(item.markColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.foreground))
        return HStack(spacing: options.glyph == .none ? 0 : CGFloat(options.glyphGap)) {
            if !options.glyphAfter { glyph }
            if options.fixedWidth {
                FixedText(text: item.text, template: template, font: font, alignment: options.numberAlign == .leading ? .leading : .trailing)
            } else {
                BarText(item.text, font: font)
            }
            if options.glyphAfter { glyph }
        }
    }
}

// MARK: - Widgets

/// A module's status item: its enabled widgets side by side (tight when merged).
struct MenuBarItemView: View {
    let module: Module
    var monitor = Monitor.shared
    var settings = SettingsStore.shared

    var body: some View {
        let prefs = settings.prefs
        let s = monitor.snapshot
        let tone = MenuBarText.tone(module, s, prefs)
        HStack(spacing: CGFloat(prefs.widgetGap(module))) {
            ForEach(prefs.widgets(module)) { WidgetView(module: module, kind: $0, prefs: prefs) }
        }
        // No side padding, as Stats draws its items: the menu bar adds its own spacing.
        .padding(.horizontal, 0)
        .frame(maxHeight: .infinity)
        .foregroundStyle(tone.color ?? Theme.barInk)
        .environment(\.barTypeface, prefs.menubar.typeface)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MenuBarText.accessibility(module, s, prefs))
    }
}

/// One widget of one module, drawn from the latest snapshot.
struct WidgetView: View {
    let module: Module
    let kind: WidgetKind
    var prefs: Preferences
    var monitor = Monitor.shared
    @Environment(\.widgetUIFont) private var ui

    private var s: Snapshot { monitor.snapshot }
    private var o: WidgetOptions { prefs.options(module, kind) }
    private var tone: BarTone { MenuBarText.tone(module, s, prefs) }
    private var globallyColored: Bool { prefs.menubar.iconColor == .color }

    var body: some View {
        let _ = monitor.tick
        content.fixedSize()
    }

    private var labelText: String { o.labelText.isEmpty ? module.widgetLabel : o.labelText }
    private var valueFont: BarFontSpec { BarFont.value(tone.emphasized, ui: ui) }

    // MARK: Values

    /// The module's headline as 0...1 (pie, tacho, bars).
    private var fraction: Double {
        switch module {
        case .cpu: return s.cpu.total
        case .gpu: return prefs.gpu.valueType == .memory ? WidgetView.vramFraction(s.gpu) : s.gpu.utilization
        case .memory: return s.memory.usedFraction
        case .network: return s.network.connected ? 1 : 0
        case .disk: return MenuBarText.volume(s.disk, prefs.disk.volume)?.usedFraction ?? 0
        case .battery: return s.battery.level
        case .sensors: return (MenuBarText.sensorValue(s.sensors, prefs.sensors.sensor) ?? 0) / 100
        }
    }

    static func vramFraction(_ g: GPUSample) -> Double {
        g.memoryLimit > 0 ? Double(g.memoryUsed) / Double(g.memoryLimit) : 0
    }

    private var valueText: String {
        switch module {
        case .gpu where prefs.gpu.valueType == .memory: return MenuBarText.gigabytes(s.gpu.memoryUsed)
        case .memory where prefs.memory.valueType == .usedGB: return MenuBarText.gigabytes(s.memory.used, binary: true)
        default: return MenuBarText.shortValue(module, s, prefs)
        }
    }

    private var valueTemplate: String {
        switch module {
        case .sensors: return "100°"
        case .gpu where prefs.gpu.valueType == .memory: return "99.9G"
        case .memory where prefs.memory.valueType == .usedGB: return "99.9G"
        default: return "100%"
        }
    }

    private var metric: Metric {
        switch module {
        case .cpu: return .cpu
        case .gpu: return .gpu
        case .memory: return .memory
        case .network: return .netDown
        case .disk: return .diskRead
        case .battery: return .battery
        case .sensors: return .cpuTemp
        }
    }

    /// Settings previews (drawn in the UI font) stay monochrome, as the design draws them.
    private var preview: Bool { ui }

    /// The fill color for a widget: warning tone first, then its color option.
    private func color(_ option: WidgetColor, _ f: Double? = nil) -> Color {
        if preview { return .primary }
        if let t = tone.color { return t }
        if globallyColored && option == .mono { return Theme.barColor(module) }
        switch option {
        case .mono: return Theme.barInk
        case .colored: return Theme.barColor(module)
        case .byValue: return WidgetView.levelColor(module, f ?? fraction, s)
        }
    }

    static func levelColor(_ m: Module, _ f: Double, _ s: Snapshot) -> Color {
        let warn = Color(nsColor: Theme.barWarn), crit = Color(nsColor: Theme.barCrit)
        switch m {
        case .memory:
            switch s.memory.pressure {
            case .normal: return Theme.barCPU
            case .warning: return warn
            case .critical: return crit
            }
        case .battery: return f > 0.5 ? Theme.barCPU : f > 0.2 ? warn : crit
        case .sensors: return f < 0.7 ? Theme.barCPU : f < 0.9 ? warn : crit
        default: return f < 0.6 ? Theme.barCPU : f < 0.85 ? warn : crit
        }
    }

    // MARK: Drawing

    @ViewBuilder private var content: some View {
        switch kind {
        // Icons and graphics: never with a number of their own.
        case .icon: MenuIconView(icon: MenuIcons.icon(module, o.icon), module: module).foregroundStyle(color(.mono))
        case .label: VerticalLabel(text: labelText)
        case .line, .labelLine: line
        case .bar: bar
        case .pie:
            if module == .cpu {
                SplitRing(segments: [(s.cpu.system, 0.55), (s.cpu.user, 1)], color: color(.mono))
            } else {
                PieMeter(fraction: fraction, color: o.monochrome ? Theme.barInk : color(.byValue))
            }
        case .tacho: TachoMeter(fraction: fraction, color: o.monochrome ? Theme.barInk : color(.byValue))
        case .ring:
            if module == .memory {
                RingMeter(fraction: fraction, color: color(o.color))
            } else {
                SplitRing(segments: [(fraction, 1)], color: color(o.color))
            }
        case .pill: PillMeter(fraction: fraction, color: color(o.color), width: module == .memory ? 22 : 18, height: module == .memory ? 10 : 9)
        case .dot: Circle().fill(color(o.color)).frame(width: 7, height: 7)
        case .battery: battery
        case .chart: chart
        case .state: state
        // Numbers
        case .value, .temp, .iconValue: number
        case .mini: mini
        case .memory: memoryPair
        case .speed: module == .network ? AnyView(networkSpeed) : AnyView(diskSpeed)
        case .details: batteryDetails
        case .time: numberText(WidgetView.batteryTime(s.battery, prefs) ?? L10n.Common.dash, template: "10:00")
        case .fan: fan
        case .stack: sensorStack
        case .pair: pair
        case .inside: batteryNumber
        }
    }

    private var mini: some View {
        let align: HorizontalAlignment = o.align == .leading ? .leading : o.align == .trailing ? .trailing : .center
        return VStack(alignment: align, spacing: 0) {
            if o.showLabel { BarText(labelText, font: BarFont.font(7, 300, ui: ui), kerning: 0.3).frame(height: 7) }
            FixedText(text: valueText, template: valueTemplate, font: BarFont.font(11, tone.emphasized ? 600 : 400, ui: ui),
                      alignment: o.align == .leading ? .leading : o.align == .trailing ? .trailing : .center)
                .frame(height: 11)
        }
        .foregroundStyle(color(o.color))
    }

    private var line: some View {
        let points = max(10, o.points)
        let graphColor = color(o.color)
        return HStack(spacing: 4) {
            if module == .cpu && o.graphContent == .userSystem {
                GraphTile(values: monitor.history.last(.cpuUser, count: points).map { $0 / 100 },
                          secondary: monitor.history.last(.cpuSystem, count: points).map { $0 / 100 },
                          color: graphColor, secondaryColor: tone.color ?? Theme.barUp, boxed: o.boxed, points: points)
            } else {
                GraphTile(values: monitor.history.last(metric, count: points).map { $0 / 100 }, color: graphColor, boxed: o.boxed, points: points)
            }
        }
    }

    @ViewBuilder private var bar: some View {
        switch module {
        case .cpu:
            let cores = s.cpu.perCore
            BarRow(values: cores, colors: cores.map { color(o.color, $0) }, boxed: o.boxed)
        case .memory:
            PillMeter(fraction: fraction, color: color(o.color))
        case .disk:
            PillMeter(fraction: fraction, color: color(o.color), width: 18, height: 9)
        default:
            VerticalMeter(fraction: fraction, color: color(o.color), boxed: o.boxed, radius: module == .sensors ? 2.5 : 1.5)
        }
    }

    /// The module's number: percent, gigabytes, free space or temperature, per its settings.
    @ViewBuilder private var number: some View {
        switch module {
        case .disk: diskValue
        case .sensors:
            let reading = MenuBarText.sensorValue(s.sensors, prefs.sensors.sensor)
            numberText(reading.map { Format.temperature($0, unit: prefs.general.temperatureUnit) } ?? L10n.Common.dash, template: "100°")
                .foregroundStyle(color(o.color == .byValue ? .byValue : .mono))
        case .battery:
            let b = s.battery
            if !(o.hidePercentWhenFull && b.onAC && (b.isCharged || b.level >= 0.99)) {
                numberText(Format.percent(b.level), template: "100%")
            }
        default:
            numberText(valueText, template: valueTemplate)
        }
    }

    /// The number just as wide as it is, so the space beside it is exactly the widget gap; or,
    /// when fixed, in room for its widest value (aligned left or right in it).
    @ViewBuilder private func numberText(_ text: String, template: String) -> some View {
        if o.numberFixed {
            FixedText(text: text, template: template, font: valueFont, alignment: o.numberAlign == .leading ? .leading : .trailing)
        } else {
            BarText(text, font: valueFont)
        }
    }

    /// Two figures stacked in the small two-row type.
    private func twoRows(_ rows: [String], template: String) -> some View {
        let font = BarFont.twoLine(ui: ui)
        return VStack(alignment: .trailing, spacing: 0) {
            ForEach(rows.indices, id: \.self) { i in
                FixedText(text: rows[i], template: template, font: font).frame(height: BarFont.twoLineRow)
            }
        }
    }

    @ViewBuilder private var pair: some View {
        switch module {
        case .gpu:
            twoRows([Format.percent(s.gpu.utilization), MenuBarText.gigabytes(s.gpu.memoryUsed)], template: "99.9G")
        default:
            number
        }
    }

    private var batteryLow: Bool {
        let b = s.battery
        return o.colorWhenLow && b.level <= 0.2 && !b.isCharging && !b.onAC
    }

    private var batteryNumber: some View {
        BatteryNumber(level: s.battery.level, text: "\(Int((s.battery.level * 100).rounded()))",
                      tint: batteryLow ? Color(nsColor: Theme.barCrit) : (globallyColored && !preview ? Theme.barBat : nil))
    }

    private var memoryPair: some View {
        let used = MenuBarText.gigabytes(s.memory.used, binary: true)
        let free = MenuBarText.gigabytes(s.memory.total > s.memory.used ? s.memory.total - s.memory.used : 0, binary: true)
        let strip = { (v: String) in o.showSymbol ? v : String(v.dropLast()) }
        let font = BarFont.twoLine(ui: ui)
        return VStack(alignment: .trailing, spacing: 0) {
            FixedText(text: strip(o.freeOnTop ? free : used), template: "99.9G", font: font).frame(height: BarFont.twoLineRow)
            FixedText(text: strip(o.freeOnTop ? used : free), template: "99.9G", font: font).frame(height: BarFont.twoLineRow)
        }
        .foregroundStyle(color(o.color))
    }

    private var networkSpeed: some View {
        let n = s.network
        let unit = prefs.network.speedUnit
        let offline = !n.connected
        let colored = (o.color == .colored || globallyColored) && !offline && tone.color == nil && !preview
        let rates = [(true, n.up), (false, n.down)]
        let items = (o.firstOnTop ? rates : rates.reversed()).map { up, v in
            SpeedPair.Item(up: up, text: offline ? L10n.Common.dash : Format.rate(v, unit: unit, style: o.unitStyle, showUnit: o.showUnit),
                           markColor: colored ? (up ? Theme.barUp : Theme.barDown) : nil)
        }
        return SpeedPair(items: items, template: Format.rateTemplate(unit: unit, style: o.unitStyle, showUnit: o.showUnit), options: o)
            .opacity(offline ? 0.45 : 1)
    }

    private var diskSpeed: some View {
        let d = s.disk
        let colored = (o.color == .colored || globallyColored) && tone.color == nil && !preview
        let format = { (v: Double) in o.showUnit ? Format.rate(v) : Format.rateCompact(v) }
        let rows = [(MenuBarText.readLetter, format(d.read), colored ? Theme.palette(.blue) : Theme.barInk),
                    (MenuBarText.writeLetter, format(d.write), colored ? Theme.palette(.purple) : Theme.barInk)]
        let ordered = o.firstOnTop ? rows : rows.reversed()
        let font = BarFont.twoLine(ui: ui)
        return Group {
            if o.layout == .twoLine {
                Grid(alignment: .leading, horizontalSpacing: 2, verticalSpacing: 0) {
                    ForEach(ordered.indices, id: \.self) { i in
                        GridRow {
                            BarText(ordered[i].0, font: font).foregroundStyle(ordered[i].2.opacity(colored ? 1 : 0.55))
                            FixedText(text: ordered[i].1, template: o.showUnit ? "999 MB/s" : "999M", font: font)
                        }
                        .frame(height: BarFont.twoLineRow)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(ordered.indices, id: \.self) { i in
                        HStack(spacing: 2) {
                            BarText(ordered[i].0, font: BarFont.font(11, 400, ui: ui)).foregroundStyle(ordered[i].2.opacity(colored ? 1 : 0.55))
                            FixedText(text: ordered[i].1, template: o.showUnit ? "999 MB/s" : "999M", font: BarFont.font(11, 400, ui: ui))
                        }
                    }
                }
            }
        }
    }

    private var chart: some View {
        let points = max(10, o.points)
        let colored = globallyColored && tone.color == nil && !preview
        let first: [Double], second: [Double]
        if module == .network {
            first = monitor.history.last(.netDown, count: points)
            second = monitor.history.last(.netUp, count: points)
        } else {
            first = monitor.history.last(.diskRead, count: points)
            second = monitor.history.last(.diskWrite, count: points)
        }
        let peak = max(first.max() ?? 0, second.max() ?? 0, module == .network ? 10_000 : 1_000_000)
        return MirrorTile(first: first.map { $0 / peak }, second: second.map { $0 / peak },
                          firstColor: colored ? Theme.palette(o.firstColor) : (tone.color ?? Theme.barInk),
                          secondColor: colored ? Theme.palette(o.secondColor) : (tone.color ?? Theme.barInk),
                          boxed: o.boxed, points: points)
    }

    private var state: some View {
        // A status dot only means something in color, so it always keeps its two colors.
        Circle().fill(Theme.palette(s.network.connected ? o.firstColor : o.secondColor)).frame(width: 7, height: 7)
    }

    private var diskValue: some View {
        let volume = MenuBarText.volume(s.disk, prefs.disk.volume)
        let text: String
        switch prefs.disk.content {
        case .free:
            let g = volume.map { MenuBarText.gigabytes(UInt64(max(0, $0.available)), decimal: true) } ?? L10n.Common.dash
            text = o.showUnit ? g : String(g.filter { $0.isNumber || $0 == "." })
        case .usedPercent: text = volume.map { Format.percent($0.usedFraction) } ?? L10n.Common.dash
        case .readWrite: text = Format.rateCompact(s.disk.read + s.disk.write)
        }
        return numberText(text, template: "999G")
    }

    private var battery: some View {
        let fill: Color? = batteryLow ? Color(nsColor: Theme.barCrit) : (globallyColored && !preview ? Theme.barBat : nil)
        return BatteryGlyph(level: s.battery.level, charging: o.showBolt && s.battery.isCharging, fill: fill)
    }

    static func batteryTime(_ b: BatterySample, _ prefs: Preferences) -> String? {
        guard let minutes = b.isCharging ? b.minutesToFull : (b.onAC ? nil : b.minutesToEmpty) else { return nil }
        return prefs.battery.timeFormat == .clock ? Format.clockDuration(minutes: minutes) : L10n.Battery.minutesShort(minutes)
    }

    private var batteryDetails: some View {
        let b = s.battery
        let percent = Format.percent(b.level)
        let time = WidgetView.batteryTime(b, prefs) ?? L10n.Common.dash
        let font = BarFont.twoLine(ui: ui)
        return Group {
            switch o.details {
            case .percentAndTime:
                VStack(alignment: .trailing, spacing: 0) {
                    FixedText(text: percent, template: "100%", font: font).frame(height: BarFont.twoLineRow)
                    FixedText(text: time, template: "10:00", font: font).frame(height: BarFont.twoLineRow)
                }
            case .percent: FixedText(text: percent, template: "100%", font: valueFont)
            case .time: FixedText(text: time, template: "10:00", font: valueFont)
            }
        }
    }

    private var fan: some View {
        let f = s.sensors.fans.first
        let text: String
        if let f {
            text = o.fanValue == .rpm ? "\(Int(f.rpm.rounded()))" : Format.percent(f.max > 0 ? f.rpm / f.max : 0)
        } else {
            text = L10n.Common.dash
        }
        return HStack(spacing: 3) {
            if o.showIcon { LineIcon(d: Icons.fan, size: 14, lineWidth: 1.3) }
            numberText(text, template: o.fanValue == .rpm ? "8888" : "100%")
        }
    }

    private var sensorStack: some View {
        let unit = prefs.general.temperatureUnit
        let rows: [(String, String)] = [
            (Module.cpu.widgetLabel, s.sensors.cpuAverage.map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash),
            (Module.gpu.widgetLabel, s.sensors.value(.gpu).map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash),
        ]
        var font = BarFont.font(10, 300, ui: ui)
        font.monospaced = o.monospaced
        let align: Alignment = o.align == .leading ? .leading : o.align == .trailing ? .trailing : .center
        return Group {
            if o.layout == .twoLine {
                Grid(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 0) {
                    ForEach(rows.indices, id: \.self) { i in
                        GridRow {
                            BarText(rows[i].0, font: font).opacity(0.55)
                            FixedText(text: rows[i].1, template: "100°", font: font, alignment: align)
                        }
                        .frame(height: BarFont.twoLineRow)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(rows.indices, id: \.self) { i in
                        HStack(spacing: 2) {
                            BarText(rows[i].0, font: BarFont.font(11, 400, ui: ui)).opacity(0.55)
                            BarText(rows[i].1, font: BarFont.font(11, 400, ui: ui))
                        }
                    }
                }
            }
        }
    }
}

/// Everything in one item: label-over-value columns, the "合并成一项" layout.
struct CombinedMenuBarView: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared

    var body: some View {
        let prefs = settings.prefs
        let s = monitor.snapshot
        let modules = prefs.menubar.order.filter { prefs.showsInMenubar($0) && MenuBarText.available($0, s) }
        HStack(spacing: 11) {
            if modules.isEmpty {
                LineIcon(d: Icons.appMark, size: 16, viewBox: 24, lineWidth: 2.4)
            }
            ForEach(modules) { m in
                column(m, s, prefs)
                    .foregroundStyle(MenuBarText.tone(m, s, prefs).color ?? Theme.barInk)
            }
        }
        .padding(.horizontal, 2)
        .frame(maxHeight: .infinity)
        .environment(\.barTypeface, prefs.menubar.typeface)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MenuBarText.combinedAccessibility(modules, s, prefs))
    }

    @ViewBuilder private func column(_ m: Module, _ s: Snapshot, _ prefs: Preferences) -> some View {
        let tone = MenuBarText.tone(m, s, prefs)
        switch m {
        case .network:
            let offline = !s.network.connected
            let up = offline ? L10n.Common.dash : Format.rateCompact(s.network.up, unit: prefs.network.speedUnit)
            let down = offline ? L10n.Common.dash : Format.rateCompact(s.network.down, unit: prefs.network.speedUnit)
            let upTop = prefs.options(.network, .speed).firstOnTop
            ArrowRows(top: upTop ? up : down, bottom: upTop ? down : up, upOnTop: upTop, template: "999K")
                .opacity(offline ? 0.45 : 1)
        default:
            VStack(spacing: -1) {
                BarText(m.compactLabel, font: BarFont.font(7, 300, ui: false), kerning: 0.3)
                FixedText(text: MenuBarText.shortValue(m, s, prefs), template: m == .sensors ? "100°" : "100%",
                          font: BarFont.font(12, tone.emphasized ? 600 : 400, ui: false), alignment: .center)
            }
            .frame(height: 18)
        }
    }
}

/// Text and state rules shared by the menu bar views, the accessibility labels and settings previews.
enum MenuBarText {
    static var upArrow: String { "↑" }
    static var downArrow: String { "↓" }

    static func gigabytes(_ bytes: UInt64, binary: Bool = false, decimal: Bool = false) -> String {
        let divisor: Double = decimal ? 1_000_000_000 : 1_073_741_824
        let gb = Double(bytes) / divisor
        if gb >= 1000 { return String(format: "%.1fT", gb / 1000) }
        if gb >= 100 || decimal { return "\(Int(gb.rounded()))G" }
        return String(format: "%.1fG", gb)
    }

    static var readLetter: String { "R" }
    static var writeLetter: String { "W" }
    static func readShort(_ v: Double) -> String { readLetter + " " + Format.rateCompact(v) }
    static func writeShort(_ v: Double) -> String { writeLetter + " " + Format.rateCompact(v) }

    static func volume(_ d: DiskSample, _ name: String) -> Volume? {
        if !name.isEmpty, let v = d.volumes.first(where: { $0.name == name }) { return v }
        return d.root
    }

    static func sensorValue(_ s: SensorsSample, _ choice: SensorChoice) -> Double? {
        switch choice {
        case .cpuAverage: return s.cpuAverage
        case .cpuPerformance: return s.value(.cpuPerformance)
        case .cpuEfficiency: return s.value(.cpuEfficiency)
        case .gpu: return s.value(.gpu)
        case .ssd: return s.value(.ssd)
        case .battery: return s.value(.battery)
        }
    }

    /// Whether this Mac has the hardware a module reports on.
    static func available(_ m: Module, _ s: Snapshot) -> Bool {
        switch m {
        case .battery: return s.battery.hasBattery
        case .sensors: return !s.sensors.temps.isEmpty || !s.sensors.fans.isEmpty
        default: return true
        }
    }

    static func shortValue(_ m: Module, _ s: Snapshot, _ prefs: Preferences) -> String {
        switch m {
        case .cpu: return Format.percent(s.cpu.total)
        case .gpu: return Format.percent(s.gpu.utilization)
        case .memory: return Format.percent(s.memory.usedFraction)
        case .network: return Format.rateCompact(s.network.down)
        case .disk: return volume(s.disk, prefs.disk.volume).map { Format.percent($0.usedFraction) } ?? L10n.Common.dash
        case .battery: return Format.percent(s.battery.level)
        case .sensors: return sensorValue(s.sensors, prefs.sensors.sensor).map { Format.temperature($0, unit: prefs.general.temperatureUnit) } ?? L10n.Common.dash
        }
    }

    /// Warn / critical coloring when "负载过高时变色" is on, plus offline dimming.
    static func tone(_ m: Module, _ s: Snapshot, _ prefs: Preferences) -> BarTone {
        if m == .network && !s.network.connected { return .dim }
        let alerts = Alerts.shared.active
        if prefs.alerts.enabled && prefs.alerts.colorMenubar, let level = alerts[m] { return level }
        guard prefs.menubar.colorOnHighLoad else { return .normal }
        switch m {
        case .cpu: return s.cpu.total >= 0.9 ? .warn : .normal
        case .gpu: return s.gpu.utilization >= 0.95 ? .warn : .normal
        case .memory: return s.memory.pressure == .critical ? .crit : s.memory.pressure == .warning ? .warn : .normal
        case .sensors:
            guard let t = sensorValue(s.sensors, prefs.sensors.sensor) else { return .normal }
            return t >= 95 ? .crit : t >= 85 ? .warn : .normal
        case .disk:
            guard let v = volume(s.disk, prefs.disk.volume) else { return .normal }
            return v.available < 10_000_000_000 ? .warn : .normal
        default: return .normal
        }
    }

    /// Whether the item has to keep its colors (otherwise it is drawn as a template image).
    static func needsColor(_ m: Module, _ s: Snapshot, _ prefs: Preferences) -> Bool {
        let t = tone(m, s, prefs)
        if t.emphasized { return true }
        if t == .dim { return false }
        if prefs.menubar.iconColor == .color { return true }
        for kind in prefs.widgets(m) {
            let o = prefs.options(m, kind)
            switch kind {
            case .state: return true
            case .pie, .tacho: if !o.monochrome { return true }
            case .battery:
                let b = s.battery
                if o.colorWhenLow && b.level <= 0.2 && !b.isCharging && !b.onAC { return true }
            case .label, .icon, .chart, .value, .details, .fan, .stack: continue
            default: if o.color != .mono { return true }
            }
        }
        return false
    }

    static func accessibility(_ m: Module, _ s: Snapshot, _ prefs: Preferences) -> String {
        let unit = prefs.general.temperatureUnit
        switch m {
        case .cpu: return L10n.A11y.cpu(Format.percent(s.cpu.total))
        case .gpu: return L10n.A11y.gpu(Format.percent(s.gpu.utilization))
        case .memory: return L10n.A11y.memory(Format.percent(s.memory.usedFraction))
        case .network:
            return s.network.connected ? L10n.A11y.network(Format.rate(s.network.up), Format.rate(s.network.down)) : L10n.A11y.networkOffline
        case .disk:
            return L10n.A11y.disk(volume(s.disk, prefs.disk.volume).map { Format.storage($0.available) } ?? L10n.Common.dash)
        case .battery:
            let base = L10n.A11y.battery(Format.percent(s.battery.level))
            if s.battery.isCharging { return base + L10n.Battery.chargingA11y }
            if s.battery.level <= 0.2 && !s.battery.onAC { return base + L10n.Battery.lowA11y }
            return base
        case .sensors:
            return L10n.A11y.temperature(sensorValue(s.sensors, prefs.sensors.sensor).map { Format.temperatureNumber($0, unit: unit) } ?? L10n.Common.dash)
        }
    }

    static func combinedAccessibility(_ modules: [Module], _ s: Snapshot, _ prefs: Preferences) -> String {
        ([L10n.App.name] + modules.map { accessibility($0, s, prefs) }).joined(separator: L10n.A11y.separator)
    }
}
