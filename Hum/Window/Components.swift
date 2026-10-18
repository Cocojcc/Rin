import AppKit
import SwiftUI

// MARK: - Typography

extension View {
    /// Space Grotesk at a size and weight (the design's type ramp: 11 / 12 / 13 / 15 / 18 / 24 / 44).
    func ui(_ size: CGFloat, _ weight: CGFloat = 400) -> some View { font(Fonts.ui(size, weight)) }
}

// MARK: - Scale

/// Hum's windows and dropdowns are laid out at the design's sizes and drawn at this scale, so
/// the whole UI shrinks uniformly and keeps the design's proportions.
enum UIScale {
    static let factor: CGFloat = 0.85

    static func of(_ value: CGFloat) -> CGFloat { value * factor }
}

/// Lays its content out at 1 / scale of the space it gets, then draws it scaled down to fit.
struct UIScaled<Content: View>: View {
    var scale: CGFloat = UIScale.factor
    @ViewBuilder var content: Content

    var body: some View {
        ScaleLayout(scale: scale) {
            content.scaleEffect(scale, anchor: .topLeading)
        }
    }
}

private struct ScaleLayout: Layout {
    var scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(ProposedViewSize(width: proposal.width.map { $0 / scale },
                                                       height: proposal.height.map { $0 / scale }))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width / scale, height: bounds.height / scale))
    }
}

// MARK: - Liquid glass

/// Track behind a group of glass controls: faint fill, a 1 pt highlight along the top inside
/// edge, a hairline outline.
struct GlassTrack: View {
    var cornerRadius: CGFloat? = nil

    var body: some View {
        GlassShape(cornerRadius: cornerRadius)
            .fill(Theme.lgFill.shadow(.inner(color: Theme.lgEdgeLight, radius: 0, x: 0, y: 1)))
            .overlay(GlassShape(cornerRadius: cornerRadius).inset(by: -0.25).stroke(Theme.lgEdgeLine, lineWidth: 0.5))
    }
}

/// The raised glass piece of a selected segment, sidebar row or chip.
struct GlassThumb: View {
    var cornerRadius: CGFloat? = nil

    var body: some View {
        GlassShape(cornerRadius: cornerRadius)
            .fill(Theme.lgThumb.shadow(.inner(color: Theme.lgThumbLight, radius: 0, x: 0, y: 1)))
            .overlay(GlassShape(cornerRadius: cornerRadius).strokeBorder(Theme.lgThumbRing, lineWidth: 0.5))
            .overlay(GlassShape(cornerRadius: cornerRadius).inset(by: -0.25).stroke(Theme.lgThumbLine, lineWidth: 0.5))
            .shadow(color: Theme.lgThumbShadow, radius: 3.5, x: 0, y: 2)
    }
}

enum Motion {
    /// A selection moving to another item (glass thumbs, chips changing groups).
    static let slide = Animation.spring(response: 0.3, dampingFraction: 0.82)
    /// Hover tints, as the design's 0.12 s background transition.
    static let hover = Animation.easeOut(duration: 0.12)
    /// One page fading into the next in the main window.
    static let page = Animation.easeOut(duration: 0.16)
}

extension View {
    /// Animates hover tints within this view.
    func hoverAnimation(_ hovering: Bool) -> some View { animation(Motion.hover, value: hovering) }

    /// Marks the selected item of the enclosing `slidingThumb` group.
    func thumbAnchor(_ selected: Bool) -> some View {
        anchorPreference(key: ThumbAnchorKey.self, value: .bounds) { selected ? $0 : nil }
    }

    /// Draws one thumb behind the item marked `thumbAnchor(true)` and slides it to the next
    /// one when `value` changes. A single moving piece, rather than one per item, so nothing
    /// cross-fades on the way.
    func slidingThumb<V: Equatable, Thumb: View>(_ value: V, @ViewBuilder thumb: @escaping () -> Thumb) -> some View {
        backgroundPreferenceValue(ThumbAnchorKey.self) { anchor in
            GeometryReader { geo in
                if let anchor {
                    let r = geo[anchor]
                    thumb().frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                }
            }
            .animation(Motion.slide, value: value)
        }
        .transformAnchorPreference(key: ThumbAnchorKey.self, value: .bounds) { current, _ in current = nil }
    }
}

private struct ThumbAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

/// A capsule, or a rounded rectangle when a radius is given.
struct GlassShape: InsettableShape {
    var cornerRadius: CGFloat?
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = cornerRadius.map { max(0, $0 - insetAmount) } ?? min(r.width, r.height) / 2
        return Path(roundedRect: r, cornerRadius: radius, style: .continuous)
    }

    func inset(by amount: CGFloat) -> GlassShape {
        var s = self
        s.insetAmount += amount
        return s
    }
}

