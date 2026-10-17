#if DEBUG
import AppKit
import SwiftUI

/// `Hum --snapshot <dir>` renders menu bar items, dropdowns and window pages to PNGs (light and
/// dark) and quits. Development aid for checking layouts against the design canvas.
enum Snapshots {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        let only = i + 2 < args.count ? args[i + 2] : nil
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        SettingsStore.persistenceEnabled = false
        RenderContext.offscreen = true
        Monitor.shared.start()
        for m in Module.allCases { Monitor.shared.setVisible(.popover(m), true) }
        Monitor.shared.setVisible(.window(.monitor(.battery)), true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
            render(to: dir, only: only)
            NSApp.terminate(nil)
        }
        return true
    }

    private static func render(to dir: URL, only: String?) {
        for dark in [false, true] {
            let tag = dark ? "dark" : "light"
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            // The canvas's mint wallpaper, so the glass reads as it does in the design.
            let wall = dark ? Color(red: 0.122, green: 0.208, blue: 0.153) : Color(red: 0.804, green: 0.898, blue: 0.808)
            func want(_ name: String) -> Bool { only == nil || name.hasPrefix(only!) }
            if want("menubar") { save(MenubarSheet(dark: dark), appearance, dir.appendingPathComponent("menubar-\(tag).png")) }
            for m in Module.allCases where want("panel") {
                save(PanelRoot(kind: .module(m)).padding(20).background(wall), appearance, dir.appendingPathComponent("panel-\(m.rawValue)-\(tag).png"))
            }
            if want("panel") {
                save(PanelRoot(kind: .combined).padding(20).background(wall), appearance, dir.appendingPathComponent("panel-combined-\(tag).png"))
            }
            if want("onboarding") {
                save(OnboardingView().padding(40).background(wall), appearance, dir.appendingPathComponent("onboarding-\(tag).png"))
            }
            if want("notch") {
                NotchWatcher.shared.debugSetHidden([.cpu, .memory])
                save(NotchAlertView().padding(40).background(wall), appearance, dir.appendingPathComponent("notch-alert-\(tag).png"))
                Navigator.shared.page = .menubar
                save(MainView().frame(width: 860, height: 1000).background(wall), appearance, dir.appendingPathComponent("page-menubar-notch-\(tag).png"))
                NotchWatcher.shared.debugSetHidden([])
            }
            let pages: [(Page, String)] = [
                (.overview, "overview"), (.monitor(.cpu), "cpu"), (.monitor(.gpu), "gpu"), (.monitor(.memory), "memory"),
                (.monitor(.network), "network"), (.monitor(.disk), "disk"), (.monitor(.battery), "battery"), (.monitor(.sensors), "sensors"),
                (.general, "general"), (.menubar, "menubar-settings"), (.menubarModule(.cpu), "menubar-cpu"), (.menubarModule(.network), "menubar-network"),
                (.alerts, "alerts"), (.about, "about"),
            ]
            for (page, name) in pages where want("page") || want("page-\(name)") {
                Navigator.shared.page = page
                save(MainView().frame(width: 860, height: 1000).background(wall), appearance, dir.appendingPathComponent("page-\(name)-\(tag).png"))
            }
        }
    }

    private static func save<V: View>(_ view: V, _ appearance: NSAppearance, _ url: URL) {
        appearance.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: view
                .environment(\.colorScheme, appearance.isDark ? .dark : .light)
                .environment(\.accent, SettingsStore.shared.prefs.general.accent.colors))
            // Draw straight into an 8-bit sRGB context; the default bitmap follows the (HDR) main display.
            var output: Data?
            renderer.render { size, draw in
                let scale: CGFloat = 2
                guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                ctx.scaleBy(x: scale, y: scale)
                draw(ctx)
                if let image = ctx.makeImage() { output = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) }
            }
            guard let png = output else { return }
            try? png.write(to: url)
        }
    }
}

