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

// MARK: - General

struct GeneralSettingsPage: View {
    var settings = SettingsStore.shared
    var updater = UpdateChecker.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var needsApproval = SMAppService.mainApp.status == .requiresApproval
    @State private var languageChanged = false

    var body: some View {
        let g = settings.prefs.general
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: L10n.Sidebar.general)

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

            SettingsGroup(title: L10n.Settings.performance) {
                SettingsRow(title: L10n.Settings.refreshInterval) {
                    Segmented(label: L10n.Settings.refreshInterval,
                              options: [(1.0, L10n.Settings.seconds(1)), (2.0, L10n.Settings.seconds(2)), (5.0, L10n.Settings.seconds(5))],
                              selection: pref(\.general.refreshInterval))
                }
                SettingsRow(title: L10n.Settings.slowOnBattery) {
                    HumSwitch(isOn: pref(\.general.slowOnBattery), label: L10n.Settings.slowOnBattery)
                }
            }

            SettingsGroup(title: L10n.Settings.updates) {
                SettingsRow(title: L10n.Settings.autoCheckUpdates) {
                    HumSwitch(isOn: pref(\.general.autoCheckUpdates), label: L10n.Settings.autoCheckUpdates)
                }
                HStack(spacing: 12) {
                    (Text(L10n.Settings.currentVersion).foregroundColor(Theme.sub)
                        + Text(verbatim: " ")
                        + Text(SystemInfo.appVersion).font(Fonts.ui(13, 500)).foregroundColor(Theme.text))
                        .ui(13)
                    Spacer(minLength: 8)
                    WellButton(title: updater.buttonTitle) { updater.check() }
                        .disabled(!updater.isConfigured || updater.state == .checking)
                        .opacity(updater.isConfigured ? 1 : 0.5)
                }
                .frame(minHeight: 42)
            }
        }
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

// MARK: - Menu bar

struct MenubarSettingsPage: View {
    var settings = SettingsStore.shared
    var notch = NotchWatcher.shared
    @State private var dragging: Module?

    var body: some View {
        let prefs = settings.prefs
        let blocked = prefs.menubar.displayMode == .separate ? notch.hidden : []
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(title: L10n.Sidebar.menubar) {
                HStack(spacing: 10) {
                    if !blocked.isEmpty { NotchStatus(count: blocked.count) }
                    WellButton(title: L10n.Settings.restoreDefaults) { settings.resetMenubar() }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                groupTitle(L10n.Settings.preview)
                MenubarPreview()
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            }

            SettingsGroup(title: L10n.Settings.display) {
                SettingsRow(title: L10n.Settings.displayMode, height: 40) {
                    Segmented(label: L10n.Settings.displayMode, options: [(DisplayMode.separate, L10n.Settings.separate), (.combined, L10n.Settings.combined)], selection: pref(\.menubar.displayMode))
                }
                SettingsRow(title: L10n.Settings.iconColor, height: 40) {
                    Segmented(label: L10n.Settings.iconColor, options: [(ColorMode.mono, L10n.Common.mono), (.color, L10n.Common.colored)], selection: pref(\.menubar.iconColor))
                }
                SettingsRow(title: L10n.Settings.colorOnHighLoad, height: 40) {
                    HumSwitch(isOn: pref(\.menubar.colorOnHighLoad), label: L10n.Settings.colorOnHighLoad)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                groupTitle(L10n.Settings.modules)
                VStack(spacing: 0) {
                    ForEach(prefs.menubar.order) { m in
                        ModuleRow(module: m, blocked: blocked.contains(m))
                            .overlay(alignment: .top) { if m != prefs.menubar.order.first { Hairline() } }
                            .opacity(dragging == m ? 0.4 : 1)
                            .modifier(ReorderModifier(module: m, dragging: $dragging))
                    }
                }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            }
        }
    }

    private func groupTitle(_ text: String) -> some View {
        Text(text).ui(13, 500).foregroundStyle(Theme.sub)
            .padding(.horizontal, 14).padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// "2 个模块被刘海挡住 [合并成一项]" next to the page title.
struct NotchStatus: View {
    var count: Int
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 8) {
            LineIcon(d: Icons.notch, size: 14, lineWidth: 1.5)
            Text(L10n.Notch.hiddenCount(count)).ui(12, 500).lineLimit(1)
            Button {
                SettingsStore.shared.prefs.menubar.displayMode = .combined
            } label: {
                Text(L10n.Notch.merge).ui(12, 500)
                    .foregroundStyle(accent.onAccent)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(accent.accent))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.warn)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.warnBg))
        .fixedSize()
        .accessibilityElement(children: .contain)
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
/// system's Wi-Fi glyph and clock for context.
struct MenubarPreview: View {
    var settings = SettingsStore.shared
    var monitor = Monitor.shared

