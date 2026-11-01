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

extension ChartSeries {
    /// CPU: the system share as a grey line, the total in the accent over the neutral wash.
    static func cpuStack(total: [ChartPoint], system: [ChartPoint], lineWidth: CGFloat = 2) -> [ChartSeries] {
        [ChartSeries(id: "s", points: system, color: Theme.faint, fill: 0, lineWidth: max(1.3, lineWidth - 0.5)),
         ChartSeries(id: "t", points: total, color: Theme.accent, fill: 1, lineWidth: lineWidth)]
    }

    /// One reading as a line over the wash (`fill: false` for a bare line, the overview's sparks).
    static func line(_ points: [ChartPoint], _ color: Color = Theme.accent, width: CGFloat = 2, fill: Bool = true) -> [ChartSeries] {
        [ChartSeries(id: "l", points: points, color: color, fill: fill ? 1 : 0, lineWidth: width)]
    }

    /// A reading's two directions for `.mirroredArea`: the first up, the second down, each over the wash.
    static func mirrored(_ top: [ChartPoint], _ topColor: Color, _ bottom: [ChartPoint], _ bottomColor: Color, lineWidth: CGFloat = 2) -> [ChartSeries] {
        [ChartSeries(id: "a", points: top, color: topColor, fill: 1, lineWidth: lineWidth),
         ChartSeries(id: "b", points: bottom, color: bottomColor, fill: 1, lineWidth: lineWidth)]
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
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.glass).shadow(color: .black.opacity(0.14), radius: 8, y: 4))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}
