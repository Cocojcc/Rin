import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// Binding into one field of the stored preferences.
@MainActor
func pref<T>(_ keyPath: WritableKeyPath<Preferences, T>) -> Binding<T> {
    Binding(get: { SettingsStore.shared.prefs[keyPath: keyPath] },
            set: { SettingsStore.shared.prefs[keyPath: keyPath] = $0 })
}

// MARK: - Settings (the sidebar's gear)

struct SettingsPage: View {
    var settings = SettingsStore.shared
    var updater = UpdateChecker.shared
    var notch = NotchWatcher.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var needsApproval = SMAppService.mainApp.status == .requiresApproval
    @State private var languageChanged = false
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var dragging: Module?
    /// The system-wide spacing lives in the system's preferences, not in Hum's.
    @State private var systemSpacing = MenuBarSpacing.preset

    var body: some View {
        let prefs = settings.prefs
        let g = prefs.general
        let blocked = prefs.menubar.displayMode == .separate ? notch.hidden : []
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: L10n.Sidebar.settings)

            SettingsGroup {
                SettingsRow(title: L10n.Settings.launchAtLogin) {
                    HumSwitch(isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }), label: L10n.Settings.launchAtLogin)
                }
                if needsApproval {
                    SettingsRow(title: L10n.Settings.loginItemNeedsApproval) {
                        WellButton(title: L10n.Settings.openLoginItems) { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
            }

            SettingsGroup(title: L10n.Settings.appearance) {
                SettingsRow(title: L10n.Settings.appearance) {
                    Segmented(label: L10n.Settings.appearance,
                              options: [(AppearanceMode.system, L10n.Settings.followSystem), (.light, L10n.Settings.light), (.dark, L10n.Settings.dark)],
                              selection: Binding(get: { g.appearance }, set: {
                                  settings.prefs.general.appearance = $0
                                  Appearance.apply()
                              }))
                }
                SettingsRow(title: L10n.Settings.accent) {
                    HStack(spacing: 10) {
                        Text(L10n.Settings.palette(g.accent)).ui(12).foregroundStyle(Theme.sub)
                        AccentPicker(selection: pref(\.general.accent))
                    }
                }
                SettingsRow(title: L10n.Settings.temperatureUnit) {
                    Segmented(label: L10n.Settings.temperatureUnit,
                              options: [(TemperatureUnit.celsius, L10n.Settings.celsius), (.fahrenheit, L10n.Settings.fahrenheit)],
                              selection: pref(\.general.temperatureUnit))
                }
                SettingsRow(title: L10n.Settings.language) {
                    HStack(spacing: 10) {
                        if languageChanged {
                            Button(L10n.Settings.restartToApply) { Appearance.relaunch() }
                                .buttonStyle(.plain)
                                .ui(12, 500)
                                .foregroundStyle(Theme.text)
                        }
                        MenuPill(label: L10n.Settings.language,
                                 options: [(LanguageChoice.system, L10n.Settings.followSystem), (.zhHans, L10n.Settings.chinese), (.en, L10n.Settings.english)],
                                 selection: Binding(get: { g.language }, set: {
                                     settings.prefs.general.language = $0
                                     Appearance.applyLanguage($0)
                                     languageChanged = true
                                 }))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(L10n.Settings.menubarGroup).ui(13, 500).foregroundStyle(Theme.sub).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    WellButton(title: L10n.Settings.restoreDefaults, height: 24, radius: 7, horizontalPadding: 10, fontSize: 12) {
                        settings.resetMenubar()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                if !blocked.isEmpty {
                    NotchBanner(count: blocked.count).padding(.bottom, 8)
                }
                VStack(spacing: 0) {
                    MenubarPreview(blocked: blocked, systemSpacing: systemSpacing)
                        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                    Hairline().padding(.horizontal, 14)
                    ModuleChips(blocked: blocked, dragging: $dragging).padding(6)
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
                Color.clear.frame(height: 8)
                SettingsGroup {
                    SettingsRow(title: L10n.Settings.displayMode) {
                        Segmented(label: L10n.Settings.displayMode, options: [(DisplayMode.separate, L10n.Settings.separate), (.combined, L10n.Settings.combined)], selection: pref(\.menubar.displayMode))
                    }
                    SettingsRow(title: L10n.Settings.humSpacing) {
                        GlassStepper(label: L10n.Settings.humSpacing,
                                     value: Binding(get: { MenuBarSpacing.hum(settings.prefs) }, set: { settings.prefs.menubar.humSpacing = $0 }),
                                     range: MenuBarSpacing.humRange, step: MenuBarSpacing.humStep)
                    }
                    SettingsRow(title: L10n.Settings.systemSpacing) {
                        Segmented(label: L10n.Settings.systemSpacing,
                                  options: [(MenuBarSpacing.Preset.standard, L10n.Settings.spacingStandard), (.compact, L10n.Settings.spacingCompact), (.tightest, L10n.Settings.spacingTightest)],
                                  selection: Binding(get: { systemSpacing }, set: { preset in
                                      systemSpacing = preset
                                      MenuBarSpacing.setPreset(preset)
                                      StatusBarController.shared.relayout()
                                  }))
                    }
                    SettingsRow(title: L10n.Settings.barFont) {
                        Segmented(label: L10n.Settings.barFont, options: [(BarTypeface.system, L10n.Settings.fontSystem), (.monospaced, L10n.Settings.fontMonospaced)], selection: pref(\.menubar.typeface))
                    }
                    SettingsRow(title: L10n.Settings.iconColor) {
                        Segmented(label: L10n.Settings.iconColor, options: [(ColorMode.mono, L10n.Common.mono), (.color, L10n.Common.colored)], selection: pref(\.menubar.iconColor))
                    }
                    SettingsRow(title: L10n.Settings.colorOnHighLoad) {
                        HumSwitch(isOn: pref(\.menubar.colorOnHighLoad), label: L10n.Settings.colorOnHighLoad)
                    }
                }
            }

            SettingsGroup(title: L10n.Sidebar.alerts) {
                SettingsRow(title: L10n.Settings.alertsEnabled) {
                    HumSwitch(isOn: pref(\.alerts.enabled), label: L10n.Settings.alertsEnabled)
                }
                if authorization == .denied {
                    SettingsRow(title: L10n.Settings.notificationsOff) {
                        WellButton(title: L10n.Settings.openNotificationSettings) { openNotificationSettings() }
                    }
                }
                SettingsRow(title: L10n.Settings.notificationStyle) {
                    Segmented(label: L10n.Settings.notificationStyle,
                              options: [(NotificationStyle.banner, L10n.Settings.banner), (.alert, L10n.Settings.alertStyle)],
                              selection: Binding(get: { prefs.alerts.style }, set: { style in
                                  guard style != settings.prefs.alerts.style else { return }
                                  settings.prefs.alerts.style = style
                                  // Banner vs. alert is a system setting per app; open the page where it is changed.
                                  openNotificationSettings()
                              }))
                }
                SettingsRow(title: L10n.Settings.playSound) { HumSwitch(isOn: pref(\.alerts.sound), label: L10n.Settings.playSound) }
                SettingsRow(title: L10n.Settings.colorMenubar) { HumSwitch(isOn: pref(\.alerts.colorMenubar), label: L10n.Settings.colorMenubar) }
            }

            SettingsGroup(title: L10n.Settings.performance) {
                SettingsRow(title: L10n.Settings.slowOnBattery) {
                    HumSwitch(isOn: pref(\.general.slowOnBattery), label: L10n.Settings.slowOnBattery)
                }
            }

            SettingsGroup(title: L10n.Sidebar.about) {
                HStack(spacing: 12) {
                    (Text(L10n.App.name).foregroundColor(Theme.sub)
                        + Text(verbatim: " ")
                        + Text(SystemInfo.appVersion).font(Fonts.ui(13, 500)).foregroundColor(Theme.text))
                        .ui(13)
                    Spacer(minLength: 8)
                    WellButton(title: updater.buttonTitle) { updater.check() }
                        .disabled(!updater.isConfigured || updater.state == .checking)
                        .opacity(updater.isConfigured ? 1 : 0.5)
                }
                .frame(minHeight: 42)
                SettingsRow(title: L10n.Settings.autoCheckUpdates) {
                    HumSwitch(isOn: pref(\.general.autoCheckUpdates), label: L10n.Settings.autoCheckUpdates)
                }
            }
        }
        .task { await refreshAuthorization() }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSSound.beep()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        needsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    private func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshAuthorization() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        authorization = s.authorizationStatus
    }
}

/// Swatches in a well; the chosen one sits on a raised tile.
struct AccentPicker: View {
    @Binding var selection: AccentPalette

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AccentPalette.allCases) { p in
                let on = p == selection
                Button {
                    selection = p
                } label: {
                    Circle().fill(p.swatch).frame(width: 11, height: 11)
                        .frame(width: 28, height: 24)
                        .thumbAnchor(on)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Settings.palette(p))
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .slidingThumb(selection) { GlassThumb() }
        .padding(2)
        .background(GlassTrack())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Settings.accent)
    }
}

/// "2 个模块被刘海挡住 [合并成一项]" above the menu bar preview.
struct NotchBanner: View {
    var count: Int
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 10) {
            LineIcon(d: Icons.notch, size: 16, lineWidth: 1.5)
            Text(L10n.Notch.hiddenCount(count)).ui(13, 500).lineLimit(1)
            Spacer(minLength: 8)
            Button {
                SettingsStore.shared.prefs.menubar.displayMode = .combined
            } label: {
                Text(L10n.Notch.merge).ui(12, 500)
                    .foregroundStyle(accent.onAccent)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(accent.accent))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.warn)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.warnBg))
        .accessibilityElement(children: .contain)
    }
}