    var body: some View {
        let prefs = settings.prefs
        let modules = prefs.menubar.order.filter { prefs.isVisible($0) && MenuBarText.available($0, monitor.snapshot) }
        HStack(spacing: 2) {
            Spacer(minLength: 0)
            if prefs.menubar.displayMode == .combined {
                CombinedMenuBarView()
            } else {
                ForEach(modules) { MenuBarItemView(module: $0) }
            }
            LineIcon(d: Icons.wifi, size: 16, lineWidth: 1.6)
                .padding(.horizontal, 5)
            Text(Format.time(Date())).font(BarFont.value()).padding(.horizontal, 5)
        }
        .foregroundStyle(Theme.barFg)
        .padding(.horizontal, 5)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.bar))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.Settings.previewA11y(modules.map { MenuBarText.accessibility($0, monitor.snapshot, prefs) }.joined(separator: L10n.A11y.separator)))
    }
}

/// One module: drag handle, icon, name, style picker, show switch, › to its page.
struct ModuleRow: View {
    let module: Module
    var blocked = false
    var settings = SettingsStore.shared

    var body: some View {
        let visible = settings.prefs.isVisible(module)
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                LineIcon(d: Icons.drag, size: 12, lineWidth: 2.4).foregroundStyle(Theme.faint)
                    .accessibilityHidden(true)
                LineIcon(d: Icons.module(module), size: 16, lineWidth: 1.5).foregroundStyle(Theme.sub)
                    .accessibilityHidden(true)
                Text(module.title).lineLimit(1)
                if blocked { StatusPill(text: L10n.Notch.blocked, fg: Theme.warn, bg: Theme.warnBg) }
                Spacer(minLength: 0)
            }
            StylePicker(module: module)
            HumSwitch(isOn: Binding(get: { visible }, set: { settings.prefs.setVisible(module, $0) }), label: L10n.Settings.showInMenubarNamed(module.title))
            IconButton(d: Icons.chevronSmallRight, label: L10n.Settings.moreSettings(module.title)) {
                Navigator.shared.page = .menubarModule(module)
            }
        }
        .frame(minHeight: 40)
    }
}

/// Four 64 × 26 segments, each a small drawing of the item in that style with live values.
struct StylePicker: View {
    let module: Module
    var settings = SettingsStore.shared

