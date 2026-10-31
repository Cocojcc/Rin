import AppKit
import SwiftUI

// MARK: - Chrome

/// A module dropdown's header: its name and a note on the left, buttons to its monitor page and
/// its settings on the right.
struct PanelHeader: View {
    var title: String
    var subtitle: String?
    var buttons: (openLabel: String, open: () -> Void, settingsLabel: String, settings: () -> Void)?

    init(module: Module, subtitle: String? = nil) {
        title = module.title
        self.subtitle = subtitle
        buttons = (L10n.Panel.openMonitor(module.title), { MainWindowController.shared.show(.monitor(module)) },
                   L10n.Panel.moduleSettings(module.title), { MainWindowController.shared.show(.moduleSettings(module)) })
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).ui(15, 600).accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).ui(12).foregroundStyle(Theme.sub).lineLimit(1) }
            }
            Spacer(minLength: 0)
            if let buttons {
                HStack(spacing: 2) {
                    HeaderButton(d: Icons.monitorWindow, label: buttons.openLabel, action: buttons.open)
                    HeaderButton(d: Icons.general, label: buttons.settingsLabel, action: buttons.settings)
                }
            }
        }
        .frame(height: 26)
    }
}

/// Every dropdown's last row: other places to go and quitting, as icons on the right.
struct PanelFooter: View {
    var body: some View {
        HStack(spacing: 2) {
            Spacer(minLength: 0)
            HeaderButton(d: Icons.overview, label: L10n.Sidebar.overview) { MainWindowController.shared.show(.overview) }
            HeaderButton(d: Icons.processes, label: L10n.Sidebar.processes) { MainWindowController.shared.show(.processes) }
            HeaderButton(d: Icons.gear, lineWidth: 1.3, label: L10n.Sidebar.settings) { MainWindowController.shared.show(.settings) }
            HeaderButton(d: Icons.power, label: L10n.Menu.quit) { NSApp.terminate(nil) }
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { ConsoleRule() }
    }
}

/// Icon button in a dropdown header or footer, tinted under the pointer.
struct HeaderButton: View {
    var d: String
    var lineWidth: CGFloat = 1.5
    var label: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            LineIcon(d: d, size: 16, lineWidth: lineWidth)
                .foregroundStyle(Theme.sub)
                .frame(width: 28, height: 28)
                .background { if hovering { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.well) } }
                .hoverAnimation(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Section inside a dropdown: small grey title (and note) above its content.
struct PanelSection<Content: View>: View {
    var title: String
    var right: String? = nil
    /// A process list's "全部" link to the Processes page, sorted by this.
    var link: ProcessSort? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelTitle(title: title) {
                if let right { Text(right).ui(12) }
                if let link { AllProcessesLink(sort: link) }
            }
            .padding(.bottom, 4)
            content
        }
    }
}

/// A group of rows or a chart; flat by default, a filled rounded well when given a fill.
struct Well<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets()
    var fill: Color = .clear
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Key / value line in a well (32 pt).
struct KVRow: View {
    var key: String
    var value: String
    var valueColor: Color = Theme.text

    var body: some View {
        HStack(spacing: 12) {
            Text(key).ui(13).foregroundStyle(Theme.sub)
            Spacer(minLength: 8)
            Text(value).ui(13, 500).foregroundStyle(valueColor).lineLimit(1).truncationMode(.middle)
        }
        .frame(height: 26)
        .accessibilityElement(children: .combine)
    }
}

/// Name / bar / value line used for temperatures and fans (28 pt).
struct MeterRow: View {
    var name: String
    var fraction: Double
    var value: String
    var color: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(name).ui(13).foregroundStyle(Theme.sub).lineLimit(1).frame(width: 76, alignment: .leading)
            DotMeter(fraction: fraction, color: color, count: 20)
            Text(value).ui(13, 500).lineLimit(1).frame(width: 64, alignment: .trailing)
        }
        .frame(height: 24)
        .accessibilityElement(children: .combine)
    }
}

/// Top processes in a dropdown: the monitor-page list at popover proportions.
struct PanelProcessList: View {
    var title: String
    var processes: [ProcessUsage]
    var metric: ProcessMetric
    var color: Color
    var nameWidth: CGFloat = 96
    var valueWidth: CGFloat = 56
    var link: ProcessSort? = nil

    var body: some View {
        PanelSection(title: title, link: link) {
            ProcessListPanel(processes: processes, metric: metric, color: color,
                             rowHeight: 28, nameWidth: nameWidth, valueWidth: valueWidth, rowPadding: 6,
                             fill: .clear, radius: 0)
        }
    }
}

// MARK: - Process actions

enum ProcessMetric {
    case cpu, memory, disk, network, gpu

    func value(_ p: ProcessUsage) -> Double {
        switch self {
        case .cpu: return p.cpu
        case .memory: return Double(p.memory)
        case .disk: return p.diskTotal
        case .network: return p.netTotal
        case .gpu: return p.gpu
        }
    }

    func text(_ p: ProcessUsage) -> String {
        switch self {
        case .cpu: return Format.percentValue(p.cpu)
        case .memory: return Format.memory(p.memory)
        case .disk: return Format.rate(p.diskTotal)
        case .network: return Format.rate(p.netTotal)
        case .gpu: return Format.percentValue(p.gpu)
        }
    }
}

/// Right-click menu on a process row (native menu).
struct ProcessContextMenu: View {
    var process: ProcessUsage

    var body: some View {
        if !process.isSystem {
            Button(L10n.Panel.quitNamed(process.name)) { QuitCenter.shared.quit(process) }
            Button(L10n.Panel.forceQuitEllipsis) { QuitCenter.shared.askForceQuit(process) }
            Divider()
        }
        Button(L10n.Panel.showInActivityMonitor) { ProcessActions.openActivityMonitor() }
        if process.bundlePath != nil || process.executablePath != nil {
            Button(L10n.Panel.showInFinder) { ProcessActions.reveal(process) }
        }
        Divider()
        Button(L10n.Panel.copyNamePID) { ProcessActions.copyNameAndPID(process) }
    }
}

