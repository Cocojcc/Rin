import SwiftUI

/// The window: a sidebar running its full height, one bar across the top (the traffic lights over
/// the sidebar, the page's name, what the page controls), the page under it.
struct MainView: View {
    static let minSize = CGSize(width: UIScale.of(760), height: UIScale.of(700))

    var navigator = Navigator.shared
    var settings = SettingsStore.shared
    @Namespace private var pageGlass

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                UIScaled { Sidebar().frame(width: Sidebar.width) }
                PageView(page: navigator.page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .padding(.top, UIScale.of(Sidebar.titleBand))
            }
            UIScaled { TitleBar().frame(height: Sidebar.titleBand) }
                .frame(height: UIScale.of(Sidebar.titleBand))
        }
        // The hosting controller sets the window's minimum from this, overriding contentMinSize.
        .frame(minWidth: MainView.minSize.width, minHeight: MainView.minSize.height)
        // The sidebar and the curves run up to the window's edge, so its corners cut them too.
        .clipShape(RoundedRectangle(cornerRadius: UIScale.of(18), style: .continuous))
        .background(GlassBackground(radius: UIScale.of(18), tint: Theme.windowGlass, material: .underWindowBackground))
        .environment(\.textScale, Fonts.windowTextScale)
        .environment(\.pageGlass, pageGlass)
        .ui(14)
        .foregroundStyle(Theme.text)
        .focusEffectDisabled()
        .ignoresSafeArea()
    }
}

/// The bar across the top: the page's name, what it says about itself beside that, then what it
/// controls on the right (the time range and the monitor / settings switch, or the process search).
struct TitleBar: View {
    var navigator = Navigator.shared
    var monitor = Monitor.shared
    var alerts = Alerts.shared

    var body: some View {
        let page = navigator.page
        HStack(spacing: 0) {
            Text(page.title).ui(15, 600).lineLimit(1).fixedSize().accessibilityAddTraits(.isHeader)
            // In a stack, so a page with nothing to say still leaves the room between its name and its controls.
            HStack(spacing: 0) {
                status(page)
                Spacer(minLength: 0)
            }
            .ui(13)
            .lineLimit(1)
            .padding(.leading, 14)
            HStack(spacing: 10) {
                switch page {
                case .monitor(.bluetooth):
                    // The accessories page is a list of devices; nothing on it spans time.
                    EmptyView()
                case .monitor(let m):
                    if m != .battery || monitor.snapshot.battery.hasBattery {
                        RangeControl(range: Binding(get: { navigator.range(m) }, set: { navigator.ranges[m] = $0 }), options: Navigator.ranges(for: m))
                    }
                case .processes:
                    Segmented(label: L10n.Processes.tabsLabel, options: ProcessTab.allCases.map { ($0, $0.title) },
                              selection: Binding(get: { navigator.processTab }, set: { navigator.processTab = $0 }), style: .range)
                        .fixedSize()
                    ProcessSearchField(text: Binding(get: { navigator.processQuery }, set: { navigator.processQuery = $0 }))
                case .about:
                    AboutCopyButton()
                default:
                    EmptyView()
                }
                // Kept apart from the switch above so it keeps its identity, and its thumb slides,
                // between a module's monitor and its settings.
                if let module = page.module {
                    ModuleViewToggle(module: module, settingsActive: page.isModuleSettings)
                }
            }
        }
        .padding(.leading, Sidebar.width + PageView.margin)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// What a page says about itself, only when there is something to say.
    @ViewBuilder private func status(_ page: Page) -> some View {
        switch page {
        case .overview:
            if let event = alerts.current {
                Button { alerts.show(event) } label: { Attention(text: AlertText.headline(event)).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .help(L10n.Alerts.view)
            }
        case .processes:
            let s = monitor.processes
            // The counts give way to the tabs and the search where the bar runs short.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    KeyValue(label: L10n.Monitor.totalLabel, value: grouped(s.processCount), size: 13)
                    KeyValue(label: L10n.Monitor.threadsLabel, value: grouped(s.threadCount), size: 13)
                }
                Color.clear.frame(width: 0, height: 0)
            }
        case .monitor(.sensors):
            let level = monitor.snapshot.sensors.thermal
            // The steps say what they are; the words go first where the bar runs short.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Text(L10n.Sensors.thermalState).foregroundStyle(Theme.sub).fixedSize()
                    ThermalSteps(level: level)
                }
                ThermalSteps(level: level)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 16)
        default:
            EmptyView()
        }
    }
}

private extension Page {
    var title: String {
        switch self {
        case .overview: return L10n.Overview.title
        case .monitor(let m), .moduleSettings(let m): return m.title
        case .settings: return L10n.Sidebar.settings
        case .menuBar: return L10n.Settings.menubarGroup
        case .processes: return L10n.Sidebar.processes
        case .sleep: return L10n.Sidebar.sleep
        case .alerts: return L10n.Sidebar.alerts
        case .about: return L10n.Sidebar.aboutMac
        }
    }

    var module: Module? {
        switch self {
        case .monitor(let m), .moduleSettings(let m): return m
        default: return nil
        }
    }

    var isModuleSettings: Bool {
        if case .moduleSettings = self { return true }
        return false
    }
}