    var body: some View {
        let names = StylePicker.styles(module)
        let selected = StylePicker.selectedIndex(module, settings.prefs)
        HStack(spacing: 2) {
            ForEach(names.indices, id: \.self) { i in
                let on = i == selected
                Button {
                    settings.prefs = StylePicker.apply(module, i, to: settings.prefs)
                } label: {
                    StyleMini(module: module, style: i)
                        .ui(12, on ? 500 : 400)
                        .foregroundStyle(on ? Theme.text : Theme.sub)
                        .frame(width: 64, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(on ? Theme.raised : Color.clear)
                                .raisedShadow(on)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(names[i])
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.well))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Settings.iconStyleNamed(module.title))
    }

    static func styles(_ m: Module) -> [String] {
        switch m {
        case .cpu, .gpu: return [L10n.Style.graph, L10n.Style.bar, L10n.Style.iconValue, L10n.Style.twoLine]
        case .memory: return [L10n.Style.bar, L10n.Style.ring, L10n.Style.iconValue, L10n.Style.twoLine]
        case .network: return [L10n.Style.arrows, L10n.Style.dots, L10n.Style.singleLine, L10n.Style.iconOnly]
        case .disk: return [L10n.Style.iconValue, L10n.Style.bar, L10n.Style.readWrite, L10n.Style.twoLine]
        case .battery: return [L10n.Style.iconPercent, L10n.Style.iconOnly, L10n.Style.percentOnly, L10n.Style.twoLine]
        case .sensors: return [L10n.Style.iconTemp, L10n.Style.tempOnly, L10n.Style.fan, L10n.Style.twoLine]
        }
    }

    static func selectedIndex(_ m: Module, _ p: Preferences) -> Int {
        switch m {
        case .cpu: return CPUStyle.allCases.firstIndex(of: p.cpu.style) ?? 0
        case .gpu: return GPUStyle.allCases.firstIndex(of: p.gpu.style) ?? 0
        case .memory: return MemoryStyle.allCases.firstIndex(of: p.memory.style) ?? 0
        case .network: return NetworkStyle.allCases.firstIndex(of: p.network.style) ?? 0
        case .disk: return DiskStyle.allCases.firstIndex(of: p.disk.style) ?? 0
        case .battery: return BatteryStyle.allCases.firstIndex(of: p.battery.style) ?? 0
        case .sensors: return SensorsStyle.allCases.firstIndex(of: p.sensors.style) ?? 0
        }
    }

    static func apply(_ m: Module, _ i: Int, to base: Preferences) -> Preferences {
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

/// Miniature of a menu bar item in one style, drawn in the current foreground style
/// (style picker segments, onboarding rows).
struct StyleMini: View {
    let module: Module
    let style: Int
    /// The onboarding chips draw a little larger: filled graph, 22 pt meters, rates with units.
    var large = false
    var monitor = Monitor.shared
    var settings = SettingsStore.shared

    var body: some View {
        HStack(spacing: 3) { content }
            .lineLimit(1)
            .fixedSize()
    }

    private var s: Snapshot { monitor.snapshot }
    private var prefs: Preferences { settings.prefs }

    @ViewBuilder private var content: some View {
        switch module {
        case .cpu: processor(s.cpu.total, metric: .cpu, icon: Icons.cpu)
        case .gpu: processor(s.gpu.utilization, metric: .gpu, icon: Icons.gpu)
        case .memory: memory
        case .network: network
        case .disk: disk
        case .battery: battery
        case .sensors: sensors
        }
    }

    @ViewBuilder private func processor(_ fraction: Double, metric: Metric, icon: String) -> some View {
        let value = Format.percent(fraction)
        switch style {
        case 0:
            let _ = monitor.tick
            TrendLine(values: monitor.history.latest(metric, seconds: 60).map { $0 / 100 }, lineWidth: large ? 1.25 : 1.2, fillOpacity: large ? 0.25 : 0)
                .frame(width: 24, height: 14)
                .background(Theme.tile)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text(value)
        case 1:
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous).strokeBorder(Theme.rim, lineWidth: 1)
                Rectangle().fill(.foreground).frame(height: 14 * min(1, max(0, fraction)))
            }
            .frame(width: 4, height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))
            Text(value)
        case 2:
            LineIcon(d: icon, size: 14, lineWidth: 1.4)
            Text(value)
        default:
            twoLine(module.compactLabel, value)
        }
    }

    @ViewBuilder private var memory: some View {
        let fraction = s.memory.usedFraction
        let value = Format.percent(fraction)
        switch style {
        case 0:
            PillMini(fraction: fraction, large: large)
            Text(value)
        case 1:
            ZStack {
                Circle().stroke(Theme.rim, lineWidth: 2)
                Circle().trim(from: 0, to: min(1, max(0, fraction)))
                    .stroke(.foreground, style: StrokeStyle(lineWidth: 2))
                    .rotationEffect(.degrees(-90))
            }
            .padding(1.07)
            .frame(width: 13, height: 13)
            Text(value)
        case 2:
            LineIcon(d: Icons.memory, size: 14, lineWidth: 1.4)
            Text(value)
        default:
            twoLine(module.compactLabel, value)
        }
    }

