import SwiftUI

/// One question the Processes page answers: who is busy, who holds memory, who moves data, who reads
/// and writes, who draws power. Each tab has the columns that answer it and nothing else: how the
/// whole Mac stands is what the module pages are for. A row is an app with its helpers folded in, so
/// PID is the main process's.
enum ProcessTab: CaseIterable, Hashable {
    case cpu, memory, network, disk, energy

    var title: String {
        switch self {
        case .cpu: return L10n.Module.cpu
        case .memory: return L10n.Module.memory
        case .network: return L10n.Module.network
        case .disk: return L10n.Module.disk
        case .energy: return L10n.Processes.energy
        }
    }

    var columns: [(title: String, width: CGFloat)] {
        let threads = L10n.Processes.threads, pid = L10n.Processes.pidLabel
        switch self {
        case .cpu: return [(L10n.Processes.usage, 60), (L10n.Processes.cpuTime, 76), (threads, 48), (pid, 52)]
        case .memory: return [(L10n.Processes.usage, 68), (L10n.Processes.share, 52), (L10n.Memory.compressed, 68), (threads, 48), (pid, 52)]
        case .network: return [(L10n.Panel.download, 76), (L10n.Panel.upload, 76), (L10n.Processes.downloaded, 72), (L10n.Processes.uploaded, 72), (pid, 52)]
        case .disk: return [(L10n.Disk.read, 76), (L10n.Disk.write, 76), (L10n.Processes.totalRead, 72), (L10n.Processes.totalWritten, 72), (pid, 52)]
        case .energy: return [(L10n.Processes.power, 68), (L10n.Processes.energyUsed, 76), (pid, 52)]
        }
    }

    /// The last column, which is quieter than the readings.
    var pidColumn: Int { columns.count - 1 }

    /// Both directions count towards the order until a column is picked.
    var defaultColumn: Int? { self == .network || self == .disk ? nil : 0 }

    /// Network, disk and energy list only the apps that have done any of it; anything else would be a row of dashes.
    func lists(_ p: ProcessUsage) -> Bool {
        switch self {
        case .cpu, .memory: return true
        case .network: return p.totalDown + p.totalUp > 0
        case .disk: return p.totalRead + p.totalWritten > 0
        case .energy: return p.energyUsed >= 0.01
        }
    }

    func value(_ p: ProcessUsage, column: Int?) -> Double {
        switch (self, column) {
        case (.cpu, 1): return p.cpuTime
        case (.cpu, 2), (.memory, 3): return Double(p.threads)
        case (.cpu, 3), (.memory, 4), (.network, 4), (.disk, 4), (.energy, 2): return Double(p.pid)
        case (.cpu, _): return p.cpu
        case (.memory, 2): return Double(p.compressed)
        case (.memory, _): return Double(p.memory)
        case (.network, 0): return p.recentDown
        case (.network, 1): return p.recentUp
        case (.network, 2): return Double(p.totalDown)
        case (.network, 3): return Double(p.totalUp)
        case (.network, _): return p.recentDown + p.recentUp
        case (.disk, 0): return p.recentRead
        case (.disk, 1): return p.recentWrite
        case (.disk, 2): return Double(p.totalRead)
        case (.disk, 3): return Double(p.totalWritten)
        case (.disk, _): return p.recentRead + p.recentWrite
        case (.energy, 1): return p.energyUsed
        case (.energy, _): return p.energy
        }
    }

    /// What orders the rows a column leaves level: what has piled up while both directions count, the second column after the first.
    func next(_ p: ProcessUsage, column: Int?) -> Double {
        switch column {
        case nil: return value(p, column: 2) + value(p, column: 3)
        case 0: return value(p, column: 1)
        default: return 0
        }
    }

    /// The cell text, or nil for nothing (drawn as a grey dash).
    func text(_ p: ProcessUsage, column: Int) -> String? {
        switch (self, column) {
        case (.cpu, 0): return Format.percentValue(p.cpu)
        case (.cpu, 1): return p.cpuTime > 0 ? Format.hms(p.cpuTime) : nil
        case (.cpu, 2), (.memory, 3): return p.threads > 0 ? "\(p.threads)" : nil
        case (.memory, 0): return p.memory > 0 ? Format.memory(p.memory) : nil
        case (.memory, 1): return p.memory > 0 ? Format.percentValue(Double(p.memory) / Double(ProcessInfo.processInfo.physicalMemory) * 100) : nil
        case (.memory, 2): return p.compressed > 0 ? Format.memory(p.compressed) : nil
        case (.network, 0): return Self.speed(p.recentDown)
        case (.network, 1): return Self.speed(p.recentUp)
        case (.network, 2): return Self.size(p.totalDown)
        case (.network, 3): return Self.size(p.totalUp)
        case (.disk, 0): return Self.rate(p.recentRead)
        case (.disk, 1): return Self.rate(p.recentWrite)
        case (.disk, 2): return Self.size(p.totalRead)
        case (.disk, 3): return Self.size(p.totalWritten)
        // In a list of who draws power, next to nothing reads 0.00 W rather than a dash.
        case (.energy, 0): return Format.appWatts(p.energy)
        case (.energy, 1): return Format.wattHours(p.energyUsed)
        default: return "\(p.pid)"
        }
    }

