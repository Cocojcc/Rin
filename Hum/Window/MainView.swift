import SwiftUI

/// Glass window: translucent sidebar on the left, the page on the right.
struct MainView: View {
    /// Two overview columns side by side; three rows of overview cards top to bottom.
    static let minSize = CGSize(width: UIScale.of(720), height: UIScale.of(700))

    var navigator = Navigator.shared
    var settings = SettingsStore.shared
    @Namespace private var pageGlass

    var body: some View {
        HStack(spacing: 0) {
            UIScaled { Sidebar().frame(width: 184) }
            PageView(page: navigator.page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The hosting controller sets the window's minimum from this, overriding contentMinSize.
        .frame(minWidth: MainView.minSize.width, minHeight: MainView.minSize.height)
        .background(GlassBackground(radius: UIScale.of(18), material: .underWindowBackground))
        .environment(\.accent, settings.prefs.general.accent.colors)
        .environment(\.pageGlass, pageGlass)
        .ui(13)
        .foregroundStyle(Theme.text)
        .focusEffectDisabled()
        .ignoresSafeArea()
    }
}

struct PageView: View {
    let page: Page

    var body: some View {
        if RenderContext.offscreen {
            // ImageRenderer can't draw scroll views.
            UIScaled { stack }.frame(maxHeight: .infinity, alignment: .top)
        } else {
            // The scroll view itself stays unscaled; only the page inside it is drawn at UI scale.
            // Pages cross-fade, stacked so the outgoing one keeps its place.
            ZStack {
                Group {
                    if fillsWindow {
                        // The page scrolls its own table, so its header stays put.
                        UIScaled { stack }
                    } else {
                        ScrollView { UIScaled { stack } }
                            .scrollIndicators(.automatic)
                    }
                }
                .id(page)
                .transition(.opacity)
            }
            .animation(Motion.page, value: page)
        }
    }

    private var fillsWindow: Bool { page == .processes }

    private var stack: some View {
        content
            .padding(EdgeInsets(top: 46, leading: 24, bottom: 24, trailing: 24))
            .frame(maxWidth: .infinity, maxHeight: fillsWindow ? .infinity : nil, alignment: .topLeading)
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .overview: OverviewPage()
        case .monitor(let m):
            switch m {
            case .cpu: CPUPage()
            case .gpu: GPUPage()
            case .memory: MemoryPage()
            case .network: NetworkPage()
            case .disk: DiskPage()
            case .battery: BatteryPage()
            case .bluetooth: BluetoothPage()
            case .sensors: SensorsPage()
            }
        case .moduleSettings(let m): ModuleSettingsPage(module: m)
        case .settings: SettingsPage()
        case .processes: ProcessesPage()
        case .sleep: SleepPage()
        case .alerts: AlertsPage()
        case .about: AboutPage()
        }
    }
}

struct Sidebar: View {
    var navigator = Navigator.shared
    var monitor = Monitor.shared
    var alerts = Alerts.shared

