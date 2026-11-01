import SwiftUI

/// The window: a title bar across the top (traffic lights, the page's controls on the right), an
/// icon rail on the left, the page on the right; one solid surface, hairlines between them.
struct MainView: View {
    static let minSize = CGSize(width: UIScale.of(760), height: UIScale.of(700))

    var navigator = Navigator.shared
    var settings = SettingsStore.shared
    @Namespace private var pageGlass

    var body: some View {
        VStack(spacing: 0) {
            UIScaled { TitleBar().frame(height: Sidebar.titleBand) }
                .frame(height: UIScale.of(Sidebar.titleBand))
                .layoutPriority(1)
            HStack(spacing: 0) {
                UIScaled { Sidebar().frame(width: Sidebar.width) }
                PageView(page: navigator.page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
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

/// The band across the top: room for the traffic lights on the left, the page's own controls on
/// the right (time range and the monitor / settings switch, or the process search), a rule under it.
struct TitleBar: View {
    var navigator = Navigator.shared

    var body: some View {
        let page = navigator.page
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            switch page {
            case .overview:
                RangeControl(range: Binding(get: { navigator.overviewRange }, set: { navigator.overviewRange = $0 }),
                             options: Navigator.ranges(for: .cpu))
            case .monitor(.bluetooth):
                // The accessories page is a list of devices; nothing on it spans time.
                EmptyView()
            case .monitor(let m):
                if m != .battery || Monitor.shared.snapshot.battery.hasBattery {
                    RangeControl(range: Binding(get: { navigator.range(m) }, set: { navigator.ranges[m] = $0 }), options: Navigator.ranges(for: m))
                }
            case .processes:
                ProcessSearchField(text: Binding(get: { navigator.processQuery }, set: { navigator.processQuery = $0 }))
            default:
                EmptyView()
            }
            // Kept apart from the switch above so it keeps its identity, and its thumb slides,
            // between a module's monitor and its settings.
            if let module = page.module {
                ModuleViewToggle(module: module, settingsActive: page.isModuleSettings)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

private extension Page {
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

    var body: some View {
        HStack(spacing: 8) {
            if RenderContext.offscreen {
                // ImageRenderer can't draw text fields.
                Text(L10n.Processes.search).ui(13).foregroundStyle(Theme.sub).frame(width: 96, alignment: .leading)
            } else {
                TextField(L10n.Processes.search, text: $text, prompt: Text(L10n.Processes.search).foregroundStyle(Theme.sub))
                    .textFieldStyle(.plain)
                    .ui(13)
                    .foregroundStyle(Theme.text)
                    .focused($focused)
                    .frame(width: 96)
            }
            Text(L10n.Processes.searchShortcut).ui(11).foregroundStyle(Theme.sub)
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

    /// The processes table scrolls itself.
    private var fillsWindow: Bool { page == .processes }

    private var stack: some View {
        content
            .environment(\.chartTint, tint)
            .padding(EdgeInsets(top: 28, leading: 32, bottom: Sidebar.bottomInset, trailing: 32))
            .frame(maxWidth: .infinity, maxHeight: fillsWindow ? .infinity : nil, alignment: .topLeading)
    }

    /// A module page's charts (and the process inspector's) take its hue under their lines.
    private var tint: Color? {
        switch page {
        case .monitor(let m): return Theme.chartTint(m, battery: Monitor.shared.snapshot.battery)
        case .processes: return Theme.hue(.cpu)
        default: return nil
        }
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

/// The icon rail: overview and processes, the modules, then sleep, alerts and this Mac; settings
/// at the foot. A module's icon always wears its hue; the current page's icon sits on a square,
/// a module's tinted with its hue, the rest grey.
struct Sidebar: View {
    var navigator = Navigator.shared
    var alerts = Alerts.shared
    var settings = SettingsStore.shared

    static let width: CGFloat = 64
    /// The title bar's height.
    static let titleBand: CGFloat = 52
    /// Under each page's last row.
    static let bottomInset: CGFloat = 20

    /// The hardware modules in the rail's order; switched-off ones are left out.
    static let moduleOrder: [Module] = [.cpu, .gpu, .memory, .network, .disk, .battery, .bluetooth, .sensors]

    var body: some View {
        let modules = Self.moduleOrder.filter(settings.prefs.isEnabled)
        VStack(spacing: 4) {
            item(.overview, Icons.overview, L10n.Sidebar.overview)
            item(.processes, Icons.processes, L10n.Sidebar.processes)
            ForEach(modules, id: \.self) { m in
                item(.monitor(m), Icons.module(m), m.title, hue: Theme.hue(m), tint: Theme.tint(m))
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
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Sidebar.label)
    }

    private func item(_ page: Page, _ d: String, _ title: String, badge: Int = 0, lineWidth: CGFloat = 1.5,
                      hue: Color? = nil, tint: Color? = nil) -> some View {
        let on = navigator.page.sidebarPage == page || (page == .settings && navigator.page == .menuBar)
        return RailButton(d: d, title: title, on: on, badge: badge, lineWidth: lineWidth, hue: hue, tint: tint) { navigator.page = page }
    }
}

/// One rail item: 36 pt square, 10 pt corners, grey behind it when current or under the pointer;
/// new alerts as a red count at its corner.
private struct RailButton: View {
    var d: String
    var title: String
    var on: Bool
    var badge: Int
    var lineWidth: CGFloat
    var hue: Color?
    var tint: Color?
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            LineIcon(d: d, size: 18, lineWidth: lineWidth)
                .foregroundStyle(hue ?? (on ? Theme.text : Theme.sub))
                .frame(width: 36, height: 36)
                .background {
                    if on || hovering { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? tint ?? Theme.selection : Theme.lgHover) }
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
