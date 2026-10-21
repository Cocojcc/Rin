import AppKit
import SwiftUI

/// About This Mac: the model with its drawing, hardware and software facts, and volumes.
struct AboutPage: View {
    @State private var info = MacInfo.read()
    @State private var wallpaper: NSImage?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: L10n.Sidebar.aboutMac) {
                WellButton(title: copied ? L10n.About.copied : L10n.About.copy, height: 28, radius: 8, fontSize: 12) { copy() }
                    .help(L10n.About.copyA11y)
                    .accessibilityLabel(L10n.About.copyA11y)
            }
            hero
            CardGrid(minWidth: 240, spacing: 12, minHeight: 0, columns: 2, minColumns: 1) {
                Section(title: L10n.About.hardware) { rows(hardware) }
                Section(title: L10n.About.software) { rows(software) }
            }
            if !info.volumes.isEmpty {
                Section(title: L10n.About.storage) {
                    rows(info.volumes.map { ($0.name, L10n.About.volume(Format.storage($0.available), Format.storage($0.total))) })
                }
            }
        }
        .task {
            info = MacInfo.read()
            wallpaper = await Task.detached(priority: .utility) { MacInfo.wallpaperThumbnail() }.value
        }
    }

    private var hero: some View {
        HStack(spacing: 24) {
            LaptopDrawing(wallpaper: wallpaper).frame(width: 132, height: 84)
            VStack(alignment: .leading, spacing: 0) {
                Text(info.modelName).ui(20, 600).kerning(-0.2).frame(height: 26)
                if let subtitle { Text(subtitle).ui(13).foregroundStyle(Theme.sub) }
                HStack(spacing: 6) {
                    chip(L10n.About.macOS(info.osVersion))
                    chip(Format.uptime(since: info.bootTime))
                }
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .padding(EdgeInsets(top: 18, leading: 14, bottom: 18, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
    }

    private var subtitle: String? {
        let parts = [info.inches.map(L10n.About.inches), info.year.map(L10n.About.year)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func chip(_ text: String) -> some View {
        Text(text).ui(12).lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(Theme.well))
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
                    .ui(13)
                    .frame(minHeight: 34)
                    .accessibilityElement(children: .combine)
                    .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
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

/// A laptop: ink lid with the desktop picture (or a plain wall) on the screen, notch, faint base.
private struct LaptopDrawing: View {
    var wallpaper: NSImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.ink)
                .frame(width: 108, height: 70).offset(x: 12, y: 2)
            screen.frame(width: 100, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                .offset(x: 16, y: 6)
            Capsule().fill(Theme.ink).frame(width: 16, height: 4).offset(x: 58, y: 6)
            BaseShape().fill(Theme.faint).frame(width: 132, height: 84)
            Capsule().fill(Theme.ink.opacity(0.35)).frame(width: 20, height: 2.5).offset(x: 56, y: 74)
        }
        .frame(width: 132, height: 84, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var screen: some View {
        if let wallpaper {
            Image(nsImage: wallpaper).resizable().aspectRatio(contentMode: .fill)
        } else {
            Theme.wall
        }
    }

    /// "M2 74h128l-3.5 6.5a3 3 0 0 1-2.6 1.5H8.1a3 3 0 0 1-2.6-1.5z" in a 132 × 84 box.
    private struct BaseShape: Shape {
        func path(in rect: CGRect) -> Path {
            Path(SVGPath.path("M2 74h128l-3.5 6.5a3 3 0 0 1-2.6 1.5H8.1a3 3 0 0 1-2.6-1.5z"))
                .applying(CGAffineTransform(scaleX: rect.width / 132, y: rect.height / 84))
        }
    }
}
