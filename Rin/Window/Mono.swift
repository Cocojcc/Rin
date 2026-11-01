import SwiftUI

// The pages' vocabulary: a native-style title, small grey labels over large figures, values on
// hairline rows, and section heads with a note or link on the right. No cards: space and rules
// do the grouping.

/// A page's title: its name (28 / 600) and what it is (13, grey); readings or controls on the right.
struct PageHeader<Trailing: View>: View {
    var title: String
    var spec: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).ui(28, 600).kerning(-0.56).lineLimit(1).fixedSize().accessibilityAddTraits(.isHeader)
                if let spec, !spec.isEmpty { Text(spec).ui(13).foregroundStyle(Theme.sub).lineLimit(1) }
            }
            Spacer(minLength: 0)
            HStack(spacing: 16) { trailing }.ui(13).lineLimit(1).fixedSize()
        }
        .frame(height: 34)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, spec: String? = nil) { self.init(title: title, spec: spec) { EmptyView() } }
}

/// The small grey label over a figure ("使用率", "CPU").
struct SmallLabel: View {
    var text: String
    var color: Color = Theme.sub

    var body: some View {
        Text(text).ui(12).kerning(0.48).foregroundStyle(color).lineLimit(1)
    }
}

/// A list's head: its label on the left, a note or "全部 ›" on the right.
struct HeadRow<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SmallLabel(text: title).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            HStack(spacing: 8) { trailing }.ui(12).foregroundStyle(Theme.sub).lineLimit(1).fixedSize()
        }
        .padding(.bottom, 4)
    }
}

extension HeadRow where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

/// A chart's head: "最近 5 分钟" in 13 / 500, its keys or a link on the right.
struct ChartHead<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).ui(13, 500).lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 14) { trailing }.ui(12).foregroundStyle(Theme.sub).lineLimit(1).fixedSize()
        }
    }
}

extension ChartHead where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

/// An icon-only control named by its tooltip: grey, a grey square under the pointer, or raised
/// (grey behind it, text-colored). `inline` ones sit in a 12 pt head row without making it taller.
struct IconAction: View {
    var d: String
    var label: String
    var size: CGFloat = 24
    var raised = false
    var inline = false
    var viewBox: CGFloat = 16
    var lineWidth: CGFloat = 1.5
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            LineIcon(d: d, size: 14, viewBox: viewBox, lineWidth: lineWidth)
                .foregroundStyle(raised || hovering ? Theme.text : Theme.sub)
                .frame(width: size, height: size)
                .background {
                    if raised || hovering { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(raised ? Theme.raise : Theme.lgHover) }
                }
                .hoverAnimation(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .padding(inline ? EdgeInsets(top: -5, leading: 0, bottom: -5, trailing: -6) : EdgeInsets())
    }
}

/// A threshold drawn on a chart or bar: the bell stands in for the word 提醒.
struct BellLabel: View {
    var text: String

    var body: some View {
        HStack(spacing: 3) {
            LineIcon(d: Icons.bell, size: 11, lineWidth: 1.6)
            Text(text)
        }
        .help(L10n.Alerts.markHelp)
    }
}

/// A color key: an 8 pt dot and its words (a ring for the empty track's color, too faint for a dot).
struct KeyDot: View {
    var text: String
    var color: Color
    var ring = false
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 6) {
            if ring {
                Circle().strokeBorder(Theme.faint, lineWidth: 1).frame(width: 8, height: 8)
            } else {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(text).ui(size).lineLimit(1)
        }
        .foregroundStyle(Theme.sub)
        .fixedSize()
    }
}

/// A label and its value on one hairline row: the label 14 (grey or text), the value 14 / 500.
struct ValueRow<Value: View>: View {
    var label: String
    var height: CGFloat = 34
    var labelColor: Color = Theme.text
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 12) {
            Text(label).ui(14).foregroundStyle(labelColor).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            value.ui(14, 500).lineLimit(1).fixedSize()
        }
        .frame(height: height)
        .accessibilityElement(children: .combine)
    }
}

extension ValueRow where Value == Text {
    init(label: String, value: String, height: CGFloat = 34, labelColor: Color = Theme.text) {
        self.init(label: label, height: height, labelColor: labelColor) { Text(value) }
    }
}

/// A reading on a hairline row: its name grey on the left; at the end the value, its breakdown
/// just before it ("平均负载 … 5 分钟 1.87  15 分钟 1.62   2.14").
struct FactRow<Detail: View>: View {
    var label: String
    var value: String
    var valueColor: Color = Theme.text
    var height: CGFloat = 30
    @ViewBuilder var detail: Detail

    var body: some View {
        ValueRow(label: label, height: height, labelColor: Theme.sub) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                detail
                Text(value).foregroundStyle(valueColor)
            }
        }
    }
}

extension FactRow where Detail == EmptyView {
    init(label: String, value: String, valueColor: Color = Theme.text, height: CGFloat = 30) {
        self.init(label: label, value: value, valueColor: valueColor, height: height) { EmptyView() }
    }
}

/// A small figure: its name in 12 grey (and a note on the right), the reading under it.
struct Figure<Right: View>: View {
    var name: String
    var value: String
    var unit: String? = nil
    var color: Color = Theme.text
    var size: CGFloat = 24
    @ViewBuilder var right: Right

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
                Spacer(minLength: 0)
                right.ui(12).foregroundStyle(Theme.sub).lineLimit(1).fixedSize()
            }
            BigValue(value: value, unit: unit, size: size, color: color)
        }
        .accessibilityElement(children: .combine)
    }
}

extension Figure where Right == EmptyView {
    init(name: String, value: String, unit: String? = nil, color: Color = Theme.text, size: CGFloat = 24) {
        self.init(name: name, value: value, unit: unit, color: color, size: size) { EmptyView() }
    }
}

/// A labelled reading with a line of detail under it (the right-hand columns' figures).
struct Stat<Value: View, Foot: View>: View {
    var name: String
    var tight = false
    @ViewBuilder var value: Value
    @ViewBuilder var foot: Foot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SmallLabel(text: name)
            value.padding(.top, tight ? 6 : 8)
            foot.padding(.top, tight ? 6 : 10)
        }
        .accessibilityElement(children: .combine)
    }
}

extension Stat where Foot == EmptyView {
    init(name: String, tight: Bool = false, @ViewBuilder value: () -> Value) {
        self.init(name: name, tight: tight, value: value) { EmptyView() }
    }
}

/// Label / value pairs 14 apart ("用户 15%   系统 8%").
struct KeyValues: View {
    var pairs: [(String, String)]
    var size: CGFloat = 12
    var spacing: CGFloat = 14

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, p in KeyValue(label: p.0, value: p.1, size: size) }
        }
        .fixedSize()
    }
}

/// A red dot and words that need attention ("妙控板电量 12%").
struct Attention: View {
    var text: String
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.danger).frame(width: 6, height: 6)
            Text(text).ui(size).lineLimit(1)
        }
        .fixedSize()
    }
}

/// Parts on one thin bar with their keys under it.
struct StackedBar: View {
    struct Part {
        var label: String
        var value: Double
        var color: Color
        var ring = false
    }

    var parts: [Part]
    var height: CGFloat = 6
    var keySize: CGFloat = 13

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SegmentBar(parts: parts.map { ($0.value, $0.color) }, height: height)
            FlowLayout(spacing: 18, lineSpacing: 6) {
                ForEach(Array(parts.filter { !$0.label.isEmpty }.enumerated()), id: \.offset) { _, p in KeyDot(text: p.label, color: p.color, ring: p.ring, size: keySize) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
