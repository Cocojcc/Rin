import AppKit
import SwiftUI

// MARK: - Typography

extension View {
    /// The UI font at a design size and weight (the type ramp: 12 / 14 / 16 / 22 / 28 / 40; nothing smaller),
    /// enlarged by the surface's `textScale`.
    func ui(_ size: CGFloat, _ weight: CGFloat = 400, proportional: Bool = false) -> some View {
        modifier(UIFont(size: size, weight: weight, proportional: proportional))
    }
}

private struct UIFont: ViewModifier {
    var size: CGFloat
    var weight: CGFloat
    var proportional: Bool
    @Environment(\.textScale) private var scale

    func body(content: Content) -> some View { content.font(Fonts.text(size, weight, scale: scale, proportional: proportional)) }
}

private struct TextScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }

extension EnvironmentValues {
    /// How much larger than the design's sizes text is drawn (the main window's `Fonts.windowTextScale`).
    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

// MARK: - Scale

/// Rin's windows and dropdowns are laid out at the design's sizes and drawn at this scale, so
/// the whole UI shrinks uniformly and keeps the design's proportions.
enum UIScale {
    static let factor: CGFloat = 0.85

    static func of(_ value: CGFloat) -> CGFloat { value * factor }
}

/// Lays its content out at 1 / scale of the space it gets, then draws it scaled down to fit.
struct UIScaled<Content: View>: View {
    var scale: CGFloat = UIScale.factor
    @ViewBuilder var content: Content
    @Environment(\.textScale) private var textScale

    var body: some View {
        ScaleLayout(scale: scale) {
            content
                // Enlarged text that no longer fits (fixed columns, narrow cards) settles back to
                // the design's size before it truncates.
                .minimumScaleFactor(1 / textScale)
                .scaleEffect(scale, anchor: .topLeading)
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

/// The grey behind a group of segments (9 pt corners).
struct GlassTrack: View {
    var cornerRadius: CGFloat? = 9

    var body: some View {
        GlassShape(cornerRadius: cornerRadius).fill(Theme.raise)
    }
}

/// The selected segment: a raised white chip with a soft shadow and a hairline ring (light), a
/// lighter step (dark); 6 pt corners.
struct GlassThumb: View {
    var cornerRadius: CGFloat? = 6

    var body: some View {
        GlassShape(cornerRadius: cornerRadius)
            .fill(Theme.raised)
            .overlay(GlassShape(cornerRadius: cornerRadius).inset(by: -0.25).stroke(Theme.raisedRing, lineWidth: 0.5))
            .shadow(color: Theme.raisedShadowNear, radius: 1, x: 0, y: 1)
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

/// Settings group: a small grey title, then rows with hairlines between them in a soft well.
struct SettingsGroup<Content: View, Trailing: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HeadRow(title: title) { trailing }
            }
            Well { DividedRows { content } }
        }
    }
}

/// A group of rows on the soft grey that sets it off from the page.
struct Well<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.well))
    }
}

extension SettingsGroup where Trailing == EmptyView {
    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, content: content) { EmptyView() }
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

/// A 1 pt rule.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 1)
    }
}

/// Label on the left, control on the right (44 pt rows in settings).
struct SettingsRow<Control: View>: View {
    var title: String
    var height: CGFloat = 45
    /// Faded and locked while another setting makes it moot (the rule above stays as it is).
    var dimmed = false
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            Text(title).ui(14).lineLimit(1)
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

/// 34 × 20 switch. On: the accent with a white knob. Off: a grey track with a white knob.
struct RinSwitch: View {
    @Binding var isOn: Bool
    var label: String

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Theme.switchOn : Theme.switchOff)
                Circle().fill(isOn ? Theme.switchOnKnob : Theme.switchKnob)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
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

/// Segments on a grey track, the selected one on a raised chip: 26 tall, 13 pt text. `.tab` is
/// the dropdowns' smaller 22 pt version, `.tabs` a page's tab bar (12 pt side padding).
struct Segmented<Value: Hashable>: View {
    /// `inline`: the range's look at 22 tall, beside a switch in a settings row.
    enum Style { case compact, range, inline, tab, tabs, sort }

    var label: String
    var options: [(Value, String)]
    @Binding var selection: Value
    var style: Style = .compact
    /// Draws a segment as an icon instead of text.
    var glyph: ((Value) -> AnyView)? = nil
    var glyphWidth: CGFloat = 18
    /// A module page's time range: the selected segment washed in the module's color.
    var tint: Color? = nil

    private var fills: Bool { false }

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
                            Text(option.1).ui(fontSize).lineLimit(1)
                        }
                    }
                    .foregroundStyle(on ? Theme.text : Theme.sub)
                    .padding(.horizontal, style == .tabs ? 12 : glyph == nil ? 10 : 8)
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
        .slidingThumb(selection) { GlassThumb() }
        .padding(style == .tab ? 2 : 3)
        .background(GlassTrack(cornerRadius: style == .tab ? 7 : 9))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private var height: CGFloat { style == .tab ? 22 : 26 }

    private var fontSize: CGFloat { style == .tab ? 12 : 13 }
}

/// "− 12 pt +": two small grey buttons around the value.
struct GlassStepper: View {
    var label: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step = 1

    var body: some View {
        HStack(spacing: 4) {
            StepButton(d: Icons.minusSmall, label: L10n.Settings.decrease(label), enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - step)
            }
            Text(L10n.Settings.points(value)).ui(13).monospacedDigit().frame(width: 44)
            StepButton(d: Icons.plusSmall, label: L10n.Settings.increase(label), enabled: value < range.upperBound) {
                value = min(range.upperBound, value + step)
            }
        }
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
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering && enabled ? Theme.chip : Theme.raise))
                .hoverAnimation(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A grey popup button that opens a menu ("5 个 ⌄").
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
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot(selection)).frame(width: 9, height: 9) }
                Text(options.first(where: { $0.0 == selection })?.1 ?? "").ui(13)
                LineIcon(d: Icons.chevronDown, size: 10, viewBox: 16, lineWidth: 2)
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.raise))
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
    var radius: CGFloat = 7
    var horizontalPadding: CGFloat = 12
    var fontSize: CGFloat = 13
    var expands = false
    var color: Color = Theme.text
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).ui(fontSize)
                .lineLimit(1)
                .foregroundStyle(color)
                .padding(.horizontal, horizontalPadding)
                .fixedSize(horizontal: !expands, vertical: false)
                .frame(maxWidth: expands ? .infinity : nil)
                .frame(height: height)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.raise))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Green button ("完成", "合并成一项").
struct PrimaryButton: View {
    var title: String
    var height: CGFloat = 38
    var radius: CGFloat = 12
    var fontSize: CGFloat = 13
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).ui(fontSize, 500)
                .lineLimit(1)
                .foregroundStyle(Theme.onGreen)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.green))
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
    var fill: Color = Theme.raise
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