    @ViewBuilder private var network: some View {
        let n = s.network
        let p = prefs.network
        let up = n.connected ? Format.rateCompact(n.up, unit: p.speedUnit) : L10n.Common.dash
        let down = n.connected ? Format.rateCompact(n.down, unit: p.speedUnit) : L10n.Common.dash
        let upTop = p.order == .uploadTop
        switch style {
        case 0 where large:
            NetArrows(upOnTop: upTop, height: 18)
            VStack(alignment: .trailing, spacing: 0) {
                let upFull = n.connected ? Format.rate(n.up, unit: p.speedUnit) : L10n.Common.dash
                let downFull = n.connected ? Format.rate(n.down, unit: p.speedUnit) : L10n.Common.dash
                Text(upTop ? upFull : downFull).frame(height: 9)
                Text(upTop ? downFull : upFull).frame(height: 9)
            }
            .ui(8, 300)
        case 0:
            Grid(alignment: .trailing, horizontalSpacing: 2, verticalSpacing: 0) {
                GridRow {
                    LineIcon(d: upTop ? Icons.arrowUpSmall : Icons.arrowDownSmall, size: 5, viewBox: 6, lineWidth: 0.92)
                    Text(upTop ? up : down).frame(height: 7)
                }
                GridRow {
                    LineIcon(d: upTop ? Icons.arrowDownSmall : Icons.arrowUpSmall, size: 5, viewBox: 6, lineWidth: 0.92)
                    Text(upTop ? down : up).frame(height: 7)
                }
            }
            .ui(8, 300)
        case 1:
            VStack(spacing: 3) {
                Circle().strokeBorder(.foreground, lineWidth: 1).frame(width: 4, height: 4)
                Circle().fill(.foreground).frame(width: 4, height: 4)
            }
            VStack(alignment: .trailing, spacing: 0) {
                Text(upTop ? up : down).frame(height: 7)
                Text(upTop ? down : up).frame(height: 7)
            }
            .ui(8, 300)
        case 2:
            Text([MenuBarText.downArrow, down, MenuBarText.upArrow, up].joined(separator: " ")).ui(10)
        default:
            LineIcon(d: Icons.network, size: 14, lineWidth: 1.4)
        }
    }

    @ViewBuilder private var disk: some View {
        let volume = MenuBarText.volume(s.disk, prefs.disk.volume)
        let used = volume.map { Format.percent($0.usedFraction) } ?? L10n.Common.dash
        switch style {
        case 0:
            LineIcon(d: Icons.disk, size: 14, lineWidth: 1.4)
            Text(volume.map { MenuBarText.gigabytes(UInt64(max(0, $0.available)), decimal: true) } ?? L10n.Common.dash)
        case 1:
            PillMini(fraction: volume?.usedFraction ?? 0, large: large)
            Text(used)
        case 2:
            Grid(alignment: .leading, horizontalSpacing: 2, verticalSpacing: 0) {
                GridRow {
                    Text(MenuBarText.readLetter).foregroundStyle(Theme.faint)
                    Text(Format.rateCompact(s.disk.read))
                }
                .frame(height: 8.5)
                GridRow {
                    Text(MenuBarText.writeLetter).foregroundStyle(Theme.faint)
                    Text(Format.rateCompact(s.disk.write))
                }
                .frame(height: 8.5)
            }
            .ui(8, 300)
        default:
            twoLine(module.compactLabel, used)
        }
    }

    @ViewBuilder private var battery: some View {
        let level = s.battery.level
        switch style {
        case 0:
            BatteryGlyph(level: level, scale: large ? 0.88 : 0.8)
            Text(Format.percent(level))
        case 1:
            BatteryGlyph(level: level, scale: large ? 0.88 : 0.8)
        case 2:
            Text(Format.percent(level))
        default:
            twoLine(module.compactLabel, Format.percent(level))
        }
    }

