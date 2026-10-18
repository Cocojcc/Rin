import SwiftUI

/// How loud a menu bar item should be. Color in the menu bar is reserved for warnings.
enum BarTone {
    case normal, warn, crit, dim

    var color: Color? {
        switch self {
        case .normal: return nil
        case .warn: return Color(nsColor: Theme.barWarn)
        case .crit: return Color(nsColor: Theme.barCrit)
        case .dim: return .primary.opacity(0.45)
        }
    }

    var emphasized: Bool { self == .warn || self == .crit }
}

/// Fixed-width text so the item doesn't change width as numbers change.
struct FixedText: View {
    var text: String
    var template: String
    var font: Font
    var alignment: Alignment = .trailing

    var body: some View {
        Text(template).font(font).hidden()
            .overlay(alignment: alignment) { Text(text).font(font).lineLimit(1).fixedSize() }
    }
}

private struct WidgetUIFontKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Widgets draw in the system font in the menu bar and in Space Grotesk where the settings
    /// window previews them (the design draws the widget strip in the UI font).
    var widgetUIFont: Bool {
        get { self[WidgetUIFontKey.self] }
        set { self[WidgetUIFontKey.self] = newValue }
    }
}

enum BarFont {
    static func font(_ size: CGFloat, _ weight: CGFloat = 400, ui: Bool) -> Font {
        if ui { return Fonts.ui(size, weight) }
        let w: Font.Weight = weight >= 600 ? .semibold : weight >= 500 ? .medium : weight <= 300 ? .light : .regular
        return .system(size: size, weight: w).monospacedDigit()
    }

    static func value(_ emphasized: Bool = false, ui: Bool = false) -> Font { font(13, emphasized ? 600 : 400, ui: ui) }
    static let stack = Font.system(size: 9, weight: .light).monospacedDigit()
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
            .background(boxed ? Color.primary.opacity(0.08) : .clear)
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
        .background(boxed ? Color.primary.opacity(0.08) : .clear)
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
            .strokeBorder(Color.primary.opacity(0.4), lineWidth: 1)
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

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .strokeBorder(boxed ? Color.primary.opacity(0.4) : .clear, lineWidth: 1)
            Rectangle().fill(color).frame(height: 16 * min(1, max(0, fraction)))
        }
        .frame(width: 5, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))
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
                    Rectangle().fill(boxed ? Color.primary.opacity(0.08) : .clear)
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
            Circle().stroke(Color.primary.opacity(0.4), lineWidth: 2)
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
                Text(String(c)).font(BarFont.font(6.5, 500, ui: ui)).frame(height: 5.4)
            }
        }
        .fixedSize()
    }
}

/// One small arrow per row beside each rate (9 pt light, 8 pt rows): the network speed layout.
struct ArrowRows: View {
    var top: String
    var bottom: String
    var topColor: Color = .primary
    var bottomColor: Color = .primary
    var upOnTop = true
    var template: String
    var glyph: SpeedGlyph = .arrows
    @Environment(\.widgetUIFont) private var ui

    var body: some View {
        let font = BarFont.font(9, 300, ui: ui)
        Grid(alignment: .trailing, horizontalSpacing: 3, verticalSpacing: 0) {
            GridRow {
                marker(top: true).foregroundStyle(topColor)
                FixedText(text: top, template: template, font: font).frame(height: 8)
            }
            GridRow {
                marker(top: false).foregroundStyle(bottomColor)
                FixedText(text: bottom, template: template, font: font).frame(height: 8)
            }
        }
    }

