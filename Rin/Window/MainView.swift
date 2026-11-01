import SwiftUI

/// The window: sidebar on the left, the page on the right, both on solid surfaces.
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
        .background(GlassBackground(radius: UIScale.of(18), tint: Theme.windowGlass, material: .underWindowBackground))
        .environment(\.textScale, Fonts.windowTextScale)
        .environment(\.pageGlass, pageGlass)
        .ui(14)
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

    /// The processes table scrolls itself; the overview's tiles share the window's height.
    private var fillsWindow: Bool { page == .processes || page == .overview }

    private var stack: some View {
        content
            .padding(EdgeInsets(top: 0, leading: 20, bottom: Sidebar.bottomInset, trailing: 20))
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
        case .menuBar: MenuBarSettingsPage()
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

    var settings = SettingsStore.shared

    /// Three groups: the whole machine, one page per hardware module, then the tools.
    private let overviewPages: [(Page, String, String)] = [
        (.overview, Icons.overview, L10n.Sidebar.overview),
        (.processes, Icons.processes, L10n.Sidebar.processes),
    ]
    private let toolPages: [(Page, String, String)] = [
        (.sleep, Icons.sleep, L10n.Sidebar.sleep),
        (.alerts, Icons.bell, L10n.Sidebar.alerts),
        (.about, Icons.mac, L10n.Sidebar.aboutMac),
    ]

    /// The hardware modules in the sidebar's order; switched-off ones are left out.
    static let moduleOrder: [Module] = [.cpu, .gpu, .memory, .network, .disk, .battery, .bluetooth, .sensors]

    private var modulePages: [(Page, String, String)] {
        Self.moduleOrder.filter(settings.prefs.isEnabled).map { (.monitor($0), Icons.module($0), $0.title) }
    }

    /// The band at the top that holds the traffic lights and, across the window, each page's title.
    static let titleBand: CGFloat = 52
    /// Below the footer, and below each page's last panel, so their bottoms line up.
    static let bottomInset: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // The traffic lights' band; the first item lines up with the first panel on the right.
            Color.clear.frame(height: Self.titleBand + 8)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(overviewPages, id: \.0) { item($0) }
                Color.clear.frame(height: 10)
                ForEach(modulePages, id: \.0) { entry in
                    item(entry)
                        .contextMenu {
                            if case .monitor(let m) = entry.0 {
                                Button(L10n.Sidebar.turnOffModule(m.title)) { turnOff(m) }
                            }
                        }
                }
                Color.clear.frame(height: 10)
                ForEach(toolPages, id: \.0) { item($0, badge: $0.0 == .alerts ? alerts.unseenCount : 0) }
            }
            // The selected page sits on the same surface as the panels beside it.
            .slidingThumb(navigator.page.sidebarPage) { thumb(hue(navigator.page.sidebarPage)) }
            Spacer(minLength: 12)
            // Her face and the name at the bottom left, beside settings, pause and quit.
            HStack(spacing: 8) {
                MoodMark(size: 22)
                Text(L10n.App.name).ui(16, 600).fixedSize()
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    footerButton(Icons.gear, lineWidth: 1.3, label: L10n.Sidebar.settings, selected: navigator.page == .settings || navigator.page == .menuBar) {
                        navigator.page = .settings
                    }
                    footerButton(monitor.isPaused ? Icons.play : Icons.pause, lineWidth: monitor.isPaused ? 1.5 : 1.8,
                                 label: monitor.isPaused ? L10n.Sidebar.resume : L10n.Sidebar.pause, selected: false) {
                        monitor.togglePause()
                    }
                    footerButton(Icons.power, lineWidth: 1.5, label: L10n.Menu.quit, selected: false) {
                        NSApp.terminate(nil)
                    }
                }
            }
            .frame(height: 30)
            .padding(.leading, 8)
        }
        .padding(EdgeInsets(top: 0, leading: 12, bottom: Self.bottomInset, trailing: 12))
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.windowGlass)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.panelEdge).frame(width: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Sidebar.label)
    }

    /// A module page's color, for its row; nil for the other pages (and battery, Bluetooth).
    private func hue(_ page: Page) -> Color? {
        if case .monitor(let m) = page { return Theme.hue(m) }
        return nil
    }

    @ViewBuilder private func thumb(_ hue: Color?) -> some View {
        if let hue {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hue.opacity(0.16))
        } else {
            PanelBackground(radius: 8)
        }
    }

    private func turnOff(_ m: Module) {
        settings.prefs.setEnabled(m, false)
    }

    /// `badge`: new alerts, a red count on the right.
    private func item(_ entry: (Page, String, String), badge: Int = 0) -> some View {
        let on = navigator.page.sidebarPage == entry.0
        return Button {
            navigator.page = entry.0
        } label: {
            HStack(spacing: 10) {
                LineIcon(d: entry.1, size: 16, lineWidth: 1.5)
                    .foregroundStyle(hue(entry.0) ?? (on ? Theme.text : Theme.sub))
                Text(entry.2).ui(14, on ? 500 : 400)
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
            .frame(height: 30)
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

/// Sidebar footer button: the selection fill when selected, a grey square under the pointer.
private struct FooterButton: View {
    var d: String
    var lineWidth: CGFloat
    var label: String
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            LineIcon(d: d, size: 15, lineWidth: lineWidth)
                .foregroundStyle(selected ? Theme.text : Theme.sub)
                .frame(width: 28, height: 28)
                .background {
                    if selected || hovering { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? Theme.selection : Theme.lgHover) }
                }
                .hoverAnimation(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
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