    @ViewBuilder private var sensors: some View {
        let value = MenuBarText.sensorValue(s.sensors, prefs.sensors.sensor)
            .map { Format.temperature($0, unit: prefs.general.temperatureUnit) } ?? L10n.Common.dash
        switch style {
        case 0:
            LineIcon(d: Icons.sensors, size: 14, lineWidth: 1.4)
            Text(value)
        case 1:
            Text(value)
        case 2:
            LineIcon(d: Icons.fan, size: 14, lineWidth: 1.3)
            Text(s.sensors.fans.first.map { "\(Int($0.rpm.rounded()))" } ?? L10n.Common.dash)
        default:
            twoLine(module.compactLabel, value)
        }
    }

    private func twoLine(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(label).ui(7, 300).frame(height: 7)
            Text(value).ui(11).frame(height: 11)
        }
    }
}

/// Capsule meter used in the style picker (18 × 9) and onboarding (22 × 10).
struct PillMini: View {
    var fraction: Double
    var large = false

    var body: some View {
        let width: CGFloat = large ? 22 : 18
        let height: CGFloat = large ? 10 : 9
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .strokeBorder(Theme.rim, lineWidth: 1)
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: large ? 2.5 : 2, style: .continuous)
                    .fill(.foreground)
                    .frame(width: max(1, (width - 5) * min(1, max(0, fraction))), height: height - 5)
                    .padding(.leading, 2.5)
            }
    }
}

// MARK: - Per-module menu bar page

struct MenubarModulePage: View {
    let module: Module
    var settings = SettingsStore.shared
    var monitor = Monitor.shared