    private let overviewPage: (Page, String, String) = (.overview, Icons.overview, L10n.Sidebar.overview)
    private let pages: [(Page, String, String)] = [
        (.processes, Icons.processes, L10n.Sidebar.processes),
        (.monitor(.cpu), Icons.cpu, L10n.Module.cpu),
        (.monitor(.gpu), Icons.gpu, L10n.Module.gpu),
        (.monitor(.memory), Icons.memory, L10n.Module.memory),
        (.monitor(.network), Icons.network, L10n.Module.network),
        (.monitor(.disk), Icons.disk, L10n.Module.disk),
        (.monitor(.battery), Icons.battery, L10n.Module.battery),
        (.sleep, Icons.sleep, L10n.Sidebar.sleep),
        (.monitor(.bluetooth), Icons.bluetooth, L10n.Module.bluetooth),
        (.monitor(.sensors), Icons.sensors, L10n.Module.sensors),
    ]
    private let alertsPage: (Page, String, String) = (.alerts, Icons.bell, L10n.Sidebar.alerts)
    private let aboutPage: (Page, String, String) = (.about, Icons.mac, L10n.Sidebar.aboutMac)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Color.clear.frame(height: 32)   // traffic lights
            HStack(spacing: 10) {
                AppMark(size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.App.name).ui(20, 600).kerning(-0.2)
                    Text(L10n.App.version(SystemInfo.appVersion)).ui(12).foregroundStyle(Theme.sub)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 2) {
                // The overview, the monitors, then Alerts and About This Mac sit in three groups.
                item(overviewPage).padding(.bottom, 12)
                ForEach(pages, id: \.0) { item($0) }
                item(alertsPage, badge: alerts.unseenCount).padding(.top, 12)
                item(aboutPage)
            }
            .slidingThumb(navigator.page.sidebarPage) { GlassThumb() }
            Spacer(minLength: 12)
            HStack {
                footerButton(Icons.gear, lineWidth: 1.3, label: L10n.Sidebar.settings, selected: navigator.page == .settings) {
                    navigator.page = .settings
                }
                Spacer(minLength: 0)
                footerButton(monitor.isPaused ? Icons.play : Icons.pause, lineWidth: monitor.isPaused ? 1.5 : 1.8,
                             label: monitor.isPaused ? L10n.Sidebar.resume : L10n.Sidebar.pause, selected: false) {
                    monitor.togglePause()
                }
                Spacer(minLength: 0)
                footerButton(Icons.power, lineWidth: 1.5, label: L10n.Menu.quit, selected: false) {
                    NSApp.terminate(nil)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(EdgeInsets(top: 0, leading: 12, bottom: 16, trailing: 12))
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.side)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Sidebar.label)
    }

    /// `badge`: new alerts, a red count on the right.
    private func item(_ entry: (Page, String, String), badge: Int = 0) -> some View {
        let on = navigator.page.sidebarPage == entry.0
        return Button {
            navigator.page = entry.0
        } label: {
            HStack(spacing: 10) {
                LineIcon(d: entry.1, size: 15, lineWidth: 1.5)
                Text(entry.2).ui(13, on ? 500 : 400)
                Spacer(minLength: 0)
                if badge > 0 {
                    Text("\(badge)").ui(12, 500).foregroundStyle(Theme.onDanger)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(Theme.danger))
                        .accessibilityLabel(L10n.Alerts.badgeA11y(badge))
                }
            }
            .foregroundStyle(on ? Theme.text : Theme.sub)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .thumbAnchor(on)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func footerButton(_ d: String, lineWidth: CGFloat, label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        FooterButton(d: d, lineWidth: lineWidth, label: label, selected: selected, action: action)
    }
}

/// Round sidebar footer button: glass when selected, a grey disc under the pointer.
private struct FooterButton: View {
    var d: String
    var lineWidth: CGFloat
    var label: String
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            LineIcon(d: d, size: 16, lineWidth: lineWidth)
                .foregroundStyle(selected ? Theme.text : Theme.sub)
                .frame(width: 32, height: 32)
                .background {
                    if selected { GlassThumb() } else if hovering { Circle().fill(Theme.well) }
                }
                .hoverAnimation(hovering)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// The app mark: three bars on an ink tile.
struct AppMark: View {
    var size: CGFloat

    var body: some View {
        LineIcon(d: Icons.appMark, size: size * 0.54, viewBox: 24, lineWidth: 2.6)
            .foregroundStyle(Theme.onInk)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Theme.ink))
            .accessibilityHidden(true)
    }
}

/// Shared by every page, so the glass thumb of a module's monitor / settings toggle can slide
/// across while one page fades into the other.
private struct PageGlassKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var pageGlass: Namespace.ID? {
        get { self[PageGlassKey.self] }
        set { self[PageGlassKey.self] = newValue }
    }
}