// MARK: - Containers

/// Subtle filled area that groups content on glass (no border).
struct Panel<Content: View>: View {
    var radius: CGFloat = 16
    var padding: EdgeInsets = EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
    var fill: Color = Theme.panel
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
    }
}

/// Section title above a panel: 13 / 500 grey, optional note on the right.
struct SectionHeader: View {
    var title: String
    var right: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).ui(13, 500).foregroundStyle(Theme.sub).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let right { Text(right).ui(12).foregroundStyle(Theme.sub) }
        }
        .frame(minHeight: 18)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}

/// A titled block: header, then content.
struct TitledSection<Content: View>: View {
    var title: String
    var right: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: title, right: right)
            content
        }
    }
}

/// Settings group: rows on a panel, separated by hairlines.
struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title).ui(13, 500).foregroundStyle(Theme.sub)
                    .padding(.horizontal, 14).padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { DividedRows { content } }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        }
    }
}

/// Lays out children with a hairline above every row but the first.
struct DividedRows<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        _VariadicView.Tree(DividedLayout()) { content }
    }

    private struct DividedLayout: _VariadicView_MultiViewRoot {
        func body(children: _VariadicView.Children) -> some View {
            let first = children.first?.id
            ForEach(children) { child in
                child.overlay(alignment: .top) {
                    if child.id != first { Hairline() }
                }
            }
        }
    }
}

/// 0.5 pt rule in a 1 pt box so rows below stay on whole points.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 0.5).frame(height: 1, alignment: .top)
    }
}

/// Label on the left, control on the right (42 pt rows in settings).
struct SettingsRow<Control: View>: View {
    var title: String
    var height: CGFloat = 42
    /// Faded and locked while another setting makes it moot (the rule above stays as it is).
    var dimmed = false
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            Text(title).ui(13).lineLimit(1)
            Spacer(minLength: 8)
            control
        }
        .opacity(dimmed ? 0.4 : 1)
        .allowsHitTesting(!dimmed)
        .animation(.easeOut(duration: 0.15), value: dimmed)
        .frame(minHeight: height)
    }
}

// MARK: - Controls

/// 34 × 20 switch. On: accent track. Off: grey track with a raised white knob.
struct HumSwitch: View {
    @Binding var isOn: Bool
    var label: String
    @Environment(\.accent) private var accent

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? accent.accent : Theme.track)
                Circle().fill(isOn ? accent.onAccent : Theme.raised)
                    .raisedShadow(!isOn)
                    .frame(width: 16, height: 16)
                    .padding(2)
            }
            .frame(width: 34, height: 20)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? L10n.Common.on : L10n.Common.off)
        .accessibilityAddTraits(.isToggle)
    }
}

/// Glass track with a glass thumb on the selected segment (`.tab`, used in dropdowns, keeps
/// the grey well and white thumb). `.compact` for settings rows (24 pt),
/// `.range` for the time ranges on monitor pages (26 pt, 12 pt side padding),
/// `.tab` for small inline switches (22 pt, 11 pt text), `.tabs` for a page's tab bar
/// (26 pt, full width), `.sort` for the overview's sort switch (26 pt).
struct Segmented<Value: Hashable>: View {
    enum Style { case compact, range, tab, tabs, sort }

    var label: String
    var options: [(Value, String)]
    @Binding var selection: Value
    var style: Style = .compact
    /// Draws a segment as an icon instead of text.
    var glyph: ((Value) -> AnyView)? = nil
    var glyphWidth: CGFloat = 18

    private var fills: Bool { style == .tabs }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.0 == selection
                Button {
                    selection = option.0
                } label: {
                    Group {
                        if let glyph {
                            glyph(option.0).frame(width: glyphWidth)
                        } else {
                            Text(option.1).ui(fontSize, on ? 500 : 400).lineLimit(1)
                        }
                    }
                    .foregroundStyle(on ? Theme.text : Theme.sub)
                    .padding(.horizontal, style == .range ? 12 : 7)
                    .frame(maxWidth: fills ? .infinity : nil)
                    .frame(height: height)
                    .thumbAnchor(on)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(glyph == nil ? "" : option.1)
                .accessibilityLabel(option.1.isEmpty ? label : option.1)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .slidingThumb(selection) {
            if glass {
                GlassThumb()
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.raised).raisedShadow()
            }
        }
        .padding(fills ? 3 : 2)
        .background {
            if glass {
                GlassTrack()
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.well)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private var height: CGFloat {
        switch style {
        case .range: return 26
        case .tab: return 22
        case .tabs, .sort: return 26
        case .compact: return 24
        }
    }

    private var glass: Bool { style != .tab }
    private var fontSize: CGFloat { style == .tab ? 11 : 12 }
}

/// "− 12 pt +" on a glass track.
struct GlassStepper: View {
    var label: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step = 1