    var body: some View {
        let visible = settings.prefs.isVisible(module)
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                IconButton(d: Icons.chevronSmallLeft, size: 32, radius: 10, tint: Theme.text, label: L10n.Settings.backToMenubar) {
                    Navigator.shared.page = .menubar
                }
                Text(L10n.Settings.breadcrumb).ui(24, 500).kerning(-0.48).foregroundStyle(Theme.sub)
                Text(module.title).ui(24, 500).kerning(-0.48).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Text(L10n.Settings.showInMenubar).foregroundStyle(Theme.sub)
                    HumSwitch(isOn: Binding(get: { visible }, set: { settings.prefs.setVisible(module, $0) }), label: L10n.Settings.showInMenubar)
                }
            }
            .frame(height: 36)
            .padding(.horizontal, 14)

            SettingsGroup(title: L10n.Settings.menubarGroup) {
                SettingsRow(title: L10n.Settings.iconStyle) { StylePicker(module: module) }
                menubarRows
            }
            SettingsGroup(title: L10n.Settings.panelGroup) {
                panelRows
            }
        }
    }

    private var counts: [(Int, String)] { [3, 4, 5, 6, 8].map { ($0, L10n.Common.count($0)) } }

    @ViewBuilder private var menubarRows: some View {
        switch module {
        case .cpu:
            toggleRow(L10n.Settings.showValue, \.cpu.showValue)
            SettingsRow(title: L10n.Settings.graphContent) {
                Segmented(label: L10n.Settings.graphContent, options: [(CPUGraphContent.total, L10n.Settings.totalUsage), (.userSystem, L10n.Settings.userSystem)], selection: pref(\.cpu.graphContent))
            }
            colorRow(\.cpu.color)
        case .gpu:
            toggleRow(L10n.Settings.showValue, \.gpu.showValue)
            SettingsRow(title: L10n.Settings.valueType) {
                Segmented(label: L10n.Settings.valueType, options: [(GPUValueType.utilization, L10n.Panel.utilization), (.memory, L10n.Panel.vram)], selection: pref(\.gpu.valueType))
            }
            colorRow(\.gpu.color)
        case .memory:
            toggleRow(L10n.Settings.showValue, \.memory.showValue)
            SettingsRow(title: L10n.Settings.valueType) {
                Segmented(label: L10n.Settings.valueType, options: [(MemoryValueType.percent, L10n.Settings.percent), (.usedGB, L10n.Settings.usedGB)], selection: pref(\.memory.valueType))
            }
            SettingsRow(title: L10n.Settings.color) {
                Segmented(label: L10n.Settings.color, options: [(MemoryColor.mono, L10n.Common.mono), (.pressure, L10n.Settings.byPressure)], selection: pref(\.memory.color))
            }
        case .network:
            toggleRow(L10n.Settings.showUnit, \.network.showUnit)
            SettingsRow(title: L10n.Settings.order) {
                Segmented(label: L10n.Settings.order, options: [(NetworkOrder.uploadTop, L10n.Settings.uploadTop), (.downloadTop, L10n.Settings.downloadTop)], selection: pref(\.network.order))
            }
            colorRow(\.network.color)
            SettingsRow(title: L10n.Settings.speedUnit) {
                MenuPill(label: L10n.Settings.speedUnit, options: [(SpeedUnit.auto, L10n.Common.auto), (.bytes, L10n.Settings.unitBytes), (.bits, L10n.Settings.unitBits)], selection: pref(\.network.speedUnit))
            }
        case .disk:
            SettingsRow(title: L10n.Settings.diskContent) {
                Segmented(label: L10n.Settings.diskContent, options: [(DiskContent.free, L10n.Settings.freeSpace), (.usedPercent, L10n.Settings.usedPercent), (.readWrite, L10n.Settings.readWrite)], selection: pref(\.disk.content))
            }
            SettingsRow(title: L10n.Settings.whichDisk) {
                MenuPill(label: L10n.Settings.whichDisk,
                         options: [("", monitor.snapshot.disk.root?.name ?? L10n.Settings.startupDisk)]
                            + monitor.snapshot.disk.volumes.filter { !$0.isRoot }.map { ($0.name, $0.name) },
                         selection: pref(\.disk.volume))
            }
        case .battery:
            toggleRow(L10n.Settings.showTimeRemaining, \.battery.showTimeRemaining)
            toggleRow(L10n.Settings.showBolt, \.battery.showBolt)
            toggleRow(L10n.Settings.colorWhenLow, \.battery.colorWhenLow)
        case .sensors:
            SettingsRow(title: L10n.Settings.whichSensor) {
                MenuPill(label: L10n.Settings.whichSensor, options: SensorChoice.allCases.map { ($0, L10n.Sensors.choice($0)) }, selection: pref(\.sensors.sensor))
            }
            SettingsRow(title: L10n.Settings.color) {
                Segmented(label: L10n.Settings.color, options: [(TempColor.mono, L10n.Common.mono), (.byTemp, L10n.Settings.byTemperature)], selection: pref(\.sensors.color))
            }
        }
    }

    @ViewBuilder private var panelRows: some View {
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
            toggleRow(L10n.Settings.showProcesses, \.gpu.showProcesses)
            SettingsRow(title: L10n.Settings.processCount) { MenuPill(label: L10n.Settings.processCount, options: counts, selection: pref(\.gpu.processCount)) }
        case .memory:
            toggleRow(L10n.Settings.showComposition, \.memory.showComposition)
            toggleRow(L10n.Settings.showPressure, \.memory.showPressure)
            toggleRow(L10n.Settings.showSwap, \.memory.showSwap)
            toggleRow(L10n.Settings.showProcesses, \.memory.showProcesses)
            SettingsRow(title: L10n.Settings.processCount) { MenuPill(label: L10n.Settings.processCount, options: counts, selection: pref(\.memory.processCount)) }
        case .network:
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
            toggleRow(L10n.Settings.showProcesses, \.disk.showProcesses)
        case .battery:
            toggleRow(L10n.Settings.showHealth, \.battery.showHealth)
            toggleRow(L10n.Settings.showCycles, \.battery.showCycles)
            toggleRow(L10n.Settings.showChargingPower, \.battery.showPower)
            toggleRow(L10n.Settings.showBluetooth, \.battery.showBluetooth)
        case .sensors:
            toggleRow(L10n.Settings.showAllTemps, \.sensors.showAllTemps)
            toggleRow(L10n.Settings.showFans, \.sensors.showFans)
            toggleRow(L10n.Settings.showPower, \.sensors.showPower)
        }
    }

    private var autoInterfaceLabel: String {
        let n = monitor.snapshot.network
        return n.interface.isEmpty ? L10n.Common.auto : L10n.Settings.autoWith(PanelText.kindName(n.kind))
    }

    private func toggleRow(_ title: String, _ keyPath: WritableKeyPath<Preferences, Bool>) -> some View {
        SettingsRow(title: title) { HumSwitch(isOn: pref(keyPath), label: title) }
    }

    private func colorRow(_ keyPath: WritableKeyPath<Preferences, ColorMode>) -> some View {
        SettingsRow(title: L10n.Settings.color) {
            Segmented(label: L10n.Settings.color, options: [(ColorMode.mono, L10n.Common.mono), (.color, L10n.Common.colored)], selection: pref(keyPath))
        }
    }
}

