import AppKit
import SwiftUI

struct RangeControl: View {
    @Binding var range: TimeRange
    var options: [TimeRange] = TimeRange.allCases

    var body: some View {
        Segmented(label: L10n.Range.label, options: options.map { ($0, $0.title) }, selection: $range, style: .range)
            .fixedSize()
    }
}

/// The busiest processes on a page: icon and name, then one or two values, already in order, so the
/// rows carry no bars or rules. Under the pointer a row shows Quit beside the name; right click has the rest.
struct ProcessTable: View {
    var processes: [ProcessUsage]
    var value: (ProcessUsage) -> String
    var valueWidth: CGFloat? = nil
    var secondary: ((ProcessUsage) -> String)? = nil
    var secondaryWidth: CGFloat = 88
    var rowHeight: CGFloat = 32
    var valueSize: CGFloat = 14
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
                    if processes.isEmpty && showsEmpty {
                        Text(L10n.Panel.noProcesses).ui(14).foregroundStyle(Theme.sub)
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
        return HStack(spacing: 12) {
            HStack(spacing: 8) {
                AppIcon(process: p)
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
            HStack(spacing: 0) {
                Reading(text: value(p), size: valueSize).fixedSize()
                    .frame(width: valueWidth, alignment: .trailing)
                // The other direction of the same reading (upload, write), so it looks the same.
                if let secondary {
                    Reading(text: secondary(p), size: valueSize).fixedSize().frame(width: secondaryWidth, alignment: .trailing)
                }
            }
        }
        .ui(14)
        .frame(height: rowHeight)
        .padding(.horizontal, 8)
        .background { if hovered == p.id { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.lgHover) } }
        .padding(.horizontal, -8)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = p.id } else if hovered == p.id { hovered = nil }
        }
        .contextMenu { ProcessContextMenu(process: p) }
        .accessibilityElement(children: .combine)
    }
}

/// A process's own icon: its app's, or the plain one programs share. Read once per path and kept, as
/// lists redraw with every reading.
struct AppIcon: View {
    var image: NSImage
    var plain = false
    var size: CGFloat = 18

    private static var cache: [String: NSImage] = [:]
    private static let program = NSWorkspace.shared.icon(for: .unixExecutable)

    /// An app bundle's icon; anything else is a plain program.
    static func image(bundle path: String?) -> NSImage {
        guard let path else { return program }
        if let known = cache[path] { return known }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[path] = icon
        return icon
    }

    init(process p: ProcessUsage, size: CGFloat = 18) {
        image = Self.image(bundle: p.bundlePath)
        plain = p.bundlePath == nil
        self.size = size
    }

    init(image: NSImage, size: CGFloat = 18) {
        self.image = image
        self.size = size
    }

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .background { if plain { RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.iconLift) } }
            .accessibilityHidden(true)
    }
}