/// Every module as a chip under the preview: the ones in the menu bar (glass, in their order,
/// a notch mark when hidden behind it) | the rest. Click shows or hides; drag reorders.
struct ModuleChips: View {
    var blocked: [Module]
    @Binding var dragging: Module?
    var settings = SettingsStore.shared

    var body: some View {
        let prefs = settings.prefs
        let shown = prefs.menubar.order.filter { prefs.showsInMenubar($0) }
        let hidden = prefs.menubar.order.filter { !prefs.showsInMenubar($0) }
        // One list, so a chip keeps its identity and slides across when it changes sides.
        let items = shown.map { ChipSlot.module($0) } + (shown.isEmpty || hidden.isEmpty ? [] : [.divider]) + hidden.map { .module($0) }
        FlowLayout(spacing: 4) {
            ForEach(items) { item in
                switch item {
                case .module(let m): chip(m, shown: shown.contains(m))
                case .divider: Rectangle().fill(Theme.cross).frame(width: 1, height: 18).padding(.horizontal, 6).frame(height: 30)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Settings.modulesInMenubar)
    }

    private func chip(_ m: Module, shown: Bool) -> some View {
        let isBlocked = shown && blocked.contains(m)
        return Button {
            withAnimation(Motion.slide) { settings.prefs.setInMenubar(m, !shown) }
        } label: {
            HStack(spacing: 6) {
                LineIcon(d: Icons.module(m), size: 14, lineWidth: 1.5)
                Text(m.title).ui(12).lineLimit(1)
                if isBlocked {
                    LineIcon(d: Icons.notch, size: 12, lineWidth: 1.5).foregroundStyle(Theme.warn)
                }
            }
            .foregroundStyle(shown ? Theme.text : Theme.sub)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background { if shown { GlassThumb() } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(dragging == m ? 0.4 : 1)
        .modifier(ReorderModifier(module: m, dragging: $dragging))
        .accessibilityLabel(isBlocked ? L10n.Settings.blockedChip(m.title) : m.title)
        .accessibilityAddTraits(shown ? [.isSelected] : [])
    }
}

/// Drag to reorder (skipped in offscreen snapshots, where AppKit drag views can't draw).
struct ReorderModifier: ViewModifier {
    let module: Module
    @Binding var dragging: Module?

    func body(content: Content) -> some View {
        if RenderContext.offscreen {
            content
        } else {
            content
                .onDrag {
                    dragging = module
                    return NSItemProvider(object: module.rawValue as NSString)
                }
                .onDrop(of: [UTType.text], delegate: ModuleDropDelegate(target: module, dragging: $dragging))
        }
    }
}

struct ModuleDropDelegate: DropDelegate {
    let target: Module
    @Binding var dragging: Module?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        var order = SettingsStore.shared.prefs.menubar.order
        guard let from = order.firstIndex(of: dragging), let to = order.firstIndex(of: target) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            SettingsStore.shared.prefs.menubar.order = order
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Picked widgets can be dragged into another order; they sit in the menu bar in that order.
private struct WidgetReorder: ViewModifier {
    let module: Module
    let kind: WidgetKind
    var picked: Bool
    @Binding var dragging: WidgetKind?

    func body(content: Content) -> some View {
        if RenderContext.offscreen || !picked {
            content
        } else {
            content
                .onDrag {
                    dragging = kind
                    return NSItemProvider(object: kind.rawValue as NSString)
                }
                .onDrop(of: [UTType.text], delegate: WidgetDropDelegate(module: module, target: kind, dragging: $dragging))
        }
    }
}

private struct WidgetDropDelegate: DropDelegate {
    let module: Module
    let target: WidgetKind
    @Binding var dragging: WidgetKind?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation(Motion.slide) { SettingsStore.shared.prefs.moveWidget(dragging, to: target, for: module) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// The menu bar as it will look with the current settings, at real size, ending with the
/// system's Wi-Fi glyph and clock. Modules behind the notch sit under a black notch block.
struct MenubarPreview: View {
    var blocked: [Module] = []
    /// The system-wide preset, passed in so the preview redraws when it changes.
    var systemSpacing = MenuBarSpacing.preset
    var settings = SettingsStore.shared
    var monitor = Monitor.shared

    var body: some View {
        let prefs = settings.prefs
        let modules = prefs.menubar.order.filter { prefs.showsInMenubar($0) && MenuBarText.available($0, monitor.snapshot) }
        let system = CGFloat(systemSpacing.spacing ?? MenuBarSpacing.systemDefault)
        HStack(spacing: system) {
            Spacer(minLength: 0)
            HStack(spacing: CGFloat(MenuBarSpacing.hum(prefs))) {
                if prefs.menubar.displayMode == .combined {
                    CombinedMenuBarView()
                } else {
                    ForEach(modules.filter { !blocked.contains($0) }) { MenuBarItemView(module: $0) }
                }
            }
            LineIcon(d: Icons.wifi, size: 16, lineWidth: 1.6)
            Text(Format.time(Date())).font(BarFont.value().font)
        }
        .foregroundStyle(Theme.barFg)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(alignment: .leading) {
            if !blocked.isEmpty {
                GeometryReader { geo in
                    UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9, style: .continuous)
                        .fill(Color.black)
                        .frame(width: 110, height: 28)
                        .offset(x: geo.size.width * 0.24)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.bar))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.Settings.previewA11y(modules.map { MenuBarText.accessibility($0, monitor.snapshot, prefs) }.joined(separator: L10n.A11y.separator)))
    }
}

// MARK: - Module settings (from a monitor page's settings button)

/// Title row of a monitor page and of its settings, with the "监视器 | 设置" switch.
struct ModuleHeader<Extra: View>: View {
    let module: Module
    var settingsActive = false
    @ViewBuilder var extra: Extra

    var body: some View {
        HStack(spacing: 20) {
            Text(module.title).ui(20, 600).kerning(-0.2).accessibilityAddTraits(.isHeader)
            extra
            Spacer(minLength: 0)
            ModuleViewToggle(module: module, settingsActive: settingsActive)
        }
        .frame(height: 36)
        .padding(.horizontal, 14)
    }
}

/// Monitor / settings icons for one module on a glass track.
struct ModuleViewToggle: View {
    let module: Module
    var settingsActive: Bool

    var body: some View {
        HStack(spacing: 2) {
            ViewSegment(d: Icons.monitorWindow, label: L10n.Settings.moduleMonitor(module.title), on: !settingsActive) {
                Navigator.shared.page = .monitor(module)
            }
            ViewSegment(d: Icons.general, label: L10n.Settings.moduleSettings(module.title), on: settingsActive) {
                Navigator.shared.page = .moduleSettings(module)
            }
        }
        .padding(2)
        .background(GlassTrack())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Settings.moduleViews(module.title))
    }
}

private struct ViewSegment: View {
    var d: String
    var label: String
    var on: Bool
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.pageGlass) private var pageGlass

    var body: some View {
        Button(action: action) {
            LineIcon(d: d, size: 16, lineWidth: 1.5)
                .foregroundStyle(on || hovering ? Theme.text : Theme.sub)
                .frame(width: 32, height: 24)
                .background {
                    if on {
                        if let pageGlass { GlassThumb().matchedGeometryEffect(id: "viewToggle", in: pageGlass) } else { GlassThumb() }
                    } else if hovering {
                        Capsule().fill(Theme.lgHover)
                    }
                }
                .hoverAnimation(hovering)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

extension ModuleHeader where Extra == EmptyView {
    init(module: Module, settingsActive: Bool = false) {
        self.init(module: module, settingsActive: settingsActive) { EmptyView() }
    }
}

enum ModuleSettingsTab: Int, CaseIterable { case module, widgets, panel, alerts }

struct ModuleSettingsPage: View {
    let module: Module
    @State private var tab: ModuleSettingsTab = ModuleSettingsPage.initialTab

    /// Lets the snapshot tool render each tab.
    static var initialTab: ModuleSettingsTab = .module

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ModuleHeader(module: module, settingsActive: true)
            WidgetStrip(module: module)
            VStack(alignment: .leading, spacing: 12) {
                Segmented(label: L10n.Settings.tabsA11y,
                          options: [(ModuleSettingsTab.module, L10n.Settings.tabModule), (.widgets, L10n.Settings.tabWidgets),
                                    (.panel, L10n.Settings.tabPanel), (.alerts, L10n.Settings.tabAlerts)],
                          selection: $tab, style: .tabs)
                switch tab {
                case .module: ModuleTab(module: module)
                case .widgets: WidgetsTab(module: module)
                case .panel: PanelTab(module: module)
                case .alerts: AlertsTab(module: module)
                }
            }
        }
    }
}

/// "在菜单栏显示" over the module's widgets as they look in the menu bar: picked (glass) |
/// available. Click a widget to toggle it; the widgets fade and lock while the switch is off.
struct WidgetStrip: View {
    let module: Module
    var settings = SettingsStore.shared
    @State private var dragging: WidgetKind?

    var body: some View {
        let prefs = settings.prefs
        let shown = prefs.showsInMenubar(module)
        let on = prefs.widgets(module)
        let off = module.widgetKinds.filter { !on.contains($0) }
        VStack(spacing: 0) {
            SettingsRow(title: L10n.Settings.showInMenubar) {
                HumSwitch(isOn: Binding(get: { settings.prefs.showsInMenubar(module) }, set: { settings.prefs.setInMenubar(module, $0) }),
                          label: L10n.Settings.showInMenubar)
            }
            .padding(.horizontal, 14)
            Hairline().padding(.horizontal, 14)
            // One list, so a chip keeps its identity and slides across when it changes sides.
            FlowLayout(spacing: 4) {
                ForEach(on.map { WidgetSlot.widget($0) } + [.divider] + off.map { .widget($0) }) { item in
                    switch item {
                    case .widget(let kind):
                        WidgetChip(module: module, kind: kind, on: on.contains(kind), prefs: prefs)
                            .opacity(dragging == kind ? 0.4 : 1)
                            .modifier(WidgetReorder(module: module, kind: kind, picked: on.contains(kind), dragging: $dragging))
                    case .divider: Rectangle().fill(Theme.cross).frame(width: 1, height: 22).padding(.horizontal, 6).frame(height: 36)
                    }
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(shown ? 1 : 0.4)
            .allowsHitTesting(shown)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.Settings.widgetStripA11y)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
    }
}

private struct WidgetChip: View {
    let module: Module
    let kind: WidgetKind
    var on: Bool
    var prefs: Preferences
    var settings = SettingsStore.shared
    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(Motion.slide) { settings.prefs.setWidget(kind, !on, for: module) }
        } label: {
            WidgetView(module: module, kind: kind, prefs: prefs)
                .environment(\.widgetUIFont, true)
                .foregroundStyle(on ? Theme.text : Theme.sub)
                .opacity(on ? 1 : 0.6)
                .padding(.horizontal, 8)
                .frame(minWidth: 40)
                .frame(height: 36)
                .background {
                    if on { GlassThumb() } else if hovering { Capsule().fill(Theme.well) }
                }
                .hoverAnimation(hovering)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(L10n.Widget.name(kind, module))
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

private let refreshChoices: [(Double, String)] = [1, 2, 3, 5, 10].map { (Double($0), L10n.Settings.seconds($0)) }

struct ModuleTab: View {
    let module: Module
    var settings = SettingsStore.shared
    var monitor = Monitor.shared

    var body: some View {
        SettingsGroup {
            switch module {
            case .cpu:
                refreshRow(\.cpu.refresh)
                SettingsRow(title: L10n.Settings.processRefresh) { MenuPill(label: L10n.Settings.processRefresh, options: refreshChoices, selection: pref(\.cpu.processRefresh)) }
            case .gpu:
                refreshRow(\.gpu.refresh)
                SettingsRow(title: L10n.Settings.valueType) {
                    Segmented(label: L10n.Settings.valueType, options: [(GPUValueType.utilization, L10n.Panel.utilization), (.memory, L10n.Panel.vram)], selection: pref(\.gpu.valueType))
                }
            case .memory:
                refreshRow(\.memory.refresh)
                SettingsRow(title: L10n.Settings.processRefresh) { MenuPill(label: L10n.Settings.processRefresh, options: refreshChoices, selection: pref(\.memory.processRefresh)) }
                SettingsRow(title: L10n.Settings.valueType) {
                    Segmented(label: L10n.Settings.valueType, options: [(MemoryValueType.percent, L10n.Settings.percent), (.usedGB, L10n.Settings.usedGB)], selection: pref(\.memory.valueType))
                }
            case .network:
                refreshRow(\.network.refresh)
                SettingsRow(title: L10n.Settings.speedUnit) {
                    MenuPill(label: L10n.Settings.speedUnit, options: [(SpeedUnit.auto, L10n.Common.auto), (.bytes, L10n.Settings.unitBytes), (.bits, L10n.Settings.unitBits)], selection: pref(\.network.speedUnit))
                }
            case .disk:
                refreshRow(\.disk.refresh)
                SettingsRow(title: L10n.Settings.whichDisk) {
                    MenuPill(label: L10n.Settings.whichDisk,
                             options: [("", monitor.snapshot.disk.root?.name ?? L10n.Settings.startupDisk)]
                                + monitor.snapshot.disk.volumes.filter { !$0.isRoot }.map { ($0.name, $0.name) },
                             selection: pref(\.disk.volume))
                }
                SettingsRow(title: L10n.Settings.diskContent) {
                    Segmented(label: L10n.Settings.diskContent, options: [(DiskContent.free, L10n.Settings.freeSpace), (.usedPercent, L10n.Settings.usedPercent), (.readWrite, L10n.Settings.readWrite)], selection: pref(\.disk.content))
                }
            case .battery:
                SettingsRow(title: L10n.Settings.refreshInterval) {
                    MenuPill(label: L10n.Settings.refreshInterval, options: [2, 5, 10, 30, 60].map { (Double($0), L10n.Settings.seconds($0)) }, selection: pref(\.battery.refresh))
                }
                SettingsRow(title: L10n.Settings.timeFormat) {
                    Segmented(label: L10n.Settings.timeFormat,
                              options: [(TimeFormat.clock, Format.clockDuration(minutes: 42)), (.minutes, L10n.Battery.minutesShort(42))],
                              selection: pref(\.battery.timeFormat))
                }
            case .sensors:
                refreshRow(\.sensors.refresh)
                SettingsRow(title: L10n.Settings.whichSensor) {
                    MenuPill(label: L10n.Settings.whichSensor, options: SensorChoice.allCases.map { ($0, L10n.Sensors.choice($0)) }, selection: pref(\.sensors.sensor))
                }
            }
        }
    }

    private func refreshRow(_ keyPath: WritableKeyPath<Preferences, Double>) -> some View {
        SettingsRow(title: L10n.Settings.refreshInterval) {
            MenuPill(label: L10n.Settings.refreshInterval, options: refreshChoices, selection: pref(keyPath))
        }
    }
}

struct WidgetsTab: View {
    let module: Module
    var settings = SettingsStore.shared

    var body: some View {
        let prefs = settings.prefs
        let widgets = prefs.widgets(module)
        VStack(alignment: .leading, spacing: 20) {
            if widgets.count > 1 {
                SettingsGroup {
                    SettingsRow(title: L10n.Settings.widgetGap) {
                        GlassStepper(label: L10n.Settings.widgetGap,
                                     value: Binding(get: { settings.prefs.widgetGap(module) }, set: { settings.prefs.setWidgetGap($0, module) }),
                                     range: ModuleWidgets.gapRange)
                    }
                }
            }
            if widgets.isEmpty {
                Text(L10n.Settings.noWidgets).foregroundStyle(Theme.sub)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            }
            ForEach(widgets) { kind in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        WidgetView(module: module, kind: kind, prefs: prefs)
                            .environment(\.widgetUIFont, true)
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 7)
                            .frame(height: 24)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.raised).raisedShadow())
                        Text(L10n.Widget.name(kind, module)).ui(13, 500).foregroundStyle(Theme.sub)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
                    if module == .network && kind == .speed {
                        NetworkSpeedOptions()
                    } else if WidgetOptionsGroup.hasOptions(module, kind) {
                        WidgetOptionsGroup(module: module, kind: kind)
                    }
                }
            }
        }
    }
}

/// The network speed widget's look: a large live preview, then its arrangement, icon and numbers.
struct NetworkSpeedOptions: View {
    var settings = SettingsStore.shared

    private func bind<T>(_ keyPath: WritableKeyPath<WidgetOptions, T>) -> Binding<T> {
        Binding(get: { settings.prefs.options(.network, .speed)[keyPath: keyPath] },
                set: {
                    var o = settings.prefs.options(.network, .speed)
                    o[keyPath: keyPath] = $0
                    settings.prefs.setOptions(o, .network, .speed)
                })
    }

    var body: some View {
        let o = settings.prefs.options(.network, .speed)
        let noGlyph = o.glyph == .none
        VStack(alignment: .leading, spacing: 12) {
            WidgetPreview(module: .network, kind: .speed)
            OptionsSection(title: L10n.Widget.arrangement) {
                SettingsRow(title: L10n.Settings.displayMode) {
                    Segmented(label: L10n.Settings.displayMode, options: [(ValueLayout.twoLine, L10n.Widget.twoLine), (.singleLine, L10n.Widget.singleLine)], selection: bind(\.layout))
                }
                SettingsRow(title: L10n.Widget.order) {
                    Segmented(label: L10n.Widget.order, options: [(true, L10n.Widget.uploadFirst), (false, L10n.Widget.downloadFirst)], selection: bind(\.firstOnTop))
                }
            }
            OptionsSection(title: L10n.Widget.icon) {
                SettingsRow(title: L10n.Widget.iconStyle) {
                    Segmented(label: L10n.Widget.iconStyleA11y,
                              options: [(SpeedGlyph.arrows, L10n.Widget.arrows), (.triangles, L10n.Widget.triangles), (.dots, L10n.Widget.dots),
                                        (.letters, L10n.Widget.letters), (.none, L10n.Common.none)],
                              selection: bind(\.glyph), glyph: { AnyView(GlyphSample(glyph: $0)) }, glyphWidth: 26)
                }
                SettingsRow(title: L10n.Widget.position, dimmed: noGlyph) {
                    Segmented(label: L10n.Widget.positionA11y, options: [(false, L10n.Widget.beforeNumber), (true, L10n.Widget.afterNumber)], selection: bind(\.glyphAfter))
                }
                SettingsRow(title: L10n.Widget.gap, dimmed: noGlyph) {
                    GlassStepper(label: L10n.Widget.gapA11y, value: bind(\.glyphGap), range: 0...8)
                }
                SettingsRow(title: L10n.Settings.color, dimmed: noGlyph) {
                    Segmented(label: L10n.Settings.color, options: [(WidgetColor.mono, L10n.Common.mono), (.colored, L10n.Common.colored)], selection: bind(\.color))
                }
            }
            OptionsSection(title: L10n.Widget.numbers) {
                SettingsRow(title: L10n.Settings.showUnit) { HumSwitch(isOn: bind(\.showUnit), label: L10n.Settings.showUnit) }
                SettingsRow(title: L10n.Widget.unitStyle, dimmed: !o.showUnit) {
                    Segmented(label: L10n.Widget.unitStyle,
                              options: [(RateUnitStyle.perSecond, L10n.Widget.unitPerSecond), (.bytes, L10n.Widget.unitBytes), (.letter, L10n.Widget.unitLetter)],
                              selection: bind(\.unitStyle))
                }
                SettingsRow(title: L10n.Widget.fixedWidth) { HumSwitch(isOn: bind(\.fixedWidth), label: L10n.Widget.fixedWidth) }
                SettingsRow(title: L10n.Widget.align) {
                    Segmented(label: L10n.Widget.align, options: [(WidgetAlign.leading, L10n.Widget.alignLeading), (.trailing, L10n.Widget.alignTrailing)], selection: bind(\.numberAlign))
                }
            }
        }
    }
}

/// A small titled group of option rows (12 pt grey title over a panel).
private struct OptionsSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).ui(12).foregroundStyle(Theme.sub)
                .padding(.horizontal, 14).padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { DividedRows { content } }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        }
    }
}

