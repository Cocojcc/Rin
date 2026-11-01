import SwiftUI

/// A column of the Processes page, also what a "全部" link sorts by on the way in.
enum ProcessSort: CaseIterable {
    case cpu, gpu, memory, energy, disk, network

    var title: String {
        switch self {
        case .cpu: return L10n.Module.cpu
        case .gpu: return L10n.Module.gpu
        case .memory: return L10n.Module.memory
        case .energy: return L10n.Processes.energy
        case .disk: return L10n.Module.disk
        case .network: return L10n.Module.network
        }
    }

    var width: CGFloat {
        switch self {
        case .cpu: return 64
        case .gpu: return 52
        case .memory: return 76
        case .energy: return 60
        case .disk, .network: return 72
        }
    }

    func value(_ p: ProcessUsage) -> Double {
        switch self {
        case .cpu: return p.cpu
        case .gpu: return p.gpu
        case .memory: return Double(p.memory)
        case .energy: return p.energy
        case .disk: return p.diskTotal
        case .network: return p.netTotal
        }
    }

    /// The cell text, or nil for nothing (drawn as a grey dash).
    func text(_ p: ProcessUsage) -> String? {
        switch self {
        case .cpu: return Format.percentValue(p.cpu)
        case .gpu: return p.gpu >= 0.05 ? Format.percentValue(p.gpu) : nil
        case .memory: return p.memory > 0 ? Format.memory(p.memory) : nil
        case .energy: return p.energy >= 0.005 ? Format.appWatts(p.energy) : nil
        case .disk: return p.diskTotal >= 1 ? Format.rate(p.diskTotal) : nil
        case .network: return p.netTotal >= 1 ? Format.rate(p.netTotal) : nil
        }
    }
}

enum ProcessFilter: CaseIterable {
    case all, apps, mine, system

    var title: String {
        switch self {
        case .all: return L10n.Processes.filterAll
        case .apps: return L10n.Processes.filterApps
        case .mine: return L10n.Processes.filterMine
        case .system: return L10n.Processes.filterSystem
        }
    }

    func includes(_ p: ProcessUsage) -> Bool {
        switch self {
        case .all: return true
        case .apps: return p.bundlePath != nil && !p.isSystem
        case .mine: return p.uid == getuid()
        case .system: return p.isSystem
        }
    }
}

/// "›" after a process list's head: opens the Processes page sorted by that list.
struct AllProcessesLink: View {
    var sort: ProcessSort

    var body: some View {
        IconAction(d: Icons.chevronRight, label: L10n.Processes.viewAllA11y, inline: true) {
            MainWindowController.shared.showProcesses(sortedBy: sort)
        }
    }
}

// MARK: - Page

struct ProcessesPage: View {
    /// The row selected when the page opens (debug snapshots render the inspector this way).
    static var initialSelection: String?

    var monitor = Monitor.shared
    var navigator = Navigator.shared
    @State private var filter: ProcessFilter = .all
    @State private var selected: String? = ProcessesPage.initialSelection