// MARK: - Alerts

struct AlertsSettingsPage: View {
    var settings = SettingsStore.shared
    @State private var authorization: UNAuthorizationStatus = .notDetermined

    var body: some View {
        let a = settings.prefs.alerts
        let unit = settings.prefs.general.temperatureUnit
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: L10n.Sidebar.alerts) {
                HStack(spacing: 10) {
                    Text(L10n.Settings.alertsEnabled).foregroundStyle(Theme.sub)
                    HumSwitch(isOn: pref(\.alerts.enabled), label: L10n.Settings.alertsEnabled)
                }
            }
            if authorization == .denied {
                SettingsGroup {
                    SettingsRow(title: L10n.Settings.notificationsOff) {
                        WellButton(title: L10n.Settings.openNotificationSettings) { openNotificationSettings() }
                    }
                }
            }
            SettingsGroup(title: L10n.Settings.rules) {
                rule(Icons.cpu, \.alerts.cpuOn, label: L10n.Settings.ruleCPUSwitch) {
                    Text(L10n.Settings.ruleCPU)
                    InlineChoice(label: L10n.Settings.ruleCPU, options: [70, 80, 90, 95].map { (Double($0), Format.percent(Double($0) / 100)) }, selection: pref(\.alerts.cpuThreshold))
                    Text(L10n.Settings.ruleFor)
                    InlineChoice(label: L10n.Settings.ruleFor,
                                 options: [(0.5, L10n.Alerts.seconds(30)), (1, L10n.Alerts.minutes(1)), (2, L10n.Alerts.minutes(2)), (5, L10n.Alerts.minutes(5))],
                                 selection: pref(\.alerts.cpuMinutes))
                }
                rule(Icons.memory, \.alerts.memoryOn, label: L10n.Settings.ruleMemorySwitch) {
                    Text(L10n.Settings.ruleMemory)
                    InlineChoice(label: L10n.Settings.ruleMemory, options: [(MemoryPressure.warning, L10n.Settings.yellow), (.critical, L10n.Settings.red)], selection: pref(\.alerts.memoryLevel))
                }
                rule(Icons.disk, \.alerts.diskOn, label: L10n.Settings.ruleDiskSwitch) {
                    Text(L10n.Settings.ruleDisk)
                    InlineChoice(label: L10n.Settings.ruleDisk, options: [5, 10, 20, 50].map { (Double($0), L10n.Settings.gigabytes($0)) }, selection: pref(\.alerts.diskFreeGB))
                }
                rule(Icons.battery, \.alerts.batteryOn, label: L10n.Settings.ruleBatterySwitch) {
                    Text(L10n.Settings.ruleBattery)
                    InlineChoice(label: L10n.Settings.ruleBattery, options: [10, 15, 20, 30].map { (Double($0), Format.percent(Double($0) / 100)) }, selection: pref(\.alerts.batteryPercent))
                }
                rule(Icons.sensors, \.alerts.tempOn, label: L10n.Settings.ruleTempSwitch) {
                    Text(L10n.Settings.ruleTemp)
                    InlineChoice(label: L10n.Settings.ruleTemp, options: [85, 90, 95, 100].map { (Double($0), Format.temperature(Double($0), unit: unit, showUnit: true)) }, selection: pref(\.alerts.tempThreshold))
                }
                rule(Icons.network, \.alerts.networkOn, label: L10n.Settings.ruleNetworkSwitch) {
                    Text(L10n.Settings.ruleNetwork)
                }
            }
            .opacity(a.enabled ? 1 : 0.5)
            .disabled(!a.enabled)

