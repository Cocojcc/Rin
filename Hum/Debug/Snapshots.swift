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
        Monitor.shared.setVisible(.window(.processes), true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
            render(to: dir, only: only)
            NSApp.terminate(nil)
        }
        return true
    }

    /// Window width for page snapshots; `HUM_SNAPSHOT_WIDTH=720` checks the narrowest window.
    private static let pageWidth = UIScale.of(CGFloat(Double(ProcessInfo.processInfo.environment["HUM_SNAPSHOT_WIDTH"] ?? "") ?? 800))

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
                save(OnboardingRoot().padding(40).background(wall), appearance, dir.appendingPathComponent("onboarding-\(tag).png"))
            }
            if want("notch") {
                NotchWatcher.shared.debugSetHidden([.cpu, .memory])
                save(NotchAlertRoot().padding(40).background(wall), appearance, dir.appendingPathComponent("notch-alert-\(tag).png"))
                Navigator.shared.page = .settings
                save(MainView().frame(width: pageWidth, height: UIScale.of(1000)).background(wall), appearance, dir.appendingPathComponent("page-settings-notch-\(tag).png"))
                NotchWatcher.shared.debugSetHidden([])
            }
            let pages: [(Page, String)] = [
                (.overview, "overview"), (.monitor(.cpu), "cpu"), (.monitor(.gpu), "gpu"), (.monitor(.memory), "memory"),
                (.monitor(.network), "network"), (.monitor(.disk), "disk"), (.monitor(.battery), "battery"), (.monitor(.bluetooth), "bluetooth"),
                (.monitor(.sensors), "sensors"),
                (.settings, "settings"), (.sleep, "sleep"), (.about, "about"),
            ] + Module.allCases.map { (.moduleSettings($0), "module-\($0.rawValue)") }
            for (page, name) in pages where want("page") || want("page-\(name)") {
                Navigator.shared.page = page
                save(MainView().frame(width: pageWidth, height: UIScale.of(1400)).background(wall), appearance, dir.appendingPathComponent("page-\(name)-\(tag).png"))
            }
            if want("page") || want("page-processes") {
                Navigator.shared.page = .processes
                ProcessesPage.initialSelection = nil
                save(MainView().frame(width: pageWidth, height: UIScale.of(760)).background(wall), appearance, dir.appendingPathComponent("page-processes-\(tag).png"))
                let busiest = Monitor.shared.snapshot.processes.all.filter { !$0.isSystem && $0.bundlePath != nil }.max { $0.cpu < $1.cpu }
                ProcessesPage.initialSelection = busiest?.id
                save(MainView().frame(width: pageWidth, height: UIScale.of(760)).background(wall), appearance, dir.appendingPathComponent("page-processes-open-\(tag).png"))
                ProcessesPage.initialSelection = nil
            }
            if want("page") || want("page-sleep") {
                KeepAwake.shared.start(.minutes(30))
                Navigator.shared.page = .sleep
                save(MainView().frame(width: pageWidth, height: UIScale.of(1000)).background(wall), appearance, dir.appendingPathComponent("page-sleep-on-\(tag).png"))
                if let out = try? Process.run(URL(fileURLWithPath: "/usr/bin/pmset"), arguments: ["-g", "assertions"]) { out.waitUntilExit() }
                KeepAwake.shared.stop()
            }
            if want("page") || want("page-alerts") {
                seedAlerts()
                Navigator.shared.page = .alerts
                save(MainView().frame(width: pageWidth, height: UIScale.of(1100)).background(wall), appearance, dir.appendingPathComponent("page-alerts-\(tag).png"))
                seedAlerts()
                Navigator.shared.page = .overview
                save(MainView().frame(width: pageWidth, height: UIScale.of(1000)).background(wall), appearance, dir.appendingPathComponent("page-overview-alert-\(tag).png"))
                Alerts.shared.debugSeed([], open: nil)
            }
            for m in Module.allCases where want("tabs") {
                for tab in ModuleSettingsTab.allCases where tab != .module {
                    ModuleSettingsPage.initialTab = tab
                    Navigator.shared.page = .moduleSettings(m)
                    save(MainView().frame(width: pageWidth, height: UIScale.of(2000)).background(wall), appearance,
                         dir.appendingPathComponent("tabs-\(m.rawValue)-\(tab.rawValue)-\(tag).png"))
                }
                ModuleSettingsPage.initialTab = .module
            }
        }
    }

    private static func seedAlerts() {
        let now = Date()
        var cpu = AlertEvent(rule: .cpu, date: now.addingTimeInterval(-300), value: 94, limit: 90, held: 60, culprit: "Xcode", culpritValue: "71%")
        cpu.seen = false
        var bt = AlertEvent(rule: .bluetoothLow, date: now.addingTimeInterval(-4000), value: 0.12, limit: 0.2, subject: "Magic Trackpad", timeLeft: 2 * 86400)
        bt.seen = true
        var disk = AlertEvent(rule: .disk, date: now.addingTimeInterval(-86400), value: 18e9, limit: 20e9, subject: "Macintosh HD", ended: now.addingTimeInterval(-80000), endValue: 182e9)
        disk.seen = true
        var net = AlertEvent(rule: .network, date: now.addingTimeInterval(-100000), value: 0, limit: 0, held: 5, ended: now.addingTimeInterval(-99880), endValue: 1)
        net.seen = true
        Alerts.shared.debugSeed([cpu, bt, disk, net], open: .cpu)
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
                                       (.monitor(.battery), "battery"), (.settings, "settings"), (.moduleSettings(.network), "module-network"),
                                       (.processes, "processes"), (.sleep, "sleep"), (.about, "about")]
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

/// `Hum --check-toggle`: flips one module's visibility and reports whether the other status
/// items survived (same buttons, same windows) instead of being torn down and re-added.
enum ToggleCheck {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--check-toggle") else { return }
        SettingsStore.persistenceEnabled = false
        NotchWatcher.alertsEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            let before = StatusBarController.shared.debugButtons()
            let prefs = SettingsStore.shared.prefs
            let target = Module.allCases.first { !prefs.showsInMenubar($0) } ?? .gpu
            SettingsStore.shared.prefs.setInMenubar(target, !prefs.showsInMenubar(target))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let after = StatusBarController.shared.debugButtons()
                print("toggled", target.rawValue, "before", before.map(\.0), "after", after.map(\.0))
                for (name, button) in before {
                    let kept = after.contains { $0.1 === button && $0.1.window === button.window }
                    print(name, kept ? "kept" : "recreated")
                }
                fflush(stdout)
                exit(0)
            }
        }
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
                    ForEach(m.widgetKinds, id: \.self) { k in
                        bar(WidgetView(module: m, kind: k, prefs: base).padding(.horizontal, 5))
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
}
#endif
