import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Picks a character. The menu ends with "导入…", which adds one to the library and picks it.
struct RunnerPicker: View {
    @Binding var selection: String
    var library = RunnerLibrary.shared

    var body: some View {
        let current = library.runner(selection)
        Menu {
            ForEach(library.all) { r in
                Button {
                    selection = r.id
                } label: {
                    if r.id == current.id { Label(library.name(r), systemImage: "checkmark") } else { Text(library.name(r)) }
                }
            }
            Divider()
            Button(L10n.Runner.importEllipsis) {
                if let r = RunnerImport.run() { selection = r.id }
            }
        } label: {
            HStack(spacing: 8) {
                RunnerStill(runner: current).frame(width: (16 * current.aspect).rounded(), height: 16)
                Text(library.name(current)).ui(13)
                LineIcon(d: Icons.upDown, width: 8, height: 12, viewBox: CGSize(width: 8, height: 12), lineWidth: 1.4)
            }
            .foregroundStyle(Theme.text)
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.well))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(L10n.Runner.character)
    }
}

/// The library in settings: each character's first frame and name, imported ones removable
/// from their context menu, and a button to import another.
struct RunnerLibraryRow: View {
    var library = RunnerLibrary.shared
    var settings = SettingsStore.shared

    var body: some View {
        SettingsRow(title: L10n.Runner.library) {
            HStack(spacing: 6) {
                ForEach(library.all) { r in
                    HStack(spacing: 6) {
                        RunnerStill(runner: r).frame(width: (16 * r.aspect).rounded(), height: 16)
                        Text(library.name(r)).ui(12).lineLimit(1)
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.well))
                    .contextMenu {
                        if !r.isBuiltIn {
                            Button(L10n.Runner.delete, role: .destructive) { delete(r) }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                IconButton(d: Icons.plus, size: 26, radius: 8, iconSize: 12, viewBox: 14, lineWidth: 1.5, tint: Theme.sub, label: L10n.Runner.importA11y) {
                    RunnerImport.run()
                }
            }
        }
    }

    /// Modules and the combined icon that played it go back to her.
    private func delete(_ r: Runner) {
        var prefs = settings.prefs
        for m in Module.allCases where prefs.options(m, .runner).runner == r.id {
            var o = prefs.options(m, .runner)
            o.runner = RunnerLibrary.defaultID
            prefs.setOptions(o, m, .runner)
        }
        if prefs.menubar.combinedRunner == r.id { prefs.menubar.combinedRunner = RunnerLibrary.defaultID }
        settings.prefs = prefs
        library.delete(r.id)
    }
}

enum RunnerImport {
    /// Asks for a folder of frames, a GIF or a PNG strip and imports it; nil when cancelled or
    /// when it couldn't be read (after saying why).
    @discardableResult
    static func run() -> Runner? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .gif, .jpeg, .folder]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            return try RunnerLibrary.shared.importRunner(from: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.Runner.importFailed
            alert.informativeText = (error as? RunnerLibrary.ImportError)?.message ?? L10n.Runner.unreadable
            alert.runModal()
            return nil
        }
    }
}
