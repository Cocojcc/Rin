import SwiftUI

/// Plain page title (20 / 600) for pages without a module header, controls on the right.
struct PageTitle<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(title).ui(22, 600).kerning(-0.2).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing
        }
        .frame(height: Sidebar.titleBand)
    }
}

extension PageTitle where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

struct RangeControl: View {
    @Binding var range: TimeRange
    var options: [TimeRange] = TimeRange.allCases
    var tint: Color? = nil

    var body: some View {
        Segmented(label: L10n.Range.label, options: options.map { ($0, $0.title) }, selection: $range, style: .range, tint: tint)
            .fixedSize()
    }
}

/// Top processes on a monitor page, inside its panel: icon, name, a cell meter, one or two values.
/// Hovering a row tints it and swaps the meter for Quit; right click has the rest.
struct ProcessTable: View {
    var processes: [ProcessUsage]
    var fraction: (ProcessUsage) -> Double
    var color: Color
    var value: (ProcessUsage) -> String
    var valueWidth: CGFloat = 72
    var secondary: ((ProcessUsage) -> String)? = nil
    var secondaryWidth: CGFloat = 72
    var rowHeight: CGFloat = 28
    var nameWidth: CGFloat = 120
    /// Pads with empty rows up to this many, so a list that comes and goes keeps its height.
    var minRows = 0
    var quitCenter = QuitCenter.shared
    @State private var hovered: String?

    var body: some View {
        let stuck = processes.filter { quitCenter.states[$0.id] == .unresponsive }
        let rest = processes.filter { quitCenter.states[$0.id] != .unresponsive }
        VStack(spacing: 6) {
            ForEach(stuck) { ConfirmForceQuitRow(process: $0, value: value($0)) }
            if !rest.isEmpty || stuck.isEmpty {
                VStack(spacing: 0) {
                    if processes.isEmpty {
                        Text(L10n.Panel.noProcesses).ui(14).foregroundStyle(Theme.faint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: rowHeight)
                    }
                    ForEach(rest) { row($0) }
                    ForEach(0..<max(0, minRows - max(processes.count, 1)), id: \.self) { _ in
                        Color.clear.frame(height: rowHeight).accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private func row(_ p: ProcessUsage) -> some View {
        let isHover = hovered == p.id && !p.isSystem
        return HStack(spacing: 10) {
            HStack(spacing: 10) {
                ProcessIcon(process: p, size: 14)
                Text(p.name).lineLimit(1).truncationMode(.tail)
            }
            .frame(width: nameWidth, alignment: .leading)
            if isHover {
                Spacer(minLength: 0)
                Button {
                    quitCenter.quit(p)
                } label: {
                    Text(quitCenter.states[p.id] == .quitting ? L10n.Panel.quitting : L10n.Panel.quit)
                        .ui(12)
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.well))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Panel.quitNamed(p.name))
            } else {
                MeterBar(fraction: fraction(p), color: color)
            }
            Text(value(p)).ui(14, 500).lineLimit(1).frame(width: valueWidth, alignment: .trailing)
            // The other direction of the same reading (upload, write), so it looks the same.
            if let secondary {
                Text(secondary(p)).ui(14, 500).lineLimit(1).frame(width: secondaryWidth, alignment: .trailing)
            }
        }
        .ui(14)
        .frame(height: rowHeight)
        .padding(.horizontal, 6)
        .background { if hovered == p.id { RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.lgHover) } }
        .padding(.horizontal, -6)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = p.id } else if hovered == p.id { hovered = nil }
        }
        .contextMenu { ProcessContextMenu(process: p) }
        .accessibilityElement(children: .combine)
    }
}