/// The up / down pair of each speed mark, as drawn on the icon style segments.
private struct GlyphSample: View {
    var glyph: SpeedGlyph

    var body: some View {
        switch glyph {
        case .letters:
            Text(L10n.Widget.uploadLetter + " " + L10n.Widget.downloadLetter).ui(10, 500).kerning(0.4)
        case .none:
            Text(L10n.Common.none).ui(12)
        case .dots:
            HStack(spacing: 3) {
                SpeedMark(glyph: .dots, up: true, size: 6, letterSize: 8)
                SpeedMark(glyph: .dots, up: false, size: 6, letterSize: 8)
            }
        default:
            HStack(spacing: 2) {
                SpeedMark(glyph: glyph, up: true, size: 7, letterSize: 8)
                SpeedMark(glyph: glyph, up: false, size: 7, letterSize: 8)
            }
        }
    }
}

/// One widget at twice the menu bar's size beside Wi-Fi and the clock, as it looks right now.
struct WidgetPreview: View {
    let module: Module
    let kind: WidgetKind
    var settings = SettingsStore.shared
    var monitor = Monitor.shared

    var body: some View {
        let _ = monitor.tick
        let prefs = settings.prefs
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Zoomed(scale: 2) {
                HStack(spacing: 12) {
                    WidgetView(module: module, kind: kind, prefs: prefs)
                        .foregroundStyle(MenuBarText.tone(module, monitor.snapshot, prefs).color ?? Theme.barInk)
                    LineIcon(d: Icons.wifi, size: 16, lineWidth: 1.6)
                    BarText(Format.time(Date()), font: BarFont.value())
                }
                .foregroundStyle(Theme.barFg)
                .environment(\.barTypeface, prefs.menubar.typeface)
                .frame(height: 28)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.bar))
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.Widget.previewA11y(L10n.Widget.name(kind, module)))
    }
}

