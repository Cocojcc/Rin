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
                MenubarPreview(blocked: blocked)
                    .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
                Color.clear.frame(height: 8)
                SettingsGroup {
                    SettingsRow(title: L10n.Settings.displayMode) {
                        Segmented(label: L10n.Settings.displayMode, options: [(DisplayMode.separate, L10n.Settings.separate), (.combined, L10n.Settings.combined)], selection: pref(\.menubar.displayMode))
                    }
                    SettingsRow(title: L10n.Settings.iconColor) {
                        Segmented(label: L10n.Settings.iconColor, options: [(ColorMode.mono, L10n.Common.mono), (.color, L10n.Common.colored)], selection: pref(\.menubar.iconColor))
                    }
                    SettingsRow(title: L10n.Settings.colorOnHighLoad) {
                        HumSwitch(isOn: pref(\.menubar.colorOnHighLoad), label: L10n.Settings.colorOnHighLoad)
                    }
                    SettingsRow(title: L10n.Settings.moduleOrder) {
                        OrderChips(blocked: blocked, dragging: $dragging)
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
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? Theme.raised : .clear).raisedShadow(on))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Settings.palette(p))
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.well))
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

/// Visible modules as draggable chips, in menu bar order. Ones behind the notch are tinted.
struct OrderChips: View {
    var blocked: [Module]
    @Binding var dragging: Module?
    var settings = SettingsStore.shared

    var body: some View {
        let prefs = settings.prefs
        let modules = prefs.menubar.order.filter { prefs.showsInMenubar($0) }
        HStack(spacing: 6) {
            ForEach(modules) { m in
                let hidden = blocked.contains(m)
                HStack(spacing: 6) {
                    LineIcon(d: Icons.drag, width: 8, height: 10, viewBox: CGSize(width: 16, height: 16), lineWidth: 2.4)
                        .opacity(0.5)
                        .accessibilityHidden(true)
                    Text(m.title).ui(12)
                }
                .foregroundStyle(hidden ? Theme.warn : Theme.text)
                .padding(.leading, 7)
                .padding(.trailing, 9)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hidden ? Theme.warnBg : Theme.well))
                .opacity(dragging == m ? 0.4 : 1)
                .modifier(ReorderModifier(module: m, dragging: $dragging))
                .accessibilityLabel(m.title)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Settings.orderA11y)
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

/// The menu bar as it will look with the current settings, at real size, ending with the
/// system's Wi-Fi glyph and clock. Modules behind the notch sit under a black notch block.
struct MenubarPreview: View {
    var blocked: [Module] = []
    var settings = SettingsStore.shared
    var monitor = Monitor.shared

    var body: some View {
        let prefs = settings.prefs
        let modules = prefs.menubar.order.filter { prefs.showsInMenubar($0) && MenuBarText.available($0, monitor.snapshot) }
        HStack(spacing: 2) {
            Spacer(minLength: 0)
            if prefs.menubar.displayMode == .combined {
                CombinedMenuBarView()
            } else {
                ForEach(modules.filter { !blocked.contains($0) }) { MenuBarItemView(module: $0) }
            }
            LineIcon(d: Icons.wifi, size: 16, lineWidth: 1.6)
                .padding(.horizontal, 5)
            Text(Format.time(Date())).font(BarFont.value()).padding(.horizontal, 5)
        }
        .foregroundStyle(Theme.barFg)
        .padding(.horizontal, 5)
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

/// Title row of a monitor page and of its settings: settings button and the module's switch.
struct ModuleHeader<Extra: View>: View {
    let module: Module
    var settingsActive = false
    @ViewBuilder var extra: Extra
    var settings = SettingsStore.shared

    var body: some View {
        HStack(spacing: 20) {
            Text(module.title).ui(20, 600).kerning(-0.2).accessibilityAddTraits(.isHeader)
            extra
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button {
                    Navigator.shared.page = settingsActive ? .monitor(module) : .moduleSettings(module)
                } label: {
                    LineIcon(d: Icons.general, size: 16, lineWidth: 1.5)
                        .foregroundStyle(settingsActive ? Theme.text : Theme.sub)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(settingsActive ? Theme.raised : Color.clear)
                                .raisedShadow(settingsActive)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Settings.moduleSettings(module.title))
                .accessibilityAddTraits(settingsActive ? [.isSelected] : [])
                HumSwitch(isOn: Binding(get: { settings.prefs.isVisible(module) }, set: { settings.prefs.setVisible(module, $0) }),
                          label: L10n.Settings.monitorModule(module.title))
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 14)
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

/// The module's widgets as they look in the menu bar: on (raised) | off. Click to toggle.
struct WidgetStrip: View {
    let module: Module
    var settings = SettingsStore.shared

    var body: some View {
        let prefs = settings.prefs
        let on = prefs.widgets(module)
        let off = module.widgetKinds.filter { !on.contains($0) }
        FlowLayout(spacing: 4) {
            ForEach(on) { chip($0, on: true, prefs) }
            Rectangle().fill(Theme.cross).frame(width: 1, height: 22).padding(.horizontal, 6).frame(height: 36)
            ForEach(off) { chip($0, on: false, prefs) }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Settings.widgetStripA11y)
    }

    private func chip(_ kind: WidgetKind, on: Bool, _ prefs: Preferences) -> some View {
        Button {
            settings.prefs.setWidget(kind, !on, for: module)
            if !on && !settings.prefs.isVisible(module) { settings.prefs.setVisible(module, true) }
        } label: {
            WidgetView(module: module, kind: kind, prefs: prefs)
                .environment(\.widgetUIFont, true)
                .foregroundStyle(on ? Theme.text : Theme.sub)
                .opacity(on ? 1 : 0.6)
                .padding(.horizontal, 9)
                .frame(minWidth: 40)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? Theme.raised : Color.clear).raisedShadow(on))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    SettingsRow(title: L10n.Settings.mergeWidgets) {
                        HumSwitch(isOn: Binding(get: { settings.prefs.widgetsMerged(module) }, set: { settings.prefs.setWidgetsMerged($0, module) }),
                                  label: L10n.Settings.mergeWidgets)
                    }
                }
            }
            if widgets.isEmpty {
                Text(L10n.Settings.notInMenubar).foregroundStyle(Theme.sub)
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
                    WidgetOptionsGroup(module: module, kind: kind)
                }
            }
        }
    }
}

