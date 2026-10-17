import AppKit
import SwiftUI

/// White card inside a dropdown (10 radius).
struct PanelCard<Content: View>: View {
    var padding = EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.popGroup))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.groupRim, lineWidth: 0.5))
    }
}

struct PanelHeader<Value: View>: View {
    var icon: String
    var color: Color
    var title: String
    var subtitle: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 10) {
            IconChip(d: icon, size: 28, iconSize: 16, radius: 7, color: color, fill: Theme.chip)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 14, weight: .bold)).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.sub).lineLimit(1)
            }
            Spacer(minLength: 4)
            value
        }
        .frame(height: 40)
        .padding(.horizontal, 2)
    }
}

/// Small grey card title with an optional faint note on the right (24 pt row).
struct PanelTitle: View {
    var text: String
    var right: String? = nil

    var body: some View {
        HStack {
            Text(text).fontWeight(.semibold).foregroundStyle(Theme.sub)
            Spacer()
            if let right { Text(right).foregroundStyle(Theme.faint) }
        }
        .font(.system(size: 11))
        .frame(height: 24)
    }
}

struct PanelLegend: View {
    var items: [(Color, String, String?)]
    var right: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                LegendDot(color: item.0, label: item.1, value: item.2)
            }
            Spacer(minLength: 0)
            if let right { Text(right).font(.system(size: 11)).foregroundStyle(Theme.faint) }
        }
        .padding(.top, 8)
    }
}

/// A key / value line inside a card (30 pt).
struct KVRow: View {
    var key: String
    var value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(key).foregroundStyle(Theme.sub)
            Spacer(minLength: 8)
            Text(value).fontWeight(.semibold).monospacedDigit().lineLimit(1).truncationMode(.middle)
        }
        .frame(height: 30)
        .accessibilityElement(children: .combine)
    }
}

/// 0.5 pt rule inside a 1 pt box, so the rows around it stay on whole points
/// (a bare 0.5 pt view shifts everything below by half a point and blurs every other line).
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 0.5).frame(height: 1, alignment: .top)
    }
}

/// Name / bar / value line used for temperatures and fans (26 pt).
struct MeterRow: View {
    var name: String
    var fraction: Double
    var value: String
    var color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(name).lineLimit(1)
            Spacer(minLength: 4)
            MeterBar(fraction: fraction, color: color).frame(width: 80)
            Text(value).fontWeight(.semibold).monospacedDigit().frame(width: 64, alignment: .trailing)
        }
        .frame(height: 26)
        .accessibilityElement(children: .combine)
    }
}

struct PanelFooter: View {
    var module: Module
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 6) {
            TintButton(title: L10n.Panel.openMonitor(module.title)) {
                MainWindowController.shared.show(.monitor(module))
            }
            Button {
                MainWindowController.shared.show(.menubarModule(module))
            } label: {
                LineIcon(d: Icons.general, size: 14, lineWidth: 1.6)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.well))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Panel.moduleSettings(module.title))
        }
    }
}

// MARK: - Process list with quit controls

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

struct PanelProcessList: View {
    var title: String
    var processes: [ProcessUsage]
    var metric: ProcessMetric
    var color: Color
    var quitCenter = QuitCenter.shared
    @State private var hovered: String?

    var body: some View {
        PanelCard(padding: EdgeInsets(top: 2, leading: 12, bottom: 4, trailing: 12)) {
            PanelTitle(text: title)
            if processes.isEmpty {
                Text(L10n.Panel.noProcesses).foregroundStyle(Theme.faint).frame(height: 30)
            }
            let maxValue = max(processes.map(metric.value).max() ?? 1, 0.0001)
            ForEach(Array(processes.enumerated()), id: \.element.id) { index, p in
                if quitCenter.states[p.id] == .unresponsive {
                    ConfirmForceQuitRow(process: p, value: metric.text(p))
                        .padding(.vertical, 2)
                } else {
                    row(p, fraction: metric.value(p) / maxValue, showTopLine: index > 0 && hovered != processes[index - 1].id)
                }
            }
        }
    }

    private func row(_ p: ProcessUsage, fraction: Double, showTopLine: Bool) -> some View {
        let isHover = hovered == p.id && !p.isSystem
        return HStack(spacing: 8) {
            ProcessIcon(process: p, size: 20)
            Text(p.name).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if isHover {
                Button {
                    quitCenter.quit(p)
                } label: {
                    Text(quitCenter.states[p.id] == .quitting ? L10n.Panel.quitting : L10n.Panel.quit)
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.popGroup)
                                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.groupRim, lineWidth: 0.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Panel.quitNamed(p.name))
            } else {
                MeterBar(fraction: fraction, color: color).frame(width: 56)
            }
            Text(metric.text(p)).fontWeight(.semibold).monospacedDigit().frame(width: 58, alignment: .trailing)
        }
        .frame(height: 30)
        .padding(.horizontal, isHover ? 6 : 0)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isHover ? Theme.hover : .clear))
        .padding(.horizontal, isHover ? -6 : 0)
        .overlay(alignment: .top) { if showTopLine && !isHover { Hairline() } }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = p.id } else if hovered == p.id { hovered = nil }
        }
        .contextMenu { ProcessContextMenu(process: p) }
        .accessibilityElement(children: .combine)
    }
}

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

/// Inline confirmation shown when an app didn't quit within a few seconds.
struct ConfirmForceQuitRow: View {
    var process: ProcessUsage
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ProcessIcon(process: process, size: 20)
                Text(process.name).fontWeight(.semibold).lineLimit(1)
                Text(L10n.Panel.notResponding)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dangerText)
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.popGroup))
                Spacer(minLength: 4)
                Text(value).fontWeight(.semibold).monospacedDigit()
            }
            Text(L10n.Panel.forceQuitWarning)
                .font(.system(size: 11))
                .foregroundStyle(Theme.sub)
                .padding(.leading, 28)
                .padding(.top, 6)
            HStack(spacing: 6) {
                Spacer()
                Button {
                    QuitCenter.shared.cancel(process)
                } label: {
                    Text(L10n.Common.cancel)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.popGroup))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.groupRim, lineWidth: 0.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    QuitCenter.shared.forceQuit(process)
                } label: {
                    Text(L10n.Panel.forceQuit)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.danger))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.dangerBg))
        .padding(.horizontal, -6)
    }
}

/// "已退出 Safari · 释放 1.4 GB 内存" confirmation strip.
struct QuitToast: View {
    var toast: QuitCenter.Toast

    var body: some View {
        HStack(spacing: 8) {
            LineIcon(d: Icons.check, size: 14, lineWidth: 2).foregroundStyle(Theme.ok)
            Text(L10n.Panel.quitDone(toast.name)).fontWeight(.semibold).lineLimit(1)
            Spacer(minLength: 4)
            if toast.freed > 0 {
                Text(L10n.Panel.freed(Format.memory(toast.freed))).font(.system(size: 11)).foregroundStyle(Theme.sub)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.okBg))
        .accessibilityElement(children: .combine)
    }
}