/// The options of one widget, bound to its stored `WidgetOptions`.
struct WidgetOptionsGroup: View {
    let module: Module
    let kind: WidgetKind
    var settings = SettingsStore.shared

    /// Pieces with nothing to set show only their title.
    static func hasOptions(_ module: Module, _ kind: WidgetKind) -> Bool {
        switch kind {
        case .pair, .iconValue, .labelLine: return false
        case .pie: return module != .cpu
        case .temp: return false
        default: return true
        }
    }

    private func bind<T>(_ keyPath: WritableKeyPath<WidgetOptions, T>) -> Binding<T> {
        Binding(get: { settings.prefs.options(module, kind)[keyPath: keyPath] },
                set: {
                    var o = settings.prefs.options(module, kind)
                    o[keyPath: keyPath] = $0
                    settings.prefs.setOptions(o, module, kind)
                })
    }

    var body: some View {
        SettingsGroup {
            switch kind {
            case .label:
                SettingsRow(title: L10n.Widget.labelText) {
                    TextField(module.widgetLabel, text: bind(\.labelText))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .ui(13)
                        .frame(width: 64)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.well))
                        .accessibilityLabel(L10n.Widget.labelText)
                }
            case .mini:
                toggle(L10n.Widget.label, \.showLabel)
                colorRow()
                alignRow()
            case .line, .labelLine:
                if module == .cpu {
                    SettingsRow(title: L10n.Settings.graphContent) {
                        Segmented(label: L10n.Settings.graphContent, options: [(CPUGraphContent.total, L10n.Settings.totalUsage), (.userSystem, L10n.Settings.userSystem)], selection: bind(\.graphContent))
                    }
                }
                toggle(L10n.Widget.boxed, \.boxed)
                colorRow()
                pointsRow()
            case .bar:
                if module != .memory && module != .disk { toggle(L10n.Widget.boxed, \.boxed) }
                colorRow()
            case .pie, .tacho:
                toggle(L10n.Widget.monochrome, \.monochrome)
            case .icon:
                SettingsRow(title: L10n.Widget.icon) {
                    Segmented(label: L10n.Widget.icon,
                              options: MenuIcons.all(module).indices.map { ($0, L10n.Widget.iconName(module, $0)) }, selection: bind(\.icon), style: .compact,
                              glyph: { i in AnyView(MenuIconView(icon: MenuIcons.icon(module, i), module: module, size: 14).environment(\.widgetUIFont, true)) },
                              glyphWidth: 20)
                }
            case .pill, .dot, .ring:
                colorRow()
            case .inside:
                toggle(L10n.Settings.colorWhenLow, \.colorWhenLow)
            case .time:
                numberWidthRows()
            case .pair, .iconValue:
                EmptyView()
            case .memory:
                colorRow()
                toggle(L10n.Widget.showSymbol, \.showSymbol)
                toggle(L10n.Widget.freeOnTop, \.freeOnTop)
            case .speed:
                layoutRow()
                toggle(L10n.Settings.showUnit, \.showUnit)
                SettingsRow(title: L10n.Settings.order) {
                    Segmented(label: L10n.Settings.order, options: [(true, L10n.Widget.readTop), (false, L10n.Widget.writeTop)], selection: bind(\.firstOnTop))
                }
                SettingsRow(title: L10n.Settings.color) {
                    MenuPill(label: L10n.Settings.color, options: [(WidgetColor.mono, L10n.Common.mono), (.colored, L10n.Common.colored)], selection: bind(\.color),
                             dot: { $0 == .mono ? Theme.text : Theme.palette(.blue) })
                }
            case .chart:
                toggle(L10n.Widget.boxed, \.boxed)
                paletteRow(module == .network ? L10n.Widget.downloadColor : L10n.Widget.readColor, \.firstColor)
                paletteRow(module == .network ? L10n.Widget.uploadColor : L10n.Widget.writeColor, \.secondColor)
                pointsRow()
            case .state:
                paletteRow(L10n.Widget.connected, \.firstColor)
                paletteRow(L10n.Widget.disconnected, \.secondColor)
            case .value, .temp:
                switch module {
                case .sensors:
                    SettingsRow(title: L10n.Settings.color) {
                        Segmented(label: L10n.Settings.color, options: [(WidgetColor.mono, L10n.Common.mono), (.byValue, L10n.Settings.byTemperature)], selection: bind(\.color))
                    }
                case .disk: toggle(L10n.Settings.showUnit, \.showUnit)
                case .battery: toggle(L10n.Widget.hidePercentWhenFull, \.hidePercentWhenFull)
                default: EmptyView()
                }
                numberWidthRows()
            case .battery:
                toggle(L10n.Settings.showBolt, \.showBolt)
                toggle(L10n.Settings.colorWhenLow, \.colorWhenLow)
            case .details:
                SettingsRow(title: L10n.Widget.detailsContent) {
                    MenuPill(label: L10n.Widget.detailsContent,
                             options: [(BatteryDetails.percentAndTime, L10n.Widget.percentAndTime), (.percent, L10n.Widget.percentOnly), (.time, L10n.Widget.timeOnly)],
                             selection: bind(\.details))
                }
            case .fan:
                toggle(L10n.Widget.showIcon, \.showIcon)
                SettingsRow(title: L10n.Widget.fanValue) {
                    Segmented(label: L10n.Widget.fanValue, options: [(FanValue.rpm, L10n.Widget.rpm), (.percent, L10n.Settings.percent)], selection: bind(\.fanValue))
                }
                numberWidthRows()
            case .stack:
                layoutRow()
                toggle(L10n.Widget.monospaced, \.monospaced)
                alignRow()
            }
        }
    }

    /// Fixed width for a single number, and where it sits in that width.
    @ViewBuilder private func numberWidthRows() -> some View {
        toggle(L10n.Widget.fixedWidth, \.numberFixed)
        SettingsRow(title: L10n.Widget.align, dimmed: !settings.prefs.options(module, kind).numberFixed) {
            Segmented(label: L10n.Widget.align, options: [(WidgetAlign.leading, L10n.Widget.alignLeading), (.trailing, L10n.Widget.alignTrailing)], selection: bind(\.numberAlign))
        }
    }

    private func toggle(_ title: String, _ keyPath: WritableKeyPath<WidgetOptions, Bool>) -> some View {
        SettingsRow(title: title) { HumSwitch(isOn: bind(keyPath), label: title) }
    }

    private func colorRow() -> some View {
        SettingsRow(title: L10n.Settings.color) {
            MenuPill(label: L10n.Settings.color,
                     options: [(WidgetColor.mono, L10n.Common.mono), (.colored, L10n.Common.colored), (.byValue, L10n.Widget.byValue(module))],
                     selection: bind(\.color),
                     dot: { c in c == .mono ? Theme.text : c == .colored ? Theme.barColor(module) : Theme.ok })
        }
    }

    private func alignRow() -> some View {
        SettingsRow(title: L10n.Widget.align) {
            Segmented(label: L10n.Widget.align, options: [(WidgetAlign.leading, L10n.Widget.alignLeading), (.center, L10n.Widget.alignCenter), (.trailing, L10n.Widget.alignTrailing)], selection: bind(\.align))
        }
    }

    private func layoutRow() -> some View {
        SettingsRow(title: L10n.Settings.displayMode) {
            Segmented(label: L10n.Settings.displayMode, options: [(ValueLayout.twoLine, L10n.Widget.twoLine), (.singleLine, L10n.Widget.singleLine)], selection: bind(\.layout))
        }
    }

    private func pointsRow() -> some View {
        SettingsRow(title: L10n.Widget.points) {
            MenuPill(label: L10n.Widget.points, options: [30, 60, 90, 120].map { ($0, "\($0)") }, selection: bind(\.points))
        }
    }

    private func paletteRow(_ title: String, _ keyPath: WritableKeyPath<WidgetOptions, PaletteColor>) -> some View {
        SettingsRow(title: title) {
            MenuPill(label: title, options: PaletteColor.allCases.map { ($0, L10n.Widget.palette($0)) }, selection: bind(keyPath),
                     dot: { Theme.palette($0) })
        }
    }
}

