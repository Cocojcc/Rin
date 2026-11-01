import SwiftUI

/// A page's title without a spec (Processes, Sleep, Alerts, Settings), controls on the right.
struct PageTitle<Trailing: View>: View {
    var title: String
    var spec: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        PageHeader(title: title, spec: spec) { trailing }
    }
}

extension PageTitle where Trailing == EmptyView {
    init(title: String, spec: String? = nil) { self.init(title: title, spec: spec) { EmptyView() } }
}

struct RangeControl: View {
    @Binding var range: TimeRange
    var options: [TimeRange] = TimeRange.allCases

    var body: some View {
        Segmented(label: L10n.Range.label, options: options.map { ($0, $0.title) }, selection: $range, style: .range)
            .fixedSize()
    }
}

/// The busiest processes on a page: name, then one or two values, on hairline rows. Under the
/// pointer a row shows Quit beside the name; right click has the rest.
struct ProcessTable: View {
    var processes: [ProcessUsage]
    var value: (ProcessUsage) -> String
    var valueWidth: CGFloat? = nil
    var secondary: ((ProcessUsage) -> String)? = nil
    var secondaryWidth: CGFloat = 88
    var rowHeight: CGFloat = 32
    /// Pads with empty rows up to this many, so a list that comes and goes keeps its height.
    var minRows = 0
    /// Says "no processes" when the list is empty (off for a list's second column).
    var showsEmpty = true
    var quitCenter = QuitCenter.shared
    @State private var hovered: String?

    var body: some View {
        let stuck = processes.filter { quitCenter.states[$0.id] == .unresponsive }
        let rest = processes.filter { quitCenter.states[$0.id] != .unresponsive }
        VStack(spacing: 6) {
            ForEach(stuck) { ConfirmForceQuitRow(process: $0, value: value($0)) }
            if !rest.isEmpty || stuck.isEmpty {
                VStack(spacing: 0) {
                    DividedRows {
                        if processes.isEmpty && showsEmpty {
                            Text(L10n.Panel.noProcesses).ui(14).foregroundStyle(Theme.sub)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: rowHeight)
                        }
                        ForEach(rest) { row($0) }
                    }
                    ForEach(0..<max(0, minRows - max(processes.count, 1)), id: \.self) { _ in
                        Color.clear.frame(height: rowHeight).accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private func row(_ p: ProcessUsage) -> some View {
        let isHover = hovered == p.id && !p.isSystem
        return HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(p.name).lineLimit(1).truncationMode(.tail)
                if isHover {
                    Button {
                        quitCenter.quit(p)
                    } label: {
                        LineIcon(d: Icons.quitCircle, size: 15, lineWidth: 1.5)
                            .foregroundStyle(Theme.sub)
                            .opacity(quitCenter.states[p.id] == .quitting ? 0.4 : 1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.Panel.quitNamed(p.name))
                    .accessibilityLabel(L10n.Panel.quitNamed(p.name))
                }
            }
            Spacer(minLength: 0)
            Text(value(p)).ui(14, 500).lineLimit(1).fixedSize()
                .frame(width: valueWidth, alignment: .trailing)
            // The other direction of the same reading (upload, write), so it looks the same.
            if let secondary {
                Text(secondary(p)).ui(14, 500).lineLimit(1).fixedSize().frame(width: secondaryWidth, alignment: .trailing)
            }
        }
        .ui(14)
        .frame(height: rowHeight)
        .padding(.horizontal, 8)
        .background { if hovered == p.id { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.lgHover) } }
        .padding(.horizontal, -8)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = p.id } else if hovered == p.id { hovered = nil }
        }
        .contextMenu { ProcessContextMenu(process: p) }
        .accessibilityElement(children: .combine)
    }
}