    @ViewBuilder private func marker(top: Bool) -> some View {
        switch glyph {
        case .arrows:
            LineIcon(d: (top == upOnTop) ? Icons.arrowUpSmall : Icons.arrowDownSmall, size: 6, viewBox: 6, lineWidth: 1.1)
        case .dots:
            Group {
                if top == upOnTop { Circle().strokeBorder(.foreground, lineWidth: 1) } else { Circle().fill(.foreground) }
            }
            .frame(width: 4, height: 4)
        case .none:
            EmptyView()
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
        HStack(spacing: prefs.widgetsMerged(module) ? 4 : 10) {
            ForEach(prefs.widgets(module)) { WidgetView(module: module, kind: $0, prefs: prefs) }
        }
        .padding(.horizontal, 5)
        .frame(maxHeight: .infinity)
        .foregroundStyle(tone.color ?? .primary)
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
        HStack(spacing: 3) {
            if o.showLabel && [.line, .bar, .pie, .tacho].contains(kind) { VerticalLabel(text: labelText) }
            content
        }
        .fixedSize()
    }

    private var labelText: String { o.labelText.isEmpty ? module.widgetLabel : o.labelText }
    private var valueFont: Font { BarFont.value(tone.emphasized, ui: ui) }

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
        case .mono: return .primary
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
        case .label: VerticalLabel(text: labelText)
        case .mini: mini
        case .line: line
        case .bar: bar
        case .pie: PieMeter(fraction: fraction, color: o.monochrome ? .primary : color(.byValue))
        case .tacho: TachoMeter(fraction: fraction, color: o.monochrome ? .primary : color(.byValue))
        case .icon: LineIcon(d: WidgetView.iconPath(module, o.icon), size: 16, lineWidth: 1.4).foregroundStyle(color(.mono))
        case .ring:
            HStack(spacing: 3) {
                RingMeter(fraction: fraction, color: color(o.color))
                if o.showValue { FixedText(text: valueText, template: valueTemplate, font: valueFont) }
            }
        case .memory: memoryPair
        case .speed: module == .network ? AnyView(networkSpeed) : AnyView(diskSpeed)
        case .chart: chart
        case .state: state
        case .value: diskValue
        case .battery: battery
        case .details: batteryDetails
        case .temp: temperature
        case .fan: fan
        case .stack: sensorStack
        }
    }

    private var mini: some View {
        let align: HorizontalAlignment = o.align == .leading ? .leading : o.align == .trailing ? .trailing : .center
        return VStack(alignment: align, spacing: 0) {
            if o.showLabel { Text(labelText).font(BarFont.font(7, 300, ui: ui)).kerning(0.3).frame(height: 7) }
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
            if o.showValue { FixedText(text: valueText, template: valueTemplate, font: valueFont) }
        }
    }

    @ViewBuilder private var bar: some View {
        switch module {
        case .cpu:
            let cores = s.cpu.perCore
            BarRow(values: cores, colors: cores.map { color(o.color, $0) }, boxed: o.boxed)
        case .sensors:
            let temps = [s.sensors.cpuAverage, s.sensors.value(.gpu), s.sensors.value(.ssd)].compactMap { $0 }.map { $0 / 100 }
            BarRow(values: temps, colors: temps.map { color(o.color, $0) }, boxed: o.boxed)
        case .memory:
            HStack(spacing: 4) {
                PillMeter(fraction: fraction, color: color(o.color))
                if o.showValue { FixedText(text: valueText, template: valueTemplate, font: valueFont) }
            }
        case .disk:
            HStack(spacing: 4) {
                PillMeter(fraction: fraction, color: color(o.color), width: 18, height: 9)
                if o.showValue { FixedText(text: Format.percent(fraction), template: "100%", font: valueFont) }
            }
        default:
            VerticalMeter(fraction: fraction, color: color(o.color), boxed: o.boxed)
        }
    }

    private var memoryPair: some View {
        let used = MenuBarText.gigabytes(s.memory.used, binary: true)
        let free = MenuBarText.gigabytes(s.memory.total > s.memory.used ? s.memory.total - s.memory.used : 0, binary: true)
        let strip = { (v: String) in o.showSymbol ? v : String(v.dropLast()) }
        let font = BarFont.font(8, 300, ui: ui)
        return VStack(alignment: .trailing, spacing: 0) {
            FixedText(text: strip(o.freeOnTop ? free : used), template: "99.9G", font: font).frame(height: 8)
            FixedText(text: strip(o.freeOnTop ? used : free), template: "99.9G", font: font).frame(height: 8)
        }
        .foregroundStyle(color(o.color))
    }

    private var networkSpeed: some View {
        let n = s.network
        let unit = prefs.network.speedUnit
        let offline = !n.connected
        let colored = (o.color == .colored || globallyColored) && !offline && tone.color == nil && !preview
        let upColor: Color = colored ? Theme.barUp : .primary
        let downColor: Color = colored ? Theme.barDown : .primary
        let format = { (v: Double) in offline ? L10n.Common.dash : (o.showUnit ? Format.rate(v, unit: unit) : Format.rateCompact(v, unit: unit)) }
        let up = format(n.up), down = format(n.down)
        let upTop = o.firstOnTop
        return Group {
            if o.layout == .twoLine {
                ArrowRows(top: upTop ? up : down, bottom: upTop ? down : up,
                          topColor: upTop ? upColor : downColor, bottomColor: upTop ? downColor : upColor,
                          upOnTop: upTop, template: o.showUnit ? "999 KB/s" : "999K", glyph: o.glyph)
            } else {
                HStack(spacing: 4) {
                    singleRate(MenuBarText.downArrow, down, downColor)
                    singleRate(MenuBarText.upArrow, up, upColor)
                }
            }
        }
        .opacity(offline ? 0.45 : 1)
    }

    private func singleRate(_ arrow: String, _ value: String, _ arrowColor: Color) -> some View {
        HStack(spacing: 1) {
            if o.glyph != .none { Text(arrow).font(BarFont.font(11, 400, ui: ui)).foregroundStyle(arrowColor) }
            FixedText(text: value, template: o.showUnit ? "999 KB/s" : "999K", font: BarFont.font(12, 400, ui: ui))
        }
    }

    private var diskSpeed: some View {
        let d = s.disk
        let colored = (o.color == .colored || globallyColored) && tone.color == nil && !preview
        let format = { (v: Double) in o.showUnit ? Format.rate(v) : Format.rateCompact(v) }
        let rows = [(MenuBarText.readLetter, format(d.read), colored ? Theme.palette(.blue) : Color.primary),
                    (MenuBarText.writeLetter, format(d.write), colored ? Theme.palette(.purple) : Color.primary)]
        let ordered = o.firstOnTop ? rows : rows.reversed()
        let font = BarFont.font(8, 300, ui: ui)
        return Group {
            if o.layout == .twoLine {
                Grid(alignment: .leading, horizontalSpacing: 2, verticalSpacing: 0) {
                    ForEach(ordered.indices, id: \.self) { i in
                        GridRow {
                            Text(ordered[i].0).font(font).foregroundStyle(ordered[i].2.opacity(colored ? 1 : 0.55))
                            FixedText(text: ordered[i].1, template: o.showUnit ? "999 MB/s" : "999M", font: font)
                        }
                        .frame(height: 8.5)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(ordered.indices, id: \.self) { i in
                        HStack(spacing: 2) {
                            Text(ordered[i].0).foregroundStyle(ordered[i].2.opacity(colored ? 1 : 0.55))
                            FixedText(text: ordered[i].1, template: o.showUnit ? "999 MB/s" : "999M", font: BarFont.font(11, 400, ui: ui))
                        }
                        .font(BarFont.font(11, 400, ui: ui))
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
                          firstColor: colored ? Theme.palette(o.firstColor) : (tone.color ?? .primary),
                          secondColor: colored ? Theme.palette(o.secondColor) : (tone.color ?? .primary),
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
        return HStack(spacing: 3) {
            if o.showIcon { LineIcon(d: Icons.disk, size: 14, lineWidth: 1.4).foregroundStyle(color(.mono)) }
            FixedText(text: text, template: "999G", font: valueFont)
        }
    }

    private var battery: some View {
        let b = s.battery
        let low = o.colorWhenLow && b.level <= 0.2 && !b.isCharging && !b.onAC
        let fill: Color? = low ? Color(nsColor: Theme.barCrit) : (globallyColored && !preview ? Theme.barBat : nil)
        let full = b.onAC && (b.isCharged || b.level >= 0.99)
        let showPercent = o.showPercent && !(o.hidePercentWhenFull && full)
        return HStack(spacing: 4) {
            BatteryGlyph(level: b.level, charging: o.showBolt && b.isCharging, fill: fill)
            if showPercent { FixedText(text: Format.percent(b.level), template: "100%", font: valueFont) }
            if o.showTime, let time = WidgetView.batteryTime(b, prefs) {
                Text(time).font(BarFont.font(11, 400, ui: ui)).opacity(0.7)
            }
        }
    }

    static func batteryTime(_ b: BatterySample, _ prefs: Preferences) -> String? {
        guard let minutes = b.isCharging ? b.minutesToFull : (b.onAC ? nil : b.minutesToEmpty) else { return nil }
        return prefs.battery.timeFormat == .clock ? Format.clockDuration(minutes: minutes) : L10n.Battery.minutesShort(minutes)
    }

    private var batteryDetails: some View {
        let b = s.battery
        let percent = Format.percent(b.level)
        let time = WidgetView.batteryTime(b, prefs) ?? L10n.Common.dash
        let font = BarFont.font(8, 300, ui: ui)
        return Group {
            switch o.details {
            case .percentAndTime:
                VStack(alignment: .trailing, spacing: 0) {
                    FixedText(text: percent, template: "100%", font: font).frame(height: 8)
                    FixedText(text: time, template: "10:00", font: font).frame(height: 8)
                }
            case .percent: FixedText(text: percent, template: "100%", font: valueFont)
            case .time: FixedText(text: time, template: "10:00", font: valueFont)
            }
        }
    }

    private var temperature: some View {
        let value = MenuBarText.sensorValue(s.sensors, prefs.sensors.sensor)
        let text = value.map { Format.temperature($0, unit: prefs.general.temperatureUnit) } ?? L10n.Common.dash
        let c = color(o.color == .byValue ? .byValue : .mono)
        return HStack(spacing: 2) {
            if o.showIcon { LineIcon(d: tone == .crit ? Icons.sensorsHot : Icons.sensors, size: 16, lineWidth: 1.4).foregroundStyle(c) }
            FixedText(text: text, template: "100°", font: valueFont)
                .foregroundStyle(o.showIcon ? (tone.color ?? .primary) : c)
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
            FixedText(text: text, template: o.fanValue == .rpm ? "8888" : "100%", font: valueFont)
        }
    }

    private var sensorStack: some View {
        let unit = prefs.general.temperatureUnit
        let rows: [(String, String)] = [
            (Module.cpu.widgetLabel, s.sensors.cpuAverage.map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash),
            (Module.gpu.widgetLabel, s.sensors.value(.gpu).map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash),
        ]
        let font = o.monospaced ? BarFont.font(8, 300, ui: ui) : (ui ? Fonts.ui(8, 300) : .system(size: 8, weight: .light))
        let align: Alignment = o.align == .leading ? .leading : o.align == .trailing ? .trailing : .center
        return Group {
            if o.layout == .twoLine {
                Grid(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 0) {
                    ForEach(rows.indices, id: \.self) { i in
                        GridRow {
                            Text(rows[i].0).font(font).opacity(0.55)
                            FixedText(text: rows[i].1, template: "100°", font: font, alignment: align)
                        }
                        .frame(height: 8)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(rows.indices, id: \.self) { i in
                        HStack(spacing: 2) {
                            Text(rows[i].0).opacity(0.55)
                            Text(rows[i].1)
                        }
                        .font(BarFont.font(11, 400, ui: ui))
                    }
                }
            }
        }
    }

    /// The "icon" widget's four choices: the module's own icon, a gauge, a waveform, a display.
    static func iconPath(_ m: Module, _ index: Int) -> String {
        switch index {
        case 1: return Icons.gauge
        case 2: return Icons.wave
        case 3: return Icons.monitorWindow
        default: return Icons.module(m)
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
                    .foregroundStyle(MenuBarText.tone(m, s, prefs).color ?? .primary)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxHeight: .infinity)
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
                Text(m.compactLabel).font(.system(size: 7, weight: .light)).kerning(0.3)
                FixedText(text: MenuBarText.shortValue(m, s, prefs), template: m == .sensors ? "100°" : "100%",
                          font: .system(size: 12, weight: tone.emphasized ? .semibold : .regular).monospacedDigit(), alignment: .center)
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
