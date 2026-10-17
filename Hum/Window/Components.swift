import AppKit
import SwiftUI

// MARK: - Containers

/// White rounded group used throughout the main window (12 radius, hairline rim).
struct Card<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
    var radius: CGFloat = 12
    var fill: Color = Theme.group
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.groupRim, lineWidth: 0.5))
    }
}

/// Settings section: small grey heading above a grouped list.
struct SettingsSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.sub)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                DividedRows { content }
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.group))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.groupRim, lineWidth: 0.5))
        }
    }
}

/// Lays out children with a hairline between each.
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
                    if child.id != first { Rectangle().fill(Theme.line).frame(height: 0.5) }
                }
            }
        }
    }
}

/// A 40 pt settings row: label on the left, control on the right.
struct SettingsRow<Control: View>: View {
    var title: String
    var height: CGFloat = 40
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            Text(title).lineLimit(1)
            Spacer(minLength: 8)
            control
        }
        .frame(minHeight: height)
    }
}

// MARK: - Controls

/// Pill switch (36 × 22) in the accent color.
struct HumToggle: View {
    @Binding var isOn: Bool
    var label: String
    @Environment(\.accent) private var accent

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? accent.accent : Theme.track.opacity(2.2))
                Circle().fill(isOn ? accent.onAccent : Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    .frame(width: 18, height: 18)
                    .padding(2)
            }
            .frame(width: 36, height: 22)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? L10n.Common.on : L10n.Common.off)
        .accessibilityAddTraits(.isToggle)
    }
}

/// Grey well with a raised white segment, like the design's radio groups.
struct SegmentedPicker<Value: Hashable>: View {
    var label: String
    var options: [(Value, String)]
    @Binding var selection: Value
    var height: CGFloat = 22
    var fontSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.0 == selection
                Button {
                    selection = option.0
                } label: {
                    Text(option.1)
                        .font(.system(size: fontSize, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Theme.text : Theme.sub)
                        .padding(.horizontal, 10)
                        .frame(height: height)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(on ? Theme.segOn : Color.clear)
                                .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.well))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// Grey pill that opens a menu of choices ("5 个 ⌄").
struct MenuPill<Value: Hashable>: View {
    var label: String
    var options: [(Value, String)]
    @Binding var selection: Value

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
            HStack(spacing: 5) {
                Text(options.first(where: { $0.0 == selection })?.1 ?? "")
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.sub)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.well))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(label)
    }
}

/// Grey rounded text button ("恢复默认", "回到现在").
struct WellButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.well))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Accent-tinted button with dark accent text (white on orange fails contrast).
struct TintButton: View {
    var title: String
    var height: CGFloat = 30
    var action: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent.tintText)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(accent.tint))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Data display

struct IconChip: View {
    var d: String
    var size: CGFloat = 30
    var iconSize: CGFloat = 16
    var radius: CGFloat = 8
    var color: Color = Theme.text
    var fill: Color = Theme.chip
    var lineWidth: CGFloat = 1.5

    var body: some View {
        LineIcon(d: d, size: iconSize, lineWidth: lineWidth)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .accessibilityHidden(true)
    }
}

/// Rounded heavy number with a smaller unit, colored like its data.
struct BigValue: View {
    var number: String
    var unit: String
    var color: Color
    var size: CGFloat = 30
    var unitSize: CGFloat = 16

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: unit == "°" ? 0 : 2) {
            Text(number).font(Fonts.big(size)).monospacedDigit()
            Text(unit).font(Fonts.big(unit == "°" ? size : unitSize))
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
    }
}

/// Thin horizontal meter (4 pt) on a track.
struct MeterBar: View {
    var fraction: Double
    var color: Color
    var height: CGFloat = 4

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

struct StatBlock: View {
    var value: String
    var label: String
    var valueSize: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: valueSize, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.sub).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct LegendDot: View {
    var color: Color
    var label: String
    var value: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(Theme.sub)
            if let value { Text(value).fontWeight(.semibold).foregroundStyle(Theme.text) }
        }
        .font(.system(size: 11))
    }
}

struct StatusBadge: View {
    var text: String
    var fg: Color
    var bg: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Capsule().fill(bg))
    }
}

/// App icon for a process row, or a letter chip when it has no bundle.
struct ProcessIcon: View {
    var process: ProcessUsage
    var size: CGFloat = 22

    var body: some View {
        if let image = ProcessActions.icon(for: process) {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Text(String(process.name.prefix(1)).uppercased())
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(Theme.sub)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(Theme.chip))
                .accessibilityHidden(true)
        }
    }
}

/// Grid lines plus area + line series, the chart look used in panels (no axes).
struct MiniChart: View {
    struct Series {
        var values: [Double]      // 0...1
        var color: Color
        var fill: Double = 0.14
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