    var body: some View {
        let s = monitor.snapshot.processes
        let rows = sorted(s.all)
        let selection = selected.flatMap { id in s.all.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: L10n.Sidebar.processes) {
                KeyValue(label: L10n.Monitor.processesLabel, value: grouped(s.processCount), size: 13)
                KeyValue(label: L10n.Monitor.threadsLabel, value: grouped(s.threadCount), size: 13)
            }
            Segmented(label: L10n.Processes.filterLabel, options: ProcessFilter.allCases.map { ($0, $0.title) },
                      selection: $filter, style: .range)
                .fixedSize()
                .padding(.top, 22)
            HStack(alignment: .top, spacing: 24) {
                ProcessGrid(rows: rows, allColumns: columns(inspecting: selection != nil),
                            sort: navigator.processSort, selected: $selected) { navigator.processSort = $0 }
                if let selection {
                    ProcessInspector(process: selection) { selected = nil }
                        .frame(width: 212)
                        .padding(.leading, 24)
                        .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 16)
            .animation(Motion.slide, value: selection?.id)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// With the inspector open only the sorted column and memory stay (CPU when sorting by memory).
    private func columns(inspecting: Bool) -> [ProcessSort] {
        guard inspecting else { return ProcessSort.allCases }
        let sort = navigator.processSort
        let keep: Set<ProcessSort> = [sort, sort == .memory ? .cpu : .memory]
        return ProcessSort.allCases.filter(keep.contains)
    }

    private func sorted(_ all: [ProcessUsage]) -> [ProcessUsage] {
        let query = navigator.processQuery.trimmingCharacters(in: .whitespaces)
        let sort = navigator.processSort
        return all
            .filter { filter.includes($0) }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || "\($0.pid)" == query }
            .sorted {
                let a = sort.value($0), b = sort.value($1)
                return a != b ? a > b : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }
}

// MARK: - Table

private struct ProcessGrid: View {
    var rows: [ProcessUsage]
    var allColumns: [ProcessSort]
    var sort: ProcessSort
    @Binding var selected: String?
    var onSort: (ProcessSort) -> Void
    @State private var width: CGFloat = 0

    /// Narrow tables drop the less telling columns first, so names stay readable; the sorted
    /// column always stays.
    private var columns: [ProcessSort] {
        guard width > 0 else { return allColumns }
        var cols = allColumns
        func needed() -> CGFloat {
            // Header padding, row inset and padding, icon and gap, the name, then each column.
            Self.minNameWidth + cols.reduce(0) { $0 + $1.width + 12 }
        }
        for drop in [ProcessSort.network, .disk, .energy, .gpu] where needed() > width && drop != sort {
            cols.removeAll { $0 == drop }
        }
        return cols
    }

    private static let minNameWidth: CGFloat = 150

    var body: some View {
        VStack(spacing: 0) {
            header
            if RenderContext.offscreen {
                // Snapshots can't scroll; the first screenful stands in for the list.
                list(Array(rows.prefix(19))).frame(maxHeight: .infinity, alignment: .top).clipped()
            } else {
                ScrollView { list(rows) }.scrollIndicators(.automatic)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { width = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in width = w }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(L10n.Processes.name).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(columns, id: \.self) { column in
                let on = column == sort
                Button {
                    onSort(column)
                } label: {
                    HStack(spacing: 3) {
                        if on { LineIcon(d: Icons.sortChevron, size: 8, viewBox: 8, lineWidth: 1.4) }
                        Text(column.title).ui(12, on ? 500 : 400).lineLimit(1)
                    }
                    .foregroundStyle(on ? Theme.text : Theme.sub)
                    .frame(width: column.width, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(column.title)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .ui(12)
        .foregroundStyle(Theme.sub)
        .frame(height: 28)
        .overlay(alignment: .bottom) { Hairline() }
        .padding(.bottom, 4)
    }

    private func list(_ rows: [ProcessUsage]) -> some View {
        LazyVStack(spacing: 0) {
            if rows.isEmpty {
                Text(L10n.Panel.noProcesses).ui(14).foregroundStyle(Theme.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 30)
            }
            ForEach(rows) { p in
                ProcessGridRow(process: p, columns: columns, selected: selected == p.id) {
                    selected = selected == p.id ? nil : p.id
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Processes.listLabel)
    }
}

private struct ProcessGridRow: View {
    var process: ProcessUsage
    var columns: [ProcessSort]
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(process.name).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(columns.enumerated()), id: \.element) { i, column in
                    Group {
                        if let text = column.text(process) {
                            Text(text).fontWeight(i == 0 ? .medium : .regular)
                        } else {
                            Text(L10n.Common.dash).foregroundStyle(Theme.sub)
                        }
                    }
                    .lineLimit(1)
                    .frame(width: column.width, alignment: .trailing)
                }
            }
            .ui(14)
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background {
                if selected || hovering {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? Theme.raise : Theme.lgHover)
                }
            }
            .padding(.horizontal, -8)
            .hoverAnimation(hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu { ProcessContextMenu(process: process) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - Inspector

private struct ProcessInspector: View {
    var process: ProcessUsage
    var close: () -> Void
    var monitor = Monitor.shared
    var quitCenter = QuitCenter.shared

    var body: some View {
        let p = process
        let d = ProcessDetails.read(p)
        let history = monitor.processHistory[p.id] ?? []
        Group {
            if RenderContext.offscreen {
                content(p, d, history)
            } else {
                ScrollView { content(p, d, history) }.scrollIndicators(.never)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Processes.inspector)
    }

    private func content(_ p: ProcessUsage, _ d: ProcessDetails, _ history: [ProcessPoint]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(p, d)
            if !p.isSystem {
                if quitCenter.states[p.id] == .unresponsive {
                    ConfirmForceQuitRow(process: p, value: Format.memory(p.memory)).padding(.top, 12)
                } else {
                    HStack(spacing: 8) {
                        actionButton(quitCenter.states[p.id] == .quitting ? L10n.Panel.quitting : L10n.Panel.quit, color: Theme.text) {
                            quitCenter.quit(p)
                        }
                        actionButton(L10n.Panel.forceQuit, color: Theme.danger) { quitCenter.askForceQuit(p) }
                    }
                    .padding(.top, 12)
                }
            }
            sparkCard(L10n.Module.cpu, value: Format.percentValue(p.cpu), values: history.map(\.cpu), color: Theme.color(for: .cpu)).padding(.top, 16)
            sparkCard(L10n.Module.memory, value: Format.memory(p.memory), values: history.map(\.memory), color: Theme.color(for: .memory), fill: false).padding(.top, 12)
            group(L10n.Processes.details, [
                (L10n.Processes.cpuTime, p.cpuTime > 0 ? Format.hms(p.cpuTime) : nil),
                (L10n.Processes.threads, d.threads.map { "\($0)" }),
                (L10n.Processes.energy, p.energy >= 0.005 ? Format.appWatts(p.energy) : nil),
                (L10n.Processes.diskReadWrite, pair(p.diskRead, p.diskWrite)),
                (L10n.Processes.networkInOut, pair(p.netDown, p.netUp)),
                (L10n.Processes.started, d.started.map(Format.dayAndTime)),
            ])
            .padding(.top, 16)
            group(L10n.Processes.relations, [
                (L10n.Processes.parent, d.parent.map { "\($0.name) · \($0.pid)" }),
                (L10n.Processes.children, children(d.children)),
            ])
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ p: ProcessUsage, _ d: ProcessDetails) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.name).ui(18, 600).lineLimit(1)
                HStack(spacing: 14) {
                    KeyValue(label: L10n.Processes.pidLabel, value: "\(p.pid)")
                    KeyValue(label: L10n.Processes.userLabel, value: d.user ?? "\(p.uid)")
                    if p.isSystem { Text(L10n.Processes.systemProcess).ui(12).foregroundStyle(Theme.sub) }
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CloseButton(action: close)
        }
    }

    private func actionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).ui(13).lineLimit(1)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.raise))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sparkCard(_ label: String, value: String, values: [Double], color: Color, fill: Bool = true) -> some View {
        let top = max(values.max() ?? 0, 0.0001) * 1.1
        let now = Date()
        let points = values.enumerated().map { ChartPoint(date: now.addingTimeInterval(Double($0.offset - values.count + 1) * 3), value: $0.element / top * 100) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).foregroundStyle(Theme.sub)
                Spacer(minLength: 4)
                Text(value).fontWeight(.medium)
            }
            .ui(13)
            ConsoleChart(kind: .area, series: ChartSeries.line(points, color, width: 1.5, fill: fill),
                         span: Double(max(ProcessPoint.kept, 2) * 3), maxValue: 100, height: 24, xLabels: nil, midline: false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private func group(_ title: String, _ rows: [(String, String?)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SmallLabel(text: title).padding(.bottom, 2).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                DividedRows {
                    ForEach(rows, id: \.0) { row in
                        HStack(spacing: 10) {
                            Text(row.0).foregroundStyle(Theme.sub).lineLimit(1).fixedSize()
                            Spacer(minLength: 0)
                            Text(row.1 ?? L10n.Common.dash).lineLimit(1).truncationMode(.tail)
                        }
                        .ui(13)
                        .frame(height: 25)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func pair(_ a: Double, _ b: Double) -> String? {
        a < 1 && b < 1 ? nil : Format.rate(a) + " · " + Format.rate(b)
    }

    /// "Safari 网页内容 ×6", or the most common name and how many there are in all.
    private func children(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let counts = Dictionary(grouping: names, by: { $0 }).mapValues(\.count)
        guard let top = counts.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }) else { return nil }
        if counts.count > 1 { return L10n.Processes.childMore(top.key, names.count) }
        return top.value > 1 ? L10n.Processes.childGroup(top.key, top.value) : top.key
    }
}

/// Round × in the inspector header, tinted under the pointer.
private struct CloseButton: View {
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            LineIcon(d: Icons.close, size: 12, lineWidth: 1.8)
                .foregroundStyle(Theme.sub)
                .frame(width: 26, height: 26)
                .background { if hovering { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.lgHover) } }
                .hoverAnimation(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(L10n.Processes.closeInspector)
        .accessibilityLabel(L10n.Processes.closeInspector)
        .keyboardShortcut(.cancelAction)
    }
}