    var body: some View {
        HStack(spacing: 2) {
            StepButton(d: Icons.minusSmall, label: L10n.Settings.decrease(label), enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - step)
            }
            Text(L10n.Settings.points(value)).ui(12, 500).monospacedDigit().frame(minWidth: 40)
            StepButton(d: Icons.plusSmall, label: L10n.Settings.increase(label), enabled: value < range.upperBound) {
                value = min(range.upperBound, value + step)
            }
        }
        .padding(2)
        .background(GlassTrack())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityValue(L10n.Settings.points(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }
}

private struct StepButton: View {
    var d: String
    var label: String
    var enabled: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            LineIcon(d: d, size: 10, viewBox: 10, lineWidth: 1.4)
                .foregroundStyle(Theme.text)
                .frame(width: 28, height: 24)
                .background { if hovering && enabled { Capsule().fill(Theme.lgHover) } }
                .hoverAnimation(hovering)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Well-coloured pill that opens a menu ("5 个 ⌃⌄").
struct MenuPill<Value: Hashable>: View {
    var label: String
    var options: [(Value, String)]
    @Binding var selection: Value
    /// Optional color dot in front of the current choice (color menus).
    var dot: ((Value) -> Color)? = nil

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    selection = option.0
                } label: {
                    if option.0 == selection { Label(option.1, systemImage: "checkmark") } else { Text(option.1) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let dot { Circle().fill(dot(selection)).frame(width: 9, height: 9) }
                Text(options.first(where: { $0.0 == selection })?.1 ?? "").ui(13)
                LineIcon(d: Icons.upDown, width: 8, height: 12, viewBox: CGSize(width: 8, height: 12), lineWidth: 1.4)
            }
            .foregroundStyle(Theme.text)
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.well))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(label)
    }
}

/// Grey text button ("恢复默认", "检查更新", "回到现在").
struct WellButton: View {
    var title: String
    var height: CGFloat = 28
    var radius: CGFloat = 8
    var horizontalPadding: CGFloat = 12
    var fontSize: CGFloat = 13
    var expands = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).ui(fontSize)
                .lineLimit(1)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, horizontalPadding)
                .fixedSize(horizontal: !expands, vertical: false)
                .frame(maxWidth: expands ? .infinity : nil)
                .frame(height: height)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.well))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Accent-filled button ("完成", "合并成一项").
struct PrimaryButton: View {
    var title: String
    var height: CGFloat = 38
    var radius: CGFloat = 12
    var fontSize: CGFloat = 13
    var action: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: action) {
            Text(title).ui(fontSize, 500)
                .lineLimit(1)
                .foregroundStyle(accent.onAccent)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(accent.accent))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Square well button with a line icon.
struct IconButton: View {
    var d: String
    var size: CGFloat = 28
    var radius: CGFloat = 8
    var iconSize: CGFloat = 12
    var viewBox: CGFloat = 12
    var lineWidth: CGFloat = 1.7
    var fill: Color = Theme.well
    var tint: Color = Theme.sub
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            LineIcon(d: d, size: iconSize, viewBox: viewBox, lineWidth: lineWidth)
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Data display

/// Value over label (monitor-page stat row: 18 / 500 over 12 grey).
struct StatBlock: View {
    var value: String
    var label: String
    var valueSize: CGFloat = 18
    var valueColor: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).ui(valueSize, 500).kerning(valueSize >= 18 ? -0.18 : 0).foregroundStyle(valueColor).lineLimit(1)
            Text(label).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A rounded strip of equal cells separated by hairlines (load average, frequencies, power).
/// Anything after `Format.marker` in a value is set small and grey ("214 / 1000").
struct CellStrip: View {
    var cells: [(String, String)]
    var fill: Color = Theme.panel
    var radius: CGFloat = 16
    var compact = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, cell in
                VStack(alignment: .leading, spacing: 2) {
                    value(cell.0).ui(15, 500).lineLimit(1).minimumScaleFactor(0.8)
                    Text(cell.1).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
                }
                .padding(.horizontal, compact ? 12 : 14)
                .padding(.vertical, compact ? 10 : 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    if i > 0 { Rectangle().fill(Theme.line).frame(width: 0.5) }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
    }

