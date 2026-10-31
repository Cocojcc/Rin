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