struct PanelTab: View {
    let module: Module
    var settings = SettingsStore.shared
    var monitor = Monitor.shared

    private var counts: [(Int, String)] { [3, 4, 5, 6, 8].map { ($0, L10n.Common.count($0)) } }

    var body: some View {
        SettingsGroup {
            switch module {
            case .cpu:
                toggleRow(L10n.Settings.showCores, \.cpu.showCores)
                toggleRow(L10n.Settings.splitCores, \.cpu.splitCoreKinds)
                toggleRow(L10n.Settings.showLoad, \.cpu.showLoad)
                toggleRow(L10n.Settings.showProcesses, \.cpu.showProcesses)
                SettingsRow(title: L10n.Settings.processCount) { MenuPill(label: L10n.Settings.processCount, options: counts, selection: pref(\.cpu.processCount)) }
            case .gpu:
                toggleRow(L10n.Settings.showVRAM, \.gpu.showMemory)
                toggleRow(L10n.Settings.showFrequency, \.gpu.showFrequency)
                toggleRow(L10n.Settings.showTempPower, \.gpu.showTempPower)
                toggleRow(L10n.Settings.showVideo, \.gpu.showVideo)
                toggleRow(L10n.Settings.showProcesses, \.gpu.showProcesses)
                SettingsRow(title: L10n.Settings.processCount) { MenuPill(label: L10n.Settings.processCount, options: counts, selection: pref(\.gpu.processCount)) }
            case .memory:
                toggleRow(L10n.Settings.showComposition, \.memory.showComposition)
                toggleRow(L10n.Settings.showPressure, \.memory.showPressure)
                toggleRow(L10n.Settings.showSwap, \.memory.showSwap)
                toggleRow(L10n.Settings.showProcesses, \.memory.showProcesses)
                SettingsRow(title: L10n.Settings.processCount) { MenuPill(label: L10n.Settings.processCount, options: counts, selection: pref(\.memory.processCount)) }
            case .network:
                toggleRow(L10n.Settings.showLatency, \.network.showLatency)
                toggleRow(L10n.Settings.showProcesses, \.network.showProcesses)
                toggleRow(L10n.Settings.showPublicIP, \.network.showPublicIP)
                SettingsRow(title: L10n.Settings.graphDuration) {
                    MenuPill(label: L10n.Settings.graphDuration, options: [30, 60, 120, 300].map { ($0, L10n.Range.lastSeconds($0)) }, selection: pref(\.network.graphSeconds))
                }
                SettingsRow(title: L10n.Settings.networkInterface) {
                    MenuPill(label: L10n.Settings.networkInterface,
                             options: [("", autoInterfaceLabel)] + monitor.interfaces.map { ($0.name, L10n.Settings.interfaceOption(PanelText.kindName($0.kind), $0.name)) },
                             selection: Binding(get: { settings.prefs.network.interface }, set: {
                                 settings.prefs.network.interface = $0
                                 Monitor.shared.applyConfiguration()
                             }))
                }
            case .disk:
                toggleRow(L10n.Settings.showAllDisks, \.disk.showAllDisks)
                toggleRow(L10n.Settings.showRWGraph, \.disk.showGraph)
                toggleRow(L10n.Settings.showDiskHealth, \.disk.showHealth)
                toggleRow(L10n.Settings.showProcesses, \.disk.showProcesses)
            case .battery:
                toggleRow(L10n.Settings.showHealth, \.battery.showHealth)
                toggleRow(L10n.Settings.showCycles, \.battery.showCycles)
                toggleRow(L10n.Settings.showBatteryTemperature, \.battery.showTemperature)
                toggleRow(L10n.Settings.showChargingPower, \.battery.showPower)
                toggleRow(L10n.Settings.showBluetooth, \.battery.showBluetooth)
            case .sensors:
                toggleRow(L10n.Settings.showThermal, \.sensors.showThermal)
                toggleRow(L10n.Settings.showAllTemps, \.sensors.showAllTemps)
                toggleRow(L10n.Settings.showFans, \.sensors.showFans)
                toggleRow(L10n.Settings.showPower, \.sensors.showPower)
            }
        }
    }