    private func value(_ s: String) -> Text {
        let parts = s.components(separatedBy: Format.marker)
        guard parts.count > 1 else { return Text(s) }
        return Text(parts[0]) + Text(parts[1...].joined()).font(Fonts.ui(12)).foregroundColor(Theme.sub)
    }
}

/// Thin horizontal meter on a track (3 pt by default).
struct MeterBar: View {
    var fraction: Double
    var color: Color
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color).frame(width: max(0, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Circular gauge; `segments` stack around the ring (butt ends when there are several).
struct Ring: View {
    struct Segment {
        var fraction: Double
        var color: Color
        var opacity: Double = 1
    }

    var segments: [Segment]
    var size: CGFloat
    var lineWidth: CGFloat
    var butt: Bool

    init(fraction: Double, color: Color, size: CGFloat, lineWidth: CGFloat, forceButt: Bool = false) {
        segments = [Segment(fraction: fraction, color: color)]
        self.size = size
        self.lineWidth = lineWidth
        butt = forceButt
    }

    init(segments: [Segment], size: CGFloat, lineWidth: CGFloat, forceButt: Bool = false) {
        self.segments = segments
        self.size = size
        self.lineWidth = lineWidth
        butt = forceButt || segments.count > 1
    }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            ForEach(Array(starts.enumerated()), id: \.offset) { i, start in
                let seg = segments[i]
                Circle()
                    .trim(from: start, to: min(1, start + max(0, seg.fraction)))
                    .stroke(seg.color.opacity(seg.opacity), style: StrokeStyle(lineWidth: lineWidth, lineCap: butt ? .butt : .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var starts: [Double] {
        var acc = 0.0
        return segments.map { s in defer { acc += max(0, s.fraction) }; return acc }
    }
}

struct LegendDot: View {
    var color: Color
    var label: String
    var size: CGFloat = 8
    var value: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: size, height: size)
            Text(label).foregroundStyle(Theme.sub)
            if let value { Text(value).fontWeight(.medium).foregroundStyle(Theme.text) }
        }
        .ui(12)
    }
}

/// Rounded pill with tinted background ("一切正常", "被挡住", "电量低").
struct StatusPill: View {
    var text: String
    var fg: Color
    var bg: Color
    var dot = false
    var fontSize: CGFloat = 11
    var height: CGFloat = 18
    var radius: CGFloat = 6

    var body: some View {
        HStack(spacing: 6) {
            if dot { Circle().fill(fg).frame(width: 6, height: 6) }
            Text(text).ui(fontSize, 500).lineLimit(1)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, dot ? 10 : 7)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(bg))
    }
}

/// App icon for a process row, or a letter tile when it has no bundle (18 pt, 5 radius).
struct ProcessIcon: View {
    var process: ProcessUsage
    var size: CGFloat = 18

    var body: some View {
        if let image = ProcessActions.icon(for: process) {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            LetterTile(name: process.name, size: size)
        }
    }
}

struct LetterTile: View {
    var name: String
    var size: CGFloat = 18

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .ui(12, 600)
            .foregroundStyle(Theme.sub)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.well))
            .accessibilityHidden(true)
    }
}

/// Grid lines plus area + line series, the chart look used in panels (no axes).
struct MiniChart: View {
    struct Series {
        var values: [Double]      // 0...1
        var color: Color
        var fill: Double = 0.13
        var lineWidth: CGFloat = 1.5
    }

    var series: [Series]
    var gridLines = 3
    var minCount = 30

    var body: some View {
        Canvas { ctx, size in
            for i in stride(from: 1, through: gridLines, by: 1) {
                let y = size.height * CGFloat(i) / CGFloat(gridLines + 1)
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: .color(Theme.grid), lineWidth: 1)
            }
            for s in series where !s.values.isEmpty {
                let count = max(s.values.count, minCount)
                let step = size.width / CGFloat(max(count - 1, 1))
                let offset = CGFloat(count - s.values.count) * step
                var line = Path()
                for (i, v) in s.values.enumerated() {
                    let pt = CGPoint(x: offset + CGFloat(i) * step, y: size.height - CGFloat(min(1, max(0, v))) * (size.height - 2) - 1)
                    if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
                }
                if s.fill > 0 {
                    var area = line
                    area.addLine(to: CGPoint(x: offset + CGFloat(s.values.count - 1) * step, y: size.height))
                    area.addLine(to: CGPoint(x: offset, y: size.height))
                    area.closeSubpath()
                    ctx.fill(area, with: .color(s.color.opacity(s.fill)))
                }
                ctx.stroke(line, with: .color(s.color), style: StrokeStyle(lineWidth: s.lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// Frosted glass for windows and panels: system blur behind, design tint on top.
struct GlassBackground: View {
    var radius: CGFloat
    var tint: Color = Theme.glass
    var material: NSVisualEffectView.Material = .popover

    var body: some View {
        ZStack {
            if !RenderContext.offscreen { VisualEffectBlur(material: material) }
            tint
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.glassRim, lineWidth: 0.5))
    }
}