    /// Bytes a second below which an app counts as not moving data: the figure would read 0.0 KB/s.
    fileprivate static let quietRate = 50.0

    private static func rate(_ v: Double) -> String? { v >= quietRate ? Format.rate(v) : nil }
    private static func speed(_ v: Double) -> String? { v >= quietRate ? Format.rate(v, unit: SettingsStore.shared.prefs.network.speedUnit) : nil }
    private static func size(_ v: UInt64) -> String? { v > 0 ? Format.storage(v) : nil }
}

/// Which tab a "›" link opens the Processes page on.
enum ProcessSort {
    case cpu, memory, network, disk, energy, gpu

    var tab: ProcessTab {
        switch self {
        case .cpu, .gpu: return .cpu
        case .memory: return .memory
        case .network: return .network
        case .disk: return .disk
        case .energy: return .energy
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
    /// The row selected and the filter when the page opens (debug snapshots render them this way).
    static var initialSelection: String?
    static var initialFilter = ProcessFilter.all

    var monitor = Monitor.shared
    var navigator = Navigator.shared
    @State private var filter = ProcessesPage.initialFilter
    @State private var selected: String? = ProcessesPage.initialSelection

    var body: some View {
        let s = monitor.processes
        let tab = navigator.processTab
        let listed = s.all.filter { tab.lists($0) && filter.includes($0) }
        // A column with nothing to say for these rows isn't drawn. Searching doesn't count, or columns would come and go while typing.
        let present = tab.columns.indices.filter { i in listed.isEmpty || listed.contains { tab.text($0, column: i) != nil } }
        let wanted = navigator.processColumns[tab] ?? tab.defaultColumn
        let column = wanted.map { present.contains($0) ? $0 : present[0] } ?? (present.contains { $0 < 2 } ? nil : present.first)
        let rows = sorted(listed, tab: tab, column: column)
        let selection = selected.flatMap { id in s.all.first { $0.id == id } }
        // The inspector needs the room: the first two columns stay, or the first and the one being sorted by.
        let at = column.flatMap(present.firstIndex(of:)) ?? 0
        let shown = selection == nil ? present : at > 1 ? [present[0], present[at]] : Array(present.prefix(2))
        HStack(alignment: .top, spacing: 24) {
            ProcessGrid(rows: rows, tab: tab, column: column, shown: shown, filter: $filter, selected: $selected) { navigator.processColumns[tab] = $0 }
            if let selection {
                ProcessInspector(process: selection) { selected = nil }
                    .frame(width: 212)
                    .padding(.leading, 24)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // The list runs out under the window's edge, as a scrolling list does.
        .padding(.bottom, -Sidebar.bottomInset)
        .animation(Motion.slide, value: selection?.id)
    }

    private func sorted(_ listed: [ProcessUsage], tab: ProcessTab, column: Int?) -> [ProcessUsage] {
        let query = navigator.processQuery.trimmingCharacters(in: .whitespaces)
        return listed
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || "\($0.pid)" == query }
            .map { (process: $0, value: tab.value($0, column: column), next: tab.next($0, column: column)) }
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                if $0.next != $1.next { return $0.next > $1.next }
                return $0.process.name.localizedStandardCompare($1.process.name) == .orderedAscending
            }
            .map(\.process)
    }
}

// MARK: - Table

private struct ProcessGrid: View {
    var rows: [ProcessUsage]
    var tab: ProcessTab
    var column: Int?
    var shown: [Int]
    @Binding var filter: ProcessFilter
    @Binding var selected: String?
    var onSort: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if RenderContext.offscreen {
                // Snapshots can't scroll; the first screenful stands in for the list.
                list(Array(rows.prefix(21))).frame(minHeight: 0, maxHeight: .infinity, alignment: .top).clipped()
            } else {
                ScrollView { list(rows) }.scrollIndicators(.automatic)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ProcessFilterMenu(selection: $filter).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(shown, id: \.self) { i in
                let info = tab.columns[i]
                // With no column picked, both directions lead together.
                let strong = column == i || (column == nil && i < 2)
                Button {
                    onSort(i)
                } label: {
                    HStack(spacing: 3) {
                        if column == i { LineIcon(d: Icons.sortChevron, size: 8, viewBox: 8, lineWidth: 1.4) }
                        Text(info.title).ui(12, strong ? 500 : 400).lineLimit(1)
                    }
                    // A long name may reach into the gap beside it rather than be cut short.
                    .fixedSize()
                    .foregroundStyle(strong ? Theme.text : Theme.sub)
                    .frame(width: info.width, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(info.title)
                .accessibilityAddTraits(column == i ? [.isSelected] : [])
            }
        }
        .frame(height: 28)
        .padding(.bottom, 4)
    }

    private func list(_ rows: [ProcessUsage]) -> some View {
        LazyVStack(spacing: 0) {
            if rows.isEmpty {
                Text(L10n.Panel.noProcesses).ui(14).foregroundStyle(Theme.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 30)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, p in
                ProcessGridRow(process: p, tab: tab, column: column, shown: shown, striped: index % 2 == 1, selected: selected == p.id) {
                    selected = selected == p.id ? nil : p.id
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Processes.listLabel)
    }
}

/// Which processes the list holds, where the names' column head would be.
private struct ProcessFilterMenu: View {
    @Binding var selection: ProcessFilter
    @State private var hovering = false

    var body: some View {
        Menu {
            ForEach(ProcessFilter.allCases, id: \.self) { filter in
                Button {
                    selection = filter
                } label: {
                    if filter == selection { Label(filter.title, systemImage: "checkmark") } else { Text(filter.title) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection.title).ui(12).lineLimit(1)
                LineIcon(d: Icons.sortChevron, size: 8, viewBox: 8, lineWidth: 1.4)
            }
            .foregroundStyle(selection == .all ? Theme.sub : Theme.text)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background { if hovering { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.lgHover) } }
            .hoverAnimation(hovering)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .padding(.leading, -8)
        .onHover { hovering = $0 }
        .accessibilityLabel(L10n.Processes.filterLabel)
    }
}

private struct ProcessGridRow: View {
    var process: ProcessUsage
    var tab: ProcessTab
    var column: Int?
    var shown: [Int]
    var striped: Bool
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    AppIcon(process: process)
                    Text(process.name).lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(shown, id: \.self) { i in
                    Group {
                        if let text = tab.text(process, column: i) {
                            Reading(text: text, weight: column == i || (column == nil && i < 2) ? 500 : 400, color: i == tab.pidColumn ? Theme.sub : Theme.text)
                        } else {
                            Text(L10n.Common.dash).foregroundStyle(Theme.sub)
                        }
                    }
                    .lineLimit(1)
                    .frame(width: tab.columns[i].width, alignment: .trailing)
                }
            }
            .ui(14)
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background {
                if selected || hovering || striped {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? Theme.raise : hovering ? Theme.lgHover : Theme.well)
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
            group([
                (L10n.Processes.cpuTime, p.cpuTime > 0 ? Format.hms(p.cpuTime) : nil),
                // The whole group's, as on its row, once `top` has reported it.
                (L10n.Processes.threads, (p.threads > 0 ? p.threads : d.threads).map { "\($0)" }),
                (L10n.Processes.energy, p.energy >= 0.005 ? Format.appWatts(p.energy) : nil),
                (L10n.Processes.diskReadWrite, pair(p.recentRead, p.recentWrite)),
                (L10n.Processes.networkInOut, pair(p.recentDown, p.recentUp)),
                (L10n.Processes.started, d.started.map(Format.dayAndTime)),
            ])
            .padding(.top, 14)
            group([
                (L10n.Processes.parent, d.parent.map { "\($0.name) · \($0.pid)" }),
                (L10n.Processes.children, children(d.children)),
            ])
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ p: ProcessUsage, _ d: ProcessDetails) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AppIcon(process: p, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name).ui(16, 600).lineLimit(1)
                HStack(spacing: 14) {
                    KeyValue(label: L10n.Processes.pidLabel, value: "\(p.pid)")
                    KeyValue(label: L10n.Processes.userLabel, value: d.user ?? "\(p.uid)")
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CloseButton(action: close)
        }
        .frame(minHeight: 42, alignment: .top)
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
                         span: Double(max(ProcessPoint.kept, 2) * 3), maxValue: 100, height: 24, midline: false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private func group(_ rows: [(String, String?)]) -> some View {
        VStack(spacing: 0) {
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

    private func pair(_ a: Double, _ b: Double) -> String? {
        max(a, b) < ProcessTab.quietRate ? nil : Format.rate(a) + " · " + Format.rate(b)
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