    private var autoInterfaceLabel: String {
        let n = monitor.snapshot.network
        return n.interface.isEmpty ? L10n.Common.auto : L10n.Settings.autoWith(PanelText.kindName(n.kind))
    }

    private func toggleRow(_ title: String, _ keyPath: WritableKeyPath<Preferences, Bool>) -> some View {
        SettingsRow(title: title) { HumSwitch(isOn: pref(keyPath), label: title) }
    }
}

struct AlertsTab: View {
    let module: Module
    var settings = SettingsStore.shared

    var body: some View {
        let unit = settings.prefs.general.temperatureUnit
        SettingsGroup {
            switch module {
            case .cpu:
                rule(\.alerts.cpuOn, label: L10n.Settings.ruleCPUSwitch) {
                    Text(L10n.Settings.ruleCPU)
                    InlineChoice(label: L10n.Settings.ruleCPU, options: [70, 80, 90, 95].map { (Double($0), Format.percent(Double($0) / 100)) }, selection: pref(\.alerts.cpuThreshold))
                    Text(L10n.Settings.ruleFor)
                    InlineChoice(label: L10n.Settings.ruleFor, options: durations, selection: pref(\.alerts.cpuMinutes))
                }
            case .gpu:
                rule(\.alerts.gpuOn, label: L10n.Settings.ruleGPUSwitch) {
                    Text(L10n.Settings.ruleGPU)
                    InlineChoice(label: L10n.Settings.ruleGPU, options: [70, 80, 90, 95].map { (Double($0), Format.percent(Double($0) / 100)) }, selection: pref(\.alerts.gpuThreshold))
                    Text(L10n.Settings.ruleFor)
                    InlineChoice(label: L10n.Settings.ruleFor, options: durations, selection: pref(\.alerts.gpuMinutes))
                }
            case .memory:
                rule(\.alerts.memoryOn, label: L10n.Settings.ruleMemorySwitch) {
                    Text(L10n.Settings.ruleMemory)
                    InlineChoice(label: L10n.Settings.ruleMemory, options: [(MemoryPressure.warning, L10n.Settings.yellow), (.critical, L10n.Settings.red)], selection: pref(\.alerts.memoryLevel))
                }
            case .network:
                rule(\.alerts.networkOn, label: L10n.Settings.ruleNetworkSwitch) { Text(L10n.Settings.ruleNetwork) }
            case .disk:
                rule(\.alerts.diskOn, label: L10n.Settings.ruleDiskSwitch) {
                    Text(L10n.Settings.ruleDisk)
                    InlineChoice(label: L10n.Settings.ruleDisk, options: [5, 10, 20, 50].map { (Double($0), L10n.Settings.gigabytes($0)) }, selection: pref(\.alerts.diskFreeGB))
                }
            case .battery:
                rule(\.alerts.batteryOn, label: L10n.Settings.ruleBatterySwitch) {
                    Text(L10n.Settings.ruleBattery)
                    InlineChoice(label: L10n.Settings.ruleBattery, options: [10, 15, 20, 30].map { (Double($0), Format.percent(Double($0) / 100)) }, selection: pref(\.alerts.batteryPercent))
                }
            case .sensors:
                rule(\.alerts.tempOn, label: L10n.Settings.ruleTempSwitch) {
                    Text(L10n.Settings.ruleTemp)
                    InlineChoice(label: L10n.Settings.ruleTemp, options: [85, 90, 95, 100].map { (Double($0), Format.temperature(Double($0), unit: unit, showUnit: true)) }, selection: pref(\.alerts.tempThreshold))
                }
            }
        }
        .opacity(settings.prefs.alerts.enabled ? 1 : 0.5)
        .disabled(!settings.prefs.alerts.enabled)
    }

