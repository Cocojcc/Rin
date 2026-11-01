import AppKit
import SwiftUI

/// About This Mac: the model, how long it has been up and its volumes as figures, then the
/// hardware and software facts side by side.
struct AboutPage: View {
    @State private var info = MacInfo.read()
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: info.modelName, spec: subtitle) {
                IconAction(d: copied ? Icons.check : Icons.copy, label: copied ? L10n.About.copied : L10n.About.copyA11y, size: 32, raised: true) { copy() }
            }
            HStack(alignment: .top, spacing: 0) {
                cell(L10n.About.uptimeLabel, first: true) {
                    let up = uptime
                    BigValue(value: up.0, unit: up.1, size: 44)
                }
                ForEach(info.volumes.prefix(2), id: \.name) { v in
                    cell(v.name) {
                        let free = Format.parts(Format.storage(v.available))
                        BigValue(value: free.0, unit: L10n.Monitor.unitFree(free.1), size: 44)
                        LevelBar(fraction: v.total > 0 ? Double(v.total - v.available) / Double(v.total) : 0, color: Theme.mid)
                            .frame(maxWidth: 180).padding(.top, 12)
                        Text(L10n.Monitor.totalOf(Format.storage(v.total))).ui(12).foregroundStyle(Theme.sub).padding(.top, 10)
                    }
                }
            }
            .padding(.horizontal, -20)
            .padding(.top, 34)
            Columns(gap: 44) {
                VStack(alignment: .leading, spacing: 0) {
                    HeadRow(title: L10n.About.hardware)
                    rows(hardware)
                }
            } b: {
                VStack(alignment: .leading, spacing: 0) {
                    HeadRow(title: L10n.About.software)
                    rows(software)
                }
            }
            .padding(.top, 40)
        }
        .task { info = MacInfo.read() }
    }

    /// One figure in the strip under the title, a rule on its left after the first.
    private func cell<Content: View>(_ label: String, first: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SmallLabel(text: label)
            VStack(alignment: .leading, spacing: 0) { content() }.padding(.top, 10)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { if !first { Rectangle().fill(Theme.line).frame(width: 1) } }
        .accessibilityElement(children: .combine)
    }

    /// "3" and "天 4 小时": the biggest unit as the figure, the rest beside it.
    private var uptime: (String, String) {
        let minutes = Int(Date().timeIntervalSince(info.bootTime) / 60)
        let days = minutes / 1440, hours = (minutes % 1440) / 60
        if days > 0 { return ("\(days)", L10n.About.uptimeDaysUnit(hours)) }
        if hours > 0 { return ("\(hours)", L10n.About.uptimeHoursUnit(minutes % 60)) }
        return ("\(max(1, minutes))", L10n.About.uptimeMinutesUnit)
    }

    private var subtitle: String? {
        let parts = [info.inches.map(L10n.About.inches), info.year.map(L10n.About.year)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var hardware: [(String, String)] {
        var out: [(String, String)] = [(L10n.About.chip, info.chip)]
        let cores = info.performanceCores + info.efficiencyCores
        out.append((L10n.Module.cpu, info.efficiencyCores > 0
                    ? L10n.About.cpuCores(cores, info.performanceCores, info.efficiencyCores)
                    : L10n.About.cores(cores)))
        if let gpu = info.gpuCores { out.append((L10n.Module.gpu, L10n.About.cores(gpu))) }
        out.append((L10n.About.memory, "\(Int((Double(info.memory) / 1_073_741_824).rounded())) GB"))
        if let px = info.displayPixels {
            let value = info.displayInches.map { L10n.About.displayValue(String(format: "%.1f", $0), px.0, px.1) }
                ?? L10n.About.resolution(px.0, px.1)
            out.append((L10n.About.display, value))
        }
        out.append((L10n.About.modelID, info.modelID))
        return out
    }

    private var software: [(String, String)] {
        [
            (L10n.About.system, L10n.About.macOS(info.osVersion)),
            (L10n.About.build, info.build),
            (L10n.About.kernel, info.kernel),
            (L10n.About.computerName, info.computerName),
            (L10n.About.booted, Format.weekdayAndTime(info.bootTime)),
            (L10n.About.architecture, info.appleSilicon ? L10n.About.appleSilicon : L10n.About.intel),
        ]
    }

    private func rows(_ items: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            DividedRows {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 12) {
                        Text(item.0).foregroundStyle(Theme.sub).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(item.1).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                    }
                    .ui(14)
                    .frame(height: 58)
                    .accessibilityElement(children: .combine)
                    .textSelection(.enabled)
                }
            }
        }
    }

    private func copy() {
        var lines = [info.modelName]
        if let subtitle { lines.append(subtitle) }
        lines.append("")
        for (label, value) in hardware + software { lines.append(L10n.About.copyLine(label, value)) }
        for v in info.volumes {
            lines.append(L10n.About.copyLine(v.name, L10n.About.volume(Format.storage(v.available), Format.storage(v.total))))
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
