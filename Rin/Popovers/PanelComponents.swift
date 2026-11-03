import AppKit
import SwiftUI

// MARK: - Chrome

/// A module dropdown's header: its name (16 / 600), buttons to its monitor page and its settings on the right.
struct PanelHeader: View {
    @Environment(\.panelQuits) private var quits
    var title: String
    var buttons: (openLabel: String, open: () -> Void, settingsLabel: String, settings: () -> Void)?

    init(module: Module) {
        title = module.title
        buttons = (L10n.Panel.openMonitor(module.title), { MainWindowController.shared.show(.monitor(module)) },
                   L10n.Panel.moduleSettings(module.title), { MainWindowController.shared.show(.moduleSettings(module)) })
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title).ui(16, 600).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let buttons {
                HStack(spacing: 2) {
                    HeaderButton(d: Icons.monitorWindow, label: buttons.openLabel, action: buttons.open)
                    HeaderButton(d: Icons.general, label: buttons.settingsLabel, action: buttons.settings)
                    if quits { HeaderButton(d: Icons.power, label: L10n.Panel.quitRin) { NSApp.terminate(nil) } }
                }
                .padding(.trailing, -6)
            }
        }
        .frame(height: 26)
    }
}

private struct PanelQuitsKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// Whether a module's header offers quitting; the details beside the combined dropdown leave it to the dropdown.
    var panelQuits: Bool {
        get { self[PanelQuitsKey.self] }
        set { self[PanelQuitsKey.self] = newValue }
    }
}

/// Icon button in a dropdown header, grey behind it under the pointer.
struct HeaderButton: View {
    var d: String
    var lineWidth: CGFloat = 1.5
    var label: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            LineIcon(d: d, size: 16, lineWidth: lineWidth)
                .foregroundStyle(hovering ? Theme.text : Theme.sub)
                .frame(width: 28, height: 26)
                .background { if hovering { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.lgHover) } }
                .hoverAnimation(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A part of a dropdown: its small grey head (a note or "全部 ›" on the right), then the content.
struct PanelSection<Content: View>: View {
    var title: String
    var right: String? = nil
    /// A process list's "全部" link to the Processes page, sorted by this.
    var link: ProcessSort? = nil
    var top: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeadRow(title: title) {
                if let right { Text(right) }
                if let link { AllProcessesLink(sort: link) }
            }
            content
        }
        .padding(.top, top)
    }
}

/// Label / value line in a dropdown (30 pt).
struct KVRow: View {
    var key: String
    var value: String
    var valueColor: Color = Theme.text

    var body: some View {
        HStack(spacing: 12) {
            Text(key).ui(14).foregroundStyle(Theme.sub)
            Spacer(minLength: 8)
            Reading(text: value, color: valueColor).truncationMode(.middle)
        }
        .frame(height: 30)
        .accessibilityElement(children: .combine)
    }
}

/// Name / thin bar / value line for temperatures, fans and devices (28 pt).
struct MeterRow: View {
    var name: String
    var fraction: Double
    var value: String
    var color: Color = Theme.mid
    var nameWidth: CGFloat = 84
    var valueWidth: CGFloat = 64

    var body: some View {
        HStack(spacing: 12) {
            Text(name).ui(14).foregroundStyle(Theme.sub).lineLimit(1).frame(width: nameWidth, alignment: .leading)
            LevelBar(fraction: fraction, color: color)
            Reading(text: value).frame(width: valueWidth, alignment: .trailing)
        }
        .frame(height: 28)
        .accessibilityElement(children: .combine)
    }
}

/// Top processes in a dropdown: the list icon and the way to all of them, then icon, name (Quit
/// beside it under the pointer) and value.
struct PanelProcessList: View {
    var title: String
    var processes: [ProcessUsage]
    var value: (ProcessUsage) -> String
    var secondary: ((ProcessUsage) -> String)? = nil
    var valueWidth: CGFloat? = nil
    var secondaryWidth: CGFloat = 74
    var rowHeight: CGFloat = 32
    var valueSize: CGFloat = 14
    var link: ProcessSort? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ListHead(tip: title, link: link)
            ProcessTable(processes: processes, value: value, valueWidth: valueWidth, secondary: secondary, secondaryWidth: secondaryWidth, rowHeight: rowHeight, valueSize: valueSize)
        }
        .padding(.top, 16)
    }
}

// MARK: - Process actions

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
                Text(process.name).ui(14, 500).lineLimit(1)
                Text(L10n.Panel.notResponding)
                    .ui(12, 500)
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.chip))
                Spacer(minLength: 4)
                Text(value).ui(14, 500)
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
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.raise))
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
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.dangerFill))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.dangerBg))
    }
}

/// "已退出 Safari · 释放 1.4 GB 内存" confirmation strip.
struct QuitToast: View {
    var toast: QuitCenter.Toast

    var body: some View {
        HStack(spacing: 8) {
            LineIcon(d: Icons.check, size: 13, lineWidth: 2).foregroundStyle(Theme.green)
            Text(L10n.Panel.quitDone(toast.name)).ui(14, 500).lineLimit(1)
            Spacer(minLength: 4)
            if toast.freed > 0 {
                Text(L10n.Panel.freed(Format.memory(toast.freed))).ui(12).foregroundStyle(Theme.sub)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.okBg))
        .accessibilityElement(children: .combine)
    }
}