    private var durations: [(Double, String)] {
        [(0.5, L10n.Alerts.seconds(30)), (1, L10n.Alerts.minutes(1)), (2, L10n.Alerts.minutes(2)), (5, L10n.Alerts.minutes(5))]
    }

    private func rule<Content: View>(_ keyPath: WritableKeyPath<Preferences, Bool>, label: String, @ViewBuilder sentence: () -> Content) -> some View {
        let on = settings.prefs[keyPath: keyPath]
        return HStack(spacing: 12) {
            HStack(spacing: 4) { sentence() }
                .opacity(on ? 1 : 0.5)
                .padding(.vertical, 7)
            Spacer(minLength: 8)
            HumSwitch(isOn: pref(keyPath), label: label)
        }
        .frame(minHeight: 48)
    }
}

/// A raised value inside a sentence that opens a menu ("高于 [90%]").
struct InlineChoice<Value: Hashable>: View {
    var label: String
    var options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                Button {
                    selection = o.0
                } label: {
                    if o.0 == selection { Label(o.1, systemImage: "checkmark") } else { Text(o.1) }
                }
            }
        } label: {
            Text(options.first { $0.0 == selection }?.1 ?? "")
                .ui(13, 500)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised).raisedShadow())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(label)
    }
}

/// A module chip or the divider between shown and hidden ones.
private enum ChipSlot: Hashable, Identifiable {
    case module(Module), divider
    var id: Self { self }
}

/// A widget chip or the divider between picked and available ones.
private enum WidgetSlot: Hashable, Identifiable {
    case widget(WidgetKind), divider
    var id: Self { self }
}
