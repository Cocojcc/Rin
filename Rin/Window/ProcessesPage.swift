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
        case .cpu, .gpu: return 44
        case .memory: return 60
        case .energy: return 56
        case .disk, .network: return 64
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

/// "全部 ›" after a process list's section title: opens the Processes page sorted by that list.
struct AllProcessesLink: View {
    var sort: ProcessSort
    @State private var hovering = false

    var body: some View {
        Button {
            MainWindowController.shared.showProcesses(sortedBy: sort)
        } label: {
            HStack(spacing: 4) {
                Text(L10n.Processes.viewAll).ui(12)
                LineIcon(d: Icons.linkChevron, width: 6, height: 10, viewBox: CGSize(width: 6, height: 10), lineWidth: 1.4)
            }
            .foregroundStyle(Theme.sub)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                if hovering { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.lgHover) }
            }
            .hoverAnimation(hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(L10n.Processes.viewAllA11y)
        // The hover box reaches past the text, as the design's negative margins.
        .padding(.vertical, -3)
        .padding(.trailing, -6)
        .padding(.leading, 10)
    }
}

// MARK: - Page

struct ProcessesPage: View {
    /// The row selected when the page opens (debug snapshots render the inspector this way).
    static var initialSelection: String?

    var monitor = Monitor.shared
    var navigator = Navigator.shared
    @State private var search = ""
    @State private var filter: ProcessFilter = .all
    @State private var selected: String? = ProcessesPage.initialSelection