            SettingsGroup(title: L10n.Settings.delivery) {
                SettingsRow(title: L10n.Settings.notificationStyle) {
                    Segmented(label: L10n.Settings.notificationStyle,
                              options: [(NotificationStyle.banner, L10n.Settings.banner), (.alert, L10n.Settings.alertStyle)],
                              selection: Binding(get: { a.style }, set: { style in
                                  guard style != settings.prefs.alerts.style else { return }
                                  settings.prefs.alerts.style = style
                                  // Banner vs. alert is a system setting per app; open the page where it is changed.
                                  openNotificationSettings()
                              }))
                }
                SettingsRow(title: L10n.Settings.playSound) { HumSwitch(isOn: pref(\.alerts.sound), label: L10n.Settings.playSound) }
                SettingsRow(title: L10n.Settings.colorMenubar) { HumSwitch(isOn: pref(\.alerts.colorMenubar), label: L10n.Settings.colorMenubar) }
            }
            .opacity(a.enabled ? 1 : 0.5)
            .disabled(!a.enabled)
        }
        .task { await refreshAuthorization() }
    }

    private func rule<Content: View>(_ icon: String, _ keyPath: WritableKeyPath<Preferences, Bool>, label: String, @ViewBuilder sentence: () -> Content) -> some View {
        let on = settings.prefs[keyPath: keyPath]
        return HStack(spacing: 12) {
            HStack(spacing: 12) {
                LineIcon(d: icon, size: 16, lineWidth: 1.5).foregroundStyle(Theme.sub)
                    .accessibilityHidden(true)
                HStack(spacing: 4) { sentence() }
                    .opacity(on ? 1 : 0.5)
            }
            .padding(.vertical, 8)
            Spacer(minLength: 8)
            HumSwitch(isOn: pref(keyPath), label: label)
        }
        .frame(minHeight: 48)
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

// MARK: - About

struct AboutPage: View {
    var monitor = Monitor.shared

    var body: some View {
        let s = monitor.snapshot
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: L10n.Sidebar.about)
            Panel(padding: EdgeInsets(top: 18, leading: 14, bottom: 18, trailing: 14)) {
                HStack(spacing: 14) {
                    AppMark(size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.App.name).ui(18, 600).kerning(-0.18)
                        Text(L10n.App.version(SystemInfo.appVersion)).ui(12).foregroundStyle(Theme.sub)
                    }
                }
            }
            SettingsGroup(title: L10n.Settings.selfUsage) {
                SettingsRow(title: L10n.Module.cpu) { Text(Format.percentValue(s.selfCPU)).ui(13, 500) }
                SettingsRow(title: L10n.Module.memory) { Text(Format.memory(s.selfMemory)).ui(13, 500) }
                SettingsRow(title: L10n.Settings.refreshInterval) {
                    Text(L10n.Settings.seconds(Int(SettingsStore.shared.prefs.general.refreshInterval))).ui(13, 500)
                }
            }
            SettingsGroup(title: L10n.Settings.thisMac) {
                SettingsRow(title: L10n.Settings.chip) { Text(SystemInfo.chipName).ui(13, 500) }
                SettingsRow(title: L10n.Panel.cores) { Text(PanelText.coreSplit() ?? L10n.Panel.coreCount(SystemInfo.coreCount)).ui(13, 500) }
                SettingsRow(title: L10n.Memory.total) { Text(Format.memory(SystemInfo.physicalMemory)).ui(13, 500) }
                SettingsRow(title: L10n.Settings.macOS) { Text(ProcessInfo.processInfo.operatingSystemVersionString).ui(13, 500).lineLimit(1) }
            }
            HStack {
                Spacer()
                WellButton(title: L10n.Menu.quit) { NSApp.terminate(nil) }
            }
        }
    }
}
