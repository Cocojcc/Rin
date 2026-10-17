import AppKit
import SwiftUI

/// First launch: pick the modules for the menu bar. Switches apply right away, so the menu bar
/// fills in while the window is open; 完成 or the close button finishes it.
final class OnboardingController: NSObject, NSWindowDelegate {
    static let shared = OnboardingController()

    private var window: NSWindow?

    /// Opens once the first sample is in, so rows for hardware this Mac lacks never flash in.
    func showIfNeeded() {
        guard !SettingsStore.shared.prefs.general.onboarded else { return }
        waitForSample(attempts: 20)
    }

    private func waitForSample(attempts: Int) {
        if Monitor.shared.tick > 0 || attempts == 0 {
            show()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.waitForSample(attempts: attempts - 1) }
        }
    }

    func show() {
        if window == nil { makeWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func finish() {
        window?.close()
    }

    private func makeWindow() {
        let host = NSHostingView(rootView: OnboardingView())
        // Measure before the view joins the window: once inside, the title bar's safe area would be
        // added on top of a layout that already draws under it.
        let size = host.fittingSize
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = host
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = L10n.Onboarding.title
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(size)
        window.center()
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        SettingsStore.shared.prefs.general.onboarded = true
        window = nil
    }
}

struct OnboardingView: View {
    var settings = SettingsStore.shared
    var monitor = Monitor.shared

    var body: some View {
        let prefs = settings.prefs
        let modules = Module.allCases.filter { monitor.tick == 0 || MenuBarText.available($0, monitor.snapshot) }
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 12)   // traffic lights
            AppMark(size: 40)
                .padding(.top, 18)
            Text(L10n.Onboarding.title).ui(24, 500).kerning(-0.48)
                .padding(.top, 14)
                .accessibilityAddTraits(.isHeader)
            Text(L10n.Onboarding.subtitle).ui(13).foregroundStyle(Theme.sub)
                .padding(.top, 4)
            VStack(spacing: 0) {
                DividedRows {
                    ForEach(modules) { m in
                        row(m, visible: prefs.isVisible(m))
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            .padding(.top, 18)
            PrimaryButton(title: L10n.Onboarding.done) { OnboardingController.shared.finish() }
                .padding(.top, 18)
        }
        .padding(EdgeInsets(top: 18, leading: 22, bottom: 22, trailing: 22))
        .frame(width: 480)
        .background(GlassBackground(radius: 18, material: .underWindowBackground))
        .environment(\.accent, prefs.general.accent.colors)
        .ui(13)
        .foregroundStyle(Theme.text)
        .ignoresSafeArea()
    }

    private func row(_ m: Module, visible: Bool) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                LineIcon(d: Icons.module(m), size: 16, lineWidth: 1.5).foregroundStyle(Theme.sub)
                    .accessibilityHidden(true)
                Text(m.title)
            }
            Spacer(minLength: 0)
            StyleMini(module: m, style: StylePicker.selectedIndex(m, settings.prefs), large: true)
                .ui(12)
                .padding(.horizontal, 7)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.well))
                .opacity(visible ? 1 : 0.45)
                .accessibilityHidden(true)
            HumSwitch(isOn: Binding(get: { visible }, set: { settings.prefs.setVisible(m, $0) }), label: L10n.Settings.showInMenubarNamed(m.title))
        }
        .frame(minHeight: 40)
    }
}