/// The options of one widget, bound to its stored `WidgetOptions`.
struct WidgetOptionsGroup: View {
    let module: Module
    let kind: WidgetKind
    var settings = SettingsStore.shared

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
            case .line:
                toggle(L10n.Widget.label, \.showLabel)
                toggle(L10n.Settings.showValue, \.showValue)
                if module == .cpu {
                    SettingsRow(title: L10n.Settings.graphContent) {
                        Segmented(label: L10n.Settings.graphContent, options: [(CPUGraphContent.total, L10n.Settings.totalUsage), (.userSystem, L10n.Settings.userSystem)], selection: bind(\.graphContent))
                    }
                }
                toggle(L10n.Widget.boxed, \.boxed)
                colorRow()
                pointsRow()
            case .bar:
                if module == .memory || module == .disk {
                    toggle(L10n.Settings.showValue, \.showValue)
                } else {
                    toggle(L10n.Widget.label, \.showLabel)
                    toggle(L10n.Widget.boxed, \.boxed)
                }
                colorRow()
            case .pie, .tacho:
                toggle(L10n.Widget.label, \.showLabel)
                toggle(L10n.Widget.monochrome, \.monochrome)
            case .icon:
                SettingsRow(title: L10n.Widget.icon) {
                    Segmented(label: L10n.Widget.icon,
                              options: (0..<4).map { ($0, "") }, selection: bind(\.icon), style: .compact,
                              glyph: { i in AnyView(LineIcon(d: WidgetView.iconPath(module, i), size: 14, lineWidth: 1.4)) })
                }
            case .ring:
                toggle(L10n.Settings.showValue, \.showValue)
                colorRow()
            case .memory:
                colorRow()
                toggle(L10n.Widget.showSymbol, \.showSymbol)
                toggle(L10n.Widget.freeOnTop, \.freeOnTop)
            case .speed where module == .network:
                SettingsRow(title: L10n.Widget.glyph) {
                    Segmented(label: L10n.Widget.glyph, options: [(SpeedGlyph.arrows, L10n.Widget.arrows), (.dots, L10n.Widget.dots), (.none, L10n.Common.none)], selection: bind(\.glyph))
                }
                layoutRow()
                toggle(L10n.Settings.showUnit, \.showUnit)
                SettingsRow(title: L10n.Settings.order) {
                    Segmented(label: L10n.Settings.order, options: [(true, L10n.Settings.uploadTop), (false, L10n.Settings.downloadTop)], selection: bind(\.firstOnTop))
                }
                SettingsRow(title: L10n.Settings.color) {
                    Segmented(label: L10n.Settings.color, options: [(WidgetColor.mono, L10n.Common.mono), (.colored, L10n.Common.colored)], selection: bind(\.color))
                }
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
                toggle(L10n.Widget.label, \.showLabel)
                toggle(L10n.Widget.boxed, \.boxed)
                paletteRow(module == .network ? L10n.Widget.downloadColor : L10n.Widget.readColor, \.firstColor)
                paletteRow(module == .network ? L10n.Widget.uploadColor : L10n.Widget.writeColor, \.secondColor)
                pointsRow()
            case .state:
                paletteRow(L10n.Widget.connected, \.firstColor)
                paletteRow(L10n.Widget.disconnected, \.secondColor)
            case .value:
                toggle(L10n.Widget.showIcon, \.showIcon)
                toggle(L10n.Settings.showUnit, \.showUnit)
            case .battery:
                toggle(L10n.Widget.showPercent, \.showPercent)
                toggle(L10n.Settings.showTimeRemaining, \.showTime)
                toggle(L10n.Widget.hidePercentWhenFull, \.hidePercentWhenFull)
                toggle(L10n.Settings.showBolt, \.showBolt)
                toggle(L10n.Settings.colorWhenLow, \.colorWhenLow)
            case .details:
                SettingsRow(title: L10n.Widget.detailsContent) {
                    MenuPill(label: L10n.Widget.detailsContent,
                             options: [(BatteryDetails.percentAndTime, L10n.Widget.percentAndTime), (.percent, L10n.Widget.percentOnly), (.time, L10n.Widget.timeOnly)],
                             selection: bind(\.details))
                }
            case .temp:
                toggle(L10n.Widget.showIcon, \.showIcon)
                SettingsRow(title: L10n.Settings.color) {
                    Segmented(label: L10n.Settings.color, options: [(WidgetColor.mono, L10n.Common.mono), (.byValue, L10n.Settings.byTemperature)], selection: bind(\.color))
                }
            case .fan:
                toggle(L10n.Widget.showIcon, \.showIcon)
                SettingsRow(title: L10n.Widget.fanValue) {
                    Segmented(label: L10n.Widget.fanValue, options: [(FanValue.rpm, L10n.Widget.rpm), (.percent, L10n.Settings.percent)], selection: bind(\.fanValue))
                }
            case .stack:
                layoutRow()
                toggle(L10n.Widget.monospaced, \.monospaced)
                alignRow()
            }
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