/// Shown above the list when an app didn't quit within a few seconds.
struct ConfirmForceQuitRow: View {
    var process: ProcessUsage
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ProcessIcon(process: process, size: 18)
                Text(process.name).ui(13, 500).lineLimit(1)
                Text(L10n.Panel.notResponding)
                    .ui(12, 500)
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.raised))
                Spacer(minLength: 4)
                Text(value).ui(13, 500)
            }
            .frame(height: 20)
            Text(L10n.Panel.forceQuitWarning)
                .ui(12)
                .foregroundStyle(Theme.sub)
                .padding(.top, 8)
            HStack(spacing: 8) {
                Button {
                    QuitCenter.shared.cancel(process)
                } label: {
                    Text(L10n.Common.cancel).ui(12)
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised).raisedShadow())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    QuitCenter.shared.forceQuit(process)
                } label: {
                    Text(L10n.Panel.forceQuit).ui(12, 500)
                        .foregroundStyle(Theme.onDanger)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.dangerFill))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.dangerBg))
    }
}

/// "已退出 Safari · 释放 1.4 GB 内存" confirmation strip.
struct QuitToast: View {
    var toast: QuitCenter.Toast

    var body: some View {
        HStack(spacing: 8) {
            LineIcon(d: Icons.check, size: 13, lineWidth: 2).foregroundStyle(Theme.ok)
            Text(L10n.Panel.quitDone(toast.name)).ui(13, 500).lineLimit(1)
            Spacer(minLength: 4)
            if toast.freed > 0 {
                Text(L10n.Panel.freed(Format.memory(toast.freed))).ui(12).foregroundStyle(Theme.sub)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.okBg))
        .accessibilityElement(children: .combine)
    }
}

/// Top-process list on a panel. Hovering a row raises it and offers Quit; right click has the rest.
struct ProcessListPanel: View {
    var processes: [ProcessUsage]
    var metric: ProcessMetric
    var color: Color
    var rowHeight: CGFloat = 34
    var nameWidth: CGFloat = 130
    var valueWidth: CGFloat = 60
    var rowPadding: CGFloat = 10
    var fill: Color = Theme.panel
    var radius: CGFloat = 16
    var quitCenter = QuitCenter.shared
    @State private var hovered: String?

    var body: some View {
        let maxValue = max(processes.map(metric.value).max() ?? 1, 0.0001)
        let stuck = processes.filter { quitCenter.states[$0.id] == .unresponsive }
        let rest = processes.filter { quitCenter.states[$0.id] != .unresponsive }
        VStack(spacing: 6) {
            // An app that didn't quit asks for confirmation above the list.
            ForEach(stuck) { ConfirmForceQuitRow(process: $0, value: metric.text($0)) }
            if !rest.isEmpty || stuck.isEmpty {
                VStack(spacing: 0) {
                    if processes.isEmpty {
                        Text(L10n.Panel.noProcesses).ui(13).foregroundStyle(Theme.faint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, rowPadding)
                            .frame(height: rowHeight)
                    }
                    ForEach(rest) { row($0, fraction: metric.value($0) / maxValue) }
                }
                .padding(fill == .clear ? 0 : 4)
                .padding(.horizontal, fill == .clear ? -rowPadding : 0)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            }
        }
    }

    private func row(_ p: ProcessUsage, fraction: Double) -> some View {
        let isHover = hovered == p.id && !p.isSystem
        return HStack(spacing: 10) {
            ProcessIcon(process: p, size: 14)
            Text(p.name).ui(13).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                DotMeter(fraction: fraction * 0.9, color: color, count: 16).frame(width: 56)
            }
            Text(metric.text(p)).ui(13, 500).lineLimit(1).frame(width: valueWidth, alignment: .trailing)
        }
        .padding(.horizontal, rowPadding)
        .frame(height: rowHeight)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(isHover ? Theme.lgHover : Color.clear))
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = p.id } else if hovered == p.id { hovered = nil }
        }
        .contextMenu { ProcessContextMenu(process: p) }
        .accessibilityElement(children: .combine)
    }
}

/// Network dropdown's busiest processes: name, download (500) and upload (grey) columns.
struct TrafficList: View {
    var processes: [ProcessUsage]
    var unit: SpeedUnit
    /// Always this many rows tall, so the dropdown doesn't change height as apps come and go.
    var rows = 5

    var body: some View {
        VStack(spacing: 0) {
            if processes.isEmpty {
                Text(L10n.Panel.noProcesses).ui(13).foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .frame(height: 30)
            }
            ForEach(processes) { p in
                HStack(spacing: 10) {
                    ProcessIcon(process: p, size: 14)
                    Text(p.name).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                    Text(MenuBarText.downArrow + " " + Format.rate(p.netDown, unit: unit)).fontWeight(.medium).lineLimit(1)
                        .frame(width: 76, alignment: .trailing)
                    Text(MenuBarText.upArrow + " " + Format.rate(p.netUp, unit: unit)).foregroundStyle(Theme.sub).lineLimit(1)
                        .frame(width: 64, alignment: .trailing)
                }
                .ui(13)
                .frame(height: 28)
                .contentShape(Rectangle())
                .contextMenu { ProcessContextMenu(process: p) }
                .accessibilityElement(children: .combine)
            }
            ForEach(0..<max(0, rows - max(processes.count, 1)), id: \.self) { _ in
                Color.clear.frame(height: 28).accessibilityHidden(true)
            }
        }
    }
}