    var body: some View {
        let s = monitor.snapshot.processes
        let rows = sorted(s.all)
        let selection = selected.flatMap { id in s.all.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(title: L10n.Sidebar.processes) { SearchField(text: $search) }
            HStack(spacing: 12) {
                Segmented(label: L10n.Processes.filterLabel, options: ProcessFilter.allCases.map { ($0, $0.title) },
                          selection: $filter, style: .range)
                    .fixedSize()
                Spacer(minLength: 0)
                Text(L10n.Monitor.processThreads(grouped(s.processCount), grouped(s.threadCount)))
                    .ui(12).foregroundStyle(Theme.sub).lineLimit(1)
                    .padding(.trailing, 14)
            }
            HStack(alignment: .top, spacing: 12) {
                ProcessGrid(rows: rows, allColumns: columns(inspecting: selection != nil),
                            sort: navigator.processSort, selected: $selected) { navigator.processSort = $0 }
                if let selection {
                    ProcessInspector(process: selection) { selected = nil }
                        .frame(width: 236)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
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
        let query = search.trimmingCharacters(in: .whitespaces)
        let sort = navigator.processSort
        return all
            .filter { filter.includes($0) }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || "\($0.pid)" == query }
            .sorted {
                let a = sort.value($0), b = sort.value($1)
                return a != b ? a > b : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private func grouped(_ n: Int) -> String { n.formatted(.number.grouping(.automatic)) }
}

/// Glass search capsule in the page title (180 × 28).
private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            LineIcon(d: Icons.search, size: 12, viewBox: 12, lineWidth: 1.4).foregroundStyle(Theme.sub)
            if RenderContext.offscreen {
                // ImageRenderer can't draw text fields.
                Text(L10n.Processes.search).ui(12).foregroundStyle(Theme.sub).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(L10n.Processes.search, text: $text, prompt: Text(L10n.Processes.search).foregroundStyle(Theme.sub))
                    .textFieldStyle(.plain)
                    .ui(12)
                    .foregroundStyle(Theme.text)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 180, height: 28)
        .background(GlassTrack())
        .accessibilityElement(children: .contain)
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
            28 + 8 + 26 + Self.minNameWidth + cols.reduce(0) { $0 + $1.width + 8 }
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
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(L10n.Processes.name).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(columns, id: \.self) { column in
                let on = column == sort
                Button {
                    onSort(column)
                } label: {
                    HStack(spacing: 3) {
                        if on { LineIcon(d: Icons.sortChevron, size: 8, viewBox: 8, lineWidth: 1.4) }
                        Text(column.title).fontWeight(on ? .medium : .regular).lineLimit(1)
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
        .padding(.horizontal, 14)
        .frame(height: 32)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
    }

    private func list(_ rows: [ProcessUsage]) -> some View {
        LazyVStack(spacing: 1) {
            if rows.isEmpty {
                Text(L10n.Panel.noProcesses).ui(13).foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
            }
            ForEach(rows) { p in
                ProcessGridRow(process: p, columns: columns, selected: selected == p.id) {
                    selected = selected == p.id ? nil : p.id
                }
            }
        }
        .padding(4)
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
            HStack(spacing: 8) {
                ProcessIcon(process: process, size: 18)
                Text(process.name).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(columns, id: \.self) { column in
                    Group {
                        if let text = column.text(process) {
                            Text(text)
                        } else {
                            Text(L10n.Common.dash).foregroundStyle(Theme.sub)
                        }
                    }
                    .lineLimit(1)
                    .frame(width: column.width, alignment: .trailing)
                }
            }
            .ui(13)
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background {
                if selected {
                    GlassThumb(cornerRadius: 10)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.well)
                }
            }
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
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Processes.inspector)
    }

    private func content(_ p: ProcessUsage, _ d: ProcessDetails, _ history: [ProcessPoint]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(p, d)
            if !p.isSystem {
                if quitCenter.states[p.id] == .unresponsive {
                    ConfirmForceQuitRow(process: p, value: Format.memory(p.memory))
                } else {
                    HStack(spacing: 8) {
                        actionButton(quitCenter.states[p.id] == .quitting ? L10n.Panel.quitting : L10n.Panel.quit, color: Theme.text) {
                            quitCenter.quit(p)
                        }
                        actionButton(L10n.Panel.forceQuit, color: Theme.danger) { quitCenter.askForceQuit(p) }
                    }
                }
            }
            sparkCard(L10n.Module.cpu, value: Format.percentValue(p.cpu), values: history.map(\.cpu), color: Theme.cpu)
            sparkCard(L10n.Module.memory, value: Format.memory(p.memory), values: history.map(\.memory), color: Theme.mem)
            group(L10n.Processes.details, [
                (L10n.Processes.cpuTime, p.cpuTime > 0 ? Format.hms(p.cpuTime) : nil),
                (L10n.Processes.threads, d.threads.map { "\($0)" }),
                (L10n.Processes.energy, p.energy >= 0.005 ? Format.appWatts(p.energy) : nil),
                (L10n.Processes.diskReadWrite, pair(p.diskRead, p.diskWrite)),
                (L10n.Processes.networkInOut, pair(p.netDown, p.netUp)),
                (L10n.Processes.started, d.started.map(Format.dayAndTime)),
            ])
            group(L10n.Processes.relations, [
                (L10n.Processes.parent, d.parent.map { "\($0.name) · \($0.pid)" }),
                (L10n.Processes.children, children(d.children)),
            ])
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ p: ProcessUsage, _ d: ProcessDetails) -> some View {
        var subtitle = L10n.Processes.pidUser("\(p.pid)", d.user ?? "\(p.uid)")
        if p.isSystem { subtitle += " · " + L10n.Processes.systemProcess }
        return HStack(alignment: .top, spacing: 10) {
            ProcessIcon(process: p, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(p.name).ui(15, 500).lineLimit(1).frame(height: 20)
                Text(subtitle).ui(12).foregroundStyle(Theme.sub).lineLimit(1).frame(height: 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CloseButton(action: close)
        }
    }

    private func actionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).ui(12, 500).lineLimit(1)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.well))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sparkCard(_ label: String, value: String, values: [Double], color: Color) -> some View {
        let top = max(values.max() ?? 0, 0.0001) * 1.1
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).foregroundStyle(Theme.sub)
                Spacer(minLength: 4)
                Text(value).fontWeight(.medium)
            }
            .ui(12)
            .frame(height: 16)
            MiniChart(series: [MiniChart.Series(values: values.map { $0 / top }, color: color, fill: 0.16)],
                      gridLines: 0, minCount: ProcessPoint.kept)
                .frame(height: 28)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.well))
        .accessibilityElement(children: .combine)
    }

    private func group(_ title: String, _ rows: [(String, String?)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).ui(12, 500).foregroundStyle(Theme.sub).frame(height: 16).padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows, id: \.0) { row in
                HStack(spacing: 10) {
                    Text(row.0).foregroundStyle(Theme.sub).lineLimit(1).fixedSize()
                    Spacer(minLength: 0)
                    Text(row.1 ?? L10n.Common.dash).fontWeight(.medium).lineLimit(1).truncationMode(.tail)
                }
                .ui(12)
                .frame(height: 24)
                .accessibilityElement(children: .combine)
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
            LineIcon(d: Icons.closeSmall, size: 10, viewBox: 10, lineWidth: 1.4)
                .foregroundStyle(Theme.sub)
                .frame(width: 24, height: 24)
                .background { if hovering { Circle().fill(Theme.lgHover) } }
                .hoverAnimation(hovering)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(L10n.Processes.closeInspector)
        .accessibilityLabel(L10n.Processes.closeInspector)
        .keyboardShortcut(.cancelAction)
    }
}
