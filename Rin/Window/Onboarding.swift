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
        let host = NSHostingView(rootView: OnboardingRoot())
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

/// The onboarding window's content at UI scale, on glass.
struct OnboardingRoot: View {
    var body: some View {
        UIScaled { OnboardingView() }
            .background(GlassBackground(radius: UIScale.of(18), tint: Theme.windowGlass, material: .underWindowBackground))
            .ignoresSafeArea()
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
            AppMark(size: 56)
                .padding(.top, 18)
            HStack(spacing: 10) {
                Text(L10n.Onboarding.greeting).ui(24, 500).kerning(-0.48)
                    .accessibilityAddTraits(.isHeader)
                Seal(size: 22)
            }
            .padding(.top, 16)
            Text(L10n.Onboarding.intro).ui(13).foregroundStyle(Theme.sub)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            VStack(spacing: 0) {
                DividedRows {
                    ForEach(modules) { m in
                        row(m, visible: prefs.showsInMenubar(m))
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
        .ui(13)
        .foregroundStyle(Theme.text)
        .focusEffectDisabled()
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
            HStack(spacing: 4) {
                ForEach(settings.prefs.widgets(m).isEmpty ? m.primaryWidgets : settings.prefs.widgets(m)) {
                    WidgetView(module: m, kind: $0, prefs: settings.prefs)
                }
            }
                .environment(\.widgetUIFont, true)
                .padding(.horizontal, 7)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.well))
                .opacity(visible ? 1 : 0.45)
                .accessibilityHidden(true)
            RinSwitch(isOn: Binding(get: { visible }, set: { settings.prefs.setInMenubar(m, $0) }), label: L10n.Settings.showInMenubarNamed(m.title))
        }
        .frame(minHeight: 40)
    }
}