/// `Hum --dump-live <dir>`: runs normally, then writes the real status item buttons and each
/// dropdown window (as AppKit draws them) to PNGs and prints their screen frames.
enum LiveDump {
    static func scheduleIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--dump-live"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { dumpItems(dir) }
    }

    private static func write(_ view: NSView, _ url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func dumpWindow(_ dir: URL) {
        let pages: [(Page, String)] = [(.overview, "overview"), (.monitor(.cpu), "cpu"), (.monitor(.network), "network"),
                                       (.monitor(.battery), "battery"), (.menubar, "menubar"), (.menubarModule(.network), "menubar-network")]
        MainWindowController.shared.show(.overview)
        var queue = pages
        func next() {
            guard !queue.isEmpty else { print("done"); fflush(stdout); return }
            let (page, name) = queue.removeFirst()
            Navigator.shared.page = page
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if let view = NSApp.windows.first(where: { $0.title == L10n.App.name })?.contentView {
                    write(view, dir.appendingPathComponent("live-window-\(name).png"))
                }
                next()
            }
        }
        next()
    }

    private static func dumpItems(_ dir: URL) {
        if let onboarding = NSApp.windows.first(where: { $0.title == L10n.Onboarding.title && $0.isVisible })?.contentView {
            write(onboarding, dir.appendingPathComponent("live-onboarding.png"))
        }
        let buttons = StatusBarController.shared.debugButtons()
        for (name, button) in buttons {
            if let w = button.window { print("item", name, w.frame, "appearance", w.effectiveAppearance.name.rawValue) }
            write(button, dir.appendingPathComponent("item-\(name).png"))
        }
        var queue = buttons
        func next() {
            guard !queue.isEmpty else {
                PanelController.shared.close()
                dumpWindow(dir)
                return
            }
            let (name, button) = queue.removeFirst()
            button.performClick(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let view = PanelController.shared.debugContentView {
                    print("panel", name, view.window?.frame ?? .zero)
                    write(view, dir.appendingPathComponent("live-panel-\(name).png"))
                }
                PanelController.shared.close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { next() }
            }
        }
        next()
    }
}

/// Every module in every style on a light / dark menu bar strip.
private struct MenubarSheet: View {
    var dark: Bool

    var body: some View {
        let base = SettingsStore.shared.prefs
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Module.allCases) { m in
                HStack(spacing: 14) {
                    Text(m.rawValue).font(.system(size: 11)).frame(width: 60, alignment: .leading)
                    ForEach(0..<4, id: \.self) { i in
                        bar(MenuBarItemView(module: m, override: variant(base, m, i)))
                    }
                }
            }
            HStack(spacing: 14) {
                Text("combined").font(.system(size: 11)).frame(width: 60, alignment: .leading)
                bar(CombinedMenuBarView())
            }
        }
        .padding(16)
        .background(dark ? Color(white: 0.1) : Color(white: 0.96))
        .foregroundStyle(dark ? Color.white : Color.black)
    }

    private func bar<V: View>(_ v: V) -> some View {
        v.frame(height: 24)
            .background(dark ? Color(red: 0.165, green: 0.169, blue: 0.188) : Color(red: 0.9, green: 0.9, blue: 0.918))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func variant(_ base: Preferences, _ m: Module, _ i: Int) -> Preferences {
        var p = base
        switch m {
        case .cpu: p.cpu.style = CPUStyle.allCases[i]
        case .gpu: p.gpu.style = GPUStyle.allCases[i]
        case .memory: p.memory.style = MemoryStyle.allCases[i]
        case .network: p.network.style = NetworkStyle.allCases[i]
        case .disk: p.disk.style = DiskStyle.allCases[i]
        case .battery: p.battery.style = BatteryStyle.allCases[i]
        case .sensors: p.sensors.style = SensorsStyle.allCases[i]
        }
        return p
    }
}
#endif