/// "搜索进程 ⌘K" in the title bar: a grey field, the shortcut in a chip; ⌘K focuses it.
struct ProcessSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    /// As wide as its prompt, so the tabs beside it keep their room in either language.
    private static let width = (L10n.Processes.search as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width.rounded(.up) + 22

    var body: some View {
        HStack(spacing: 8) {
            if RenderContext.offscreen {
                // ImageRenderer can't draw text fields.
                Text(L10n.Processes.search).ui(13).foregroundStyle(Theme.sub).lineLimit(1).frame(width: Self.width, alignment: .leading)
            } else {
                TextField(L10n.Processes.search, text: $text, prompt: Text(L10n.Processes.search).foregroundStyle(Theme.sub))
                    .textFieldStyle(.plain)
                    .ui(13)
                    .foregroundStyle(Theme.text)
                    .focused($focused)
                    .frame(width: Self.width)
            }
            Text(L10n.Processes.searchShortcut).ui(11).foregroundStyle(Theme.sub).fixedSize()
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.chip))
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(GlassTrack())
        .background {
            Button("") { focused = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }
}

struct PageView: View {
    let page: Page

    /// A page's text stays this far from the sidebar and the window's edge.
    static let margin: CGFloat = 32
    /// What the design's window has under its bar; anything more goes to the page's main curve.
    private static let designHeight: CGFloat = 700 - Sidebar.titleBand

    var body: some View {
        GeometryReader { geo in
            let extra = max(0, geo.size.height / UIScale.factor - Self.designHeight)
            Group {
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
            .environment(\.pageExtra, extra)
        }
    }

    /// The processes table scrolls itself.
    private var fillsWindow: Bool { page == .processes }

    private var stack: some View {
        content
            .padding(EdgeInsets(top: 6, leading: Self.margin, bottom: Sidebar.bottomInset, trailing: Self.margin))
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

/// The sidebar: overview and processes, the modules, then sleep, alerts and this Mac; settings at
/// the foot. A module's icon always wears its hue; the current page is a solid tile, a module's in
/// its hue, the rest in the text color. The overview's is a pale one, as the page around it is all hairlines.
struct Sidebar: View {
    var navigator = Navigator.shared
    var alerts = Alerts.shared
    var settings = SettingsStore.shared

    /// As wide as the window's buttons need, with their gap on the far side too: they aren't drawn
    /// at the interface's scale, and the middle one sits right over the icons.
    static let width: CGFloat = 92
    /// A button is as wide as the three window buttons above it, so the column lines up from the
    /// top of the window down, and as tall as fourteen of them can be in the shortest window.
    static let itemWidth: CGFloat = width - 2 * 9 / 0.85
    static let itemHeight: CGFloat = 40
    /// The bar across the top; the sidebar's icons start below it.
    static let titleBand: CGFloat = 52
    /// Under each page's last row.
    static let bottomInset: CGFloat = 20

    /// The hardware modules in the sidebar's order; switched-off ones are left out.
    static let moduleOrder: [Module] = [.cpu, .memory, .network, .disk, .gpu, .sensors, .battery, .bluetooth]

    var body: some View {
        let modules = Self.moduleOrder.filter(settings.prefs.isEnabled)
        VStack(spacing: 3) {
            item(.overview, Icons.overview, L10n.Sidebar.overview)
            item(.processes, Icons.processes, L10n.Sidebar.processes)
            ForEach(modules, id: \.self) { m in
                item(.monitor(m), Icons.module(m), m.title, hue: Theme.hue(m))
                    .padding(.top, m == modules.first ? 10 : 0)
                    .contextMenu {
                        Button(L10n.Sidebar.turnOffModule(m.title)) { settings.prefs.setEnabled(m, false) }
                    }
            }
            item(.sleep, Icons.sleep, L10n.Sidebar.sleep).padding(.top, 10)
            item(.alerts, Icons.bell, L10n.Sidebar.alerts, badge: alerts.unseenCount)
            item(.about, Icons.mac, L10n.Sidebar.aboutMac)
            Spacer(minLength: 10)
            item(.settings, Icons.gear, L10n.Sidebar.settings, lineWidth: 1.3)
        }
        .slidingThumb(navigator.page.sidebarPage == .menuBar ? .settings : navigator.page.sidebarPage) {
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.raise)
        }
        .padding(.top, Self.titleBand)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.rail)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Sidebar.label)
    }

    private func item(_ page: Page, _ d: String, _ title: String, badge: Int = 0, lineWidth: CGFloat = 1.5, hue: Color? = nil) -> some View {
        let on = navigator.page.sidebarPage == page || (page == .settings && navigator.page == .menuBar)
        return RailButton(d: d, title: title, on: on, badge: badge, lineWidth: lineWidth, hue: hue) { navigator.page = page }
    }
}

/// One sidebar item: grey under the pointer, under the group's sliding tile when current; new
/// alerts as a red count at its corner.
private struct RailButton: View {
    var d: String
    var title: String
    var on: Bool
    var badge: Int
    var lineWidth: CGFloat
    var hue: Color?
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            LineIcon(d: d, size: 20, lineWidth: lineWidth)
                .foregroundStyle(hue ?? (on ? Theme.text : Theme.sub))
                .frame(width: Sidebar.itemWidth, height: Sidebar.itemHeight)
                .thumbAnchor(on)
                .background {
                    if hovering && !on {
                        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.lgHover)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)").ui(10, 600).foregroundStyle(Theme.onDanger)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(Capsule().fill(Theme.danger))
                            .offset(x: 3, y: -2)
                            .accessibilityLabel(L10n.Alerts.badgeA11y(badge))
                    }
                }
                .hoverAnimation(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// Shared by every page, so the thumb of a module's monitor / settings switch can slide across
/// while one page fades into the other.
private struct PageGlassKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var pageGlass: Namespace.ID? {
        get { self[PageGlassKey.self] }
        set { self[PageGlassKey.self] = newValue }
    }
}
