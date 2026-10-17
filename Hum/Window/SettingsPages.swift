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
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var needsApproval = SMAppService.mainApp.status == .requiresApproval
    @State private var languageChanged = false
    @Environment(\.accent) private var accent

    var body: some View {
        let g = settings.prefs.general
        PageHeader(icon: nil, title: L10n.Sidebar.general)

        SettingsSection(title: L10n.Settings.startup) {
            SettingsRow(title: L10n.Settings.launchAtLogin) {
                HumToggle(isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }), label: L10n.Settings.launchAtLogin)
            }
            if needsApproval {
                SettingsRow(title: L10n.Settings.loginItemNeedsApproval) {
                    WellButton(title: L10n.Settings.openLoginItems) { SMAppService.openSystemSettingsLoginItems() }
                }
            }
        }

        SettingsSection(title: L10n.Settings.appearance) {
            HStack(spacing: 12) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    AppearanceThumb(mode: mode, selected: g.appearance == mode) {
                        settings.prefs.general.appearance = mode
                        Appearance.apply()
                    }
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.Settings.appearance)

            SettingsRow(title: L10n.Settings.accent) {
                HStack(spacing: 12) {
                    Text(L10n.Settings.palette(g.accent)).font(.system(size: 12)).foregroundStyle(Theme.sub)
                    HStack(spacing: 10) {
                        ForEach(AccentPalette.allCases) { p in
                            Button {
                                settings.prefs.general.accent = p
                            } label: {
                                Circle().fill(p.swatch)
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: g.accent == p ? 2 : 0).padding(-0.5))
                                    .overlay(Circle().strokeBorder(p.swatch, lineWidth: g.accent == p ? 2 : 0).padding(-3))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.Settings.palette(p))
                            .accessibilityAddTraits(g.accent == p ? [.isSelected] : [])
                        }
                    }
                }
            }
            SettingsRow(title: L10n.Settings.temperatureUnit) {
                SegmentedPicker(label: L10n.Settings.temperatureUnit, options: [(TemperatureUnit.celsius, "°C"), (.fahrenheit, "°F")], selection: pref(\.general.temperatureUnit))
            }
            SettingsRow(title: L10n.Settings.language) {
                HStack(spacing: 8) {
                    if languageChanged {
                        Button(L10n.Settings.restartToApply) { Appearance.relaunch() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(accent.tintText)
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

        SettingsSection(title: L10n.Settings.performance) {
            SettingsRow(title: L10n.Settings.refreshInterval) {
                SegmentedPicker(label: L10n.Settings.refreshInterval,
                                options: [(1.0, L10n.Settings.seconds(1)), (2.0, L10n.Settings.seconds(2)), (5.0, L10n.Settings.seconds(5))],
                                selection: pref(\.general.refreshInterval))
            }
            SettingsRow(title: L10n.Settings.slowOnBattery) {
                HumToggle(isOn: pref(\.general.slowOnBattery), label: L10n.Settings.slowOnBattery)
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

/// Window-shaped thumbnail for the appearance choice.
struct AppearanceThumb: View {
    var mode: AppearanceMode
    var selected: Bool
    var action: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .top) {
                    HStack(spacing: 0) {
                        if mode != .dark { Color(red: 0.89, green: 0.898, blue: 0.918) }
                        if mode != .light { Color(red: 0.11, green: 0.114, blue: 0.129) }
                    }
                    HStack(spacing: 0) {
                        if mode != .dark { window(light: true) }
                        if mode != .light { window(light: false) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(.horizontal, 28)
                    .padding(.top, 12)
                    .frame(height: 72, alignment: .top)
                }
                .frame(height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.groupRim, lineWidth: 0.5))
                .padding(2)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? accent.accent : .clear, lineWidth: 2))
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.text : Theme.sub)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var title: String {
        switch mode {
        case .system: return L10n.Settings.followSystem
        case .light: return L10n.Settings.light
        case .dark: return L10n.Settings.dark
        }
    }

    private func window(light: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            (light ? Color.white : Color(red: 0.173, green: 0.173, blue: 0.18))
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(light ? Color(white: 0.9) : Color(white: 0.23)).frame(width: 40, height: 5)
                Capsule().fill(accent.accent).frame(width: 28, height: 5)
            }
            .padding(.leading, 8)
            .padding(.top, 9)
        }
        .frame(height: 60)
    }
}

// MARK: - Menu bar

struct MenubarSettingsPage: View {
    var settings = SettingsStore.shared
    @State private var dragging: Module?

    var body: some View {
        let prefs = settings.prefs
        PageHeader(icon: nil, title: L10n.Sidebar.menubar) {
            WellButton(title: L10n.Settings.restoreDefaults) { settings.resetMenubar() }
        }

        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.Settings.preview).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.sub).padding(.horizontal, 4)
            MenubarPreview()
                .padding(.horizontal, 14)
                .frame(height: 56)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.group))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.groupRim, lineWidth: 0.5))
        }

        SettingsSection(title: L10n.Settings.display) {
            SettingsRow(title: L10n.Settings.displayMode) {
                SegmentedPicker(label: L10n.Settings.displayMode, options: [(DisplayMode.separate, L10n.Settings.separate), (.combined, L10n.Settings.combined)], selection: pref(\.menubar.displayMode))
            }
            SettingsRow(title: L10n.Settings.iconColor) {
                SegmentedPicker(label: L10n.Settings.iconColor, options: [(ColorMode.mono, L10n.Common.mono), (.color, L10n.Common.colored)], selection: pref(\.menubar.iconColor))
            }
            SettingsRow(title: L10n.Settings.colorOnHighLoad) {
                HumToggle(isOn: pref(\.menubar.colorOnHighLoad), label: L10n.Settings.colorOnHighLoad)
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.Settings.modules).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.sub).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(prefs.menubar.order) { m in
                    ModuleRow(module: m)
                        .overlay(alignment: .top) { if m != prefs.menubar.order.first { Hairline() } }
                        .opacity(dragging == m ? 0.4 : 1)
                        .modifier(ReorderModifier(module: m, dragging: $dragging))
                }
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.group))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.groupRim, lineWidth: 0.5))
        }
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

/// What the menu bar looks like with the current settings, at real size.
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
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.chip.opacity(1.4)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Settings.previewA11y(modules.map { MenuBarText.accessibility($0, monitor.snapshot, prefs) }.joined(separator: L10n.A11y.separator)))
    }
}

/// One module: drag handle, name, style picker with live previews, show switch, › to its page.
struct ModuleRow: View {
    let module: Module
    var settings = SettingsStore.shared

    var body: some View {
        let visible = settings.prefs.isVisible(module)
        HStack(spacing: 10) {
            LineIcon(d: Icons.drag, size: 12, lineWidth: 2.4).foregroundStyle(Theme.faint)
                .accessibilityHidden(true)
            IconChip(d: Icons.module(module), size: 24, iconSize: 14, radius: 6)
            Text(module.title).lineLimit(1)
            Spacer(minLength: 6)
            StylePicker(module: module, compact: true)
                .opacity(visible ? 1 : 0.5)
            HumToggle(isOn: Binding(get: { visible }, set: { settings.prefs.setVisible(module, $0) }), label: L10n.Settings.showInMenubarNamed(module.title))
            Button {
                Navigator.shared.page = .menubarModule(module)
            } label: {
                LineIcon(d: Icons.chevronRight, size: 14, lineWidth: 1.8).foregroundStyle(Theme.faint)
                    .frame(width: 22, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Settings.moreSettings(module.title))
        }
        .frame(height: 44)
    }
}

/// Segmented control whose segments are the real menu bar item drawn in each style.
struct StylePicker: View {
    let module: Module
    var compact = false
    var settings = SettingsStore.shared

    var body: some View {
        let prefs = settings.prefs
        let styles = StylePicker.styles(module)
        HStack(spacing: 2) {
            ForEach(Array(styles.enumerated()), id: \.offset) { i, item in
                let on = StylePicker.selectedIndex(module, prefs) == i
                Button {
                    settings.prefs = StylePicker.apply(module, i, to: settings.prefs)
                } label: {
                    MenuBarItemView(module: module, override: StylePicker.apply(module, i, to: prefs))
                        .scaleEffect(compact ? 0.82 : 0.92)
                        .frame(height: compact ? 26 : 30)
                        .padding(.horizontal, compact ? -2 : 2)
                        .foregroundStyle(Theme.text)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(on ? Theme.segOn : .clear)
                                .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.well))
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

// MARK: - Per-module menu bar page

struct MenubarModulePage: View {
    let module: Module
    var settings = SettingsStore.shared
    var monitor = Monitor.shared

    var body: some View {
        let visible = settings.prefs.isVisible(module)
        Button {
            Navigator.shared.page = .menubar
        } label: {
            HStack(spacing: 4) {
                LineIcon(d: Icons.chevronLeft, size: 13, lineWidth: 1.8)
                Text(L10n.Sidebar.menubar)
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.sub)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Settings.backToMenubar)

        PageHeader(icon: Icons.module(module), title: module.title) {
            HStack(spacing: 10) {
                Text(L10n.Settings.showInMenubar).font(.system(size: 13)).foregroundStyle(Theme.sub)
                HumToggle(isOn: Binding(get: { visible }, set: { settings.prefs.setVisible(module, $0) }), label: L10n.Settings.showInMenubar)
            }
        }

        SettingsSection(title: L10n.Settings.menubarGroup) {
            SettingsRow(title: L10n.Settings.iconStyle, height: 48) { StylePicker(module: module) }
            menubarRows
        }
        SettingsSection(title: L10n.Settings.panelGroup) {
            panelRows
        }
    }

    private var counts: [(Int, String)] { [3, 4, 5, 6, 8].map { ($0, L10n.Common.count($0)) } }

    @ViewBuilder private var menubarRows: some View {
        switch module {
        case .cpu:
            toggleRow(L10n.Settings.showValue, \.cpu.showValue)
            SettingsRow(title: L10n.Settings.graphContent) {
                SegmentedPicker(label: L10n.Settings.graphContent, options: [(CPUGraphContent.total, L10n.Settings.totalUsage), (.userSystem, L10n.Settings.userSystem)], selection: pref(\.cpu.graphContent))
            }
            colorRow(\.cpu.color)
        case .gpu:
            toggleRow(L10n.Settings.showValue, \.gpu.showValue)
            SettingsRow(title: L10n.Settings.valueType) {
                SegmentedPicker(label: L10n.Settings.valueType, options: [(GPUValueType.utilization, L10n.Panel.utilization), (.memory, L10n.Panel.vram)], selection: pref(\.gpu.valueType))
            }
            colorRow(\.gpu.color)
        case .memory:
            toggleRow(L10n.Settings.showValue, \.memory.showValue)
            SettingsRow(title: L10n.Settings.valueType) {
                SegmentedPicker(label: L10n.Settings.valueType, options: [(MemoryValueType.percent, L10n.Settings.percent), (.usedGB, L10n.Settings.usedGB)], selection: pref(\.memory.valueType))
            }
            SettingsRow(title: L10n.Settings.color) {
                SegmentedPicker(label: L10n.Settings.color, options: [(MemoryColor.mono, L10n.Common.mono), (.pressure, L10n.Settings.byPressure)], selection: pref(\.memory.color))
            }
        case .network:
            toggleRow(L10n.Settings.showUnit, \.network.showUnit)
            SettingsRow(title: L10n.Settings.order) {
                SegmentedPicker(label: L10n.Settings.order, options: [(NetworkOrder.uploadTop, L10n.Settings.uploadTop), (.downloadTop, L10n.Settings.downloadTop)], selection: pref(\.network.order))
            }
            colorRow(\.network.color)
            SettingsRow(title: L10n.Settings.speedUnit) {
                MenuPill(label: L10n.Settings.speedUnit, options: [(SpeedUnit.auto, L10n.Common.auto), (.bytes, L10n.Settings.unitBytes), (.bits, L10n.Settings.unitBits)], selection: pref(\.network.speedUnit))
            }
        case .disk:
            SettingsRow(title: L10n.Settings.diskContent) {
                SegmentedPicker(label: L10n.Settings.diskContent, options: [(DiskContent.free, L10n.Settings.freeSpace), (.usedPercent, L10n.Settings.usedPercent), (.readWrite, L10n.Settings.readWrite)], selection: pref(\.disk.content))
            }
            SettingsRow(title: L10n.Settings.whichDisk) {
                MenuPill(label: L10n.Settings.whichDisk,
                         options: [("", L10n.Settings.startupDisk)] + monitor.snapshot.disk.volumes.filter { !$0.isRoot }.map { ($0.name, $0.name) },
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
                SegmentedPicker(label: L10n.Settings.color, options: [(TempColor.mono, L10n.Common.mono), (.byTemp, L10n.Settings.byTemperature)], selection: pref(\.sensors.color))
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
            SettingsRow(title: L10n.Network.interface) {
                MenuPill(label: L10n.Network.interface,
                         options: [("", L10n.Common.auto)] + monitor.interfaces.map { ($0.name, "\(PanelText.kindName($0.kind)) · \($0.name)") },
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

    private func toggleRow(_ title: String, _ keyPath: WritableKeyPath<Preferences, Bool>) -> some View {
        SettingsRow(title: title) { HumToggle(isOn: pref(keyPath), label: title) }
    }

    private func colorRow(_ keyPath: WritableKeyPath<Preferences, ColorMode>) -> some View {
        SettingsRow(title: L10n.Settings.color) {
            SegmentedPicker(label: L10n.Settings.color, options: [(ColorMode.mono, L10n.Common.mono), (.color, L10n.Common.colored)], selection: pref(keyPath))
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
        PageHeader(icon: nil, title: L10n.Sidebar.alerts) {
            HStack(spacing: 10) {
                Text(L10n.Settings.alertsEnabled).foregroundStyle(Theme.sub)
                HumToggle(isOn: pref(\.alerts.enabled), label: L10n.Settings.alertsEnabled)
            }
        }
        if authorization == .denied {
            Card {
                HStack {
                    Text(L10n.Settings.notificationsOff).fontWeight(.semibold)
                    Spacer()
                    WellButton(title: L10n.Settings.openNotificationSettings) { openNotificationSettings() }
                }
            }
        }
        SettingsSection(title: L10n.Settings.rules) {
            rule(enabled: \.alerts.cpuOn) {
                Text(L10n.Settings.ruleCPU)
                InlineChoice(label: L10n.Settings.ruleCPU, options: [70, 80, 90, 95].map { (Double($0), "\($0)%") }, selection: pref(\.alerts.cpuThreshold))
                Text(L10n.Settings.ruleFor)
                InlineChoice(label: L10n.Settings.ruleFor, options: [(0.5, L10n.Alerts.seconds(30)), (1, L10n.Alerts.minutes(1)), (2, L10n.Alerts.minutes(2)), (5, L10n.Alerts.minutes(5))], selection: pref(\.alerts.cpuMinutes))
            }
            rule(enabled: \.alerts.memoryOn) {
                Text(L10n.Settings.ruleMemory)
                InlineChoice(label: L10n.Settings.ruleMemory, options: [(MemoryPressure.warning, L10n.Settings.yellow), (.critical, L10n.Settings.red)], selection: pref(\.alerts.memoryLevel))
            }
            rule(enabled: \.alerts.diskOn) {
                Text(L10n.Settings.ruleDisk)
                InlineChoice(label: L10n.Settings.ruleDisk, options: [5, 10, 20, 50].map { (Double($0), "\($0) GB") }, selection: pref(\.alerts.diskFreeGB))
            }
            rule(enabled: \.alerts.batteryOn) {
                Text(L10n.Settings.ruleBattery)
                InlineChoice(label: L10n.Settings.ruleBattery, options: [10, 15, 20, 30].map { (Double($0), "\($0)%") }, selection: pref(\.alerts.batteryPercent))
            }
            rule(enabled: \.alerts.tempOn) {
                Text(L10n.Settings.ruleTemp)
                InlineChoice(label: L10n.Settings.ruleTemp, options: [85, 90, 95, 100].map { (Double($0), Format.temperature(Double($0), unit: unit, showUnit: true)) }, selection: pref(\.alerts.tempThreshold))
            }
            rule(enabled: \.alerts.networkOn) {
                Text(L10n.Settings.ruleNetwork)
            }
        }
        .opacity(a.enabled ? 1 : 0.5)
        .disabled(!a.enabled)

        SettingsSection(title: L10n.Settings.delivery) {
            SettingsRow(title: L10n.Settings.notificationStyle) {
                WellButton(title: L10n.Settings.changeInSystemSettings) { openNotificationSettings() }
            }
            SettingsRow(title: L10n.Settings.playSound) { HumToggle(isOn: pref(\.alerts.sound), label: L10n.Settings.playSound) }
            SettingsRow(title: L10n.Settings.colorMenubar) { HumToggle(isOn: pref(\.alerts.colorMenubar), label: L10n.Settings.colorMenubar) }
        }
        .opacity(a.enabled ? 1 : 0.5)
        .disabled(!a.enabled)
        .task { await refreshAuthorization() }
    }

    private func rule<Content: View>(enabled keyPath: WritableKeyPath<Preferences, Bool>, @ViewBuilder sentence: () -> Content) -> some View {
        let on = settings.prefs[keyPath: keyPath]
        return HStack(spacing: 6) {
            HStack(spacing: 6) { sentence() }
                .opacity(on ? 1 : 0.45)
            Spacer(minLength: 8)
            HumToggle(isOn: pref(keyPath), label: L10n.Settings.ruleToggle)
        }
        .frame(minHeight: 44)
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

/// An accent-tinted value inside a sentence that opens a menu ("高于 [90%]").
struct InlineChoice<Value: Hashable>: View {
    var label: String
    var options: [(Value, String)]
    @Binding var selection: Value
    @Environment(\.accent) private var accent

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                Button(o.1) { selection = o.0 }
            }
        } label: {
            Text(options.first { $0.0 == selection }?.1 ?? "")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent.tintText)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(accent.tint))
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
        PageHeader(icon: nil, title: L10n.Sidebar.about)
        Card(padding: EdgeInsets(top: 24, leading: 20, bottom: 24, trailing: 20)) {
            HStack(spacing: 16) {
                AppMark(size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.App.name).font(.system(size: 22, weight: .bold))
                    Text(L10n.App.version(SystemInfo.appVersion)).foregroundStyle(Theme.sub)
                }
                Spacer()
            }
        }
        SettingsSection(title: L10n.Settings.selfUsage) {
            SettingsRow(title: L10n.Module.cpu) { Text(Format.percentValue(s.selfCPU)).fontWeight(.semibold).monospacedDigit() }
            SettingsRow(title: L10n.Module.memory) { Text(Format.memory(s.selfMemory)).fontWeight(.semibold).monospacedDigit() }
            SettingsRow(title: L10n.Settings.refreshInterval) {
                Text(L10n.Settings.seconds(Int(SettingsStore.shared.prefs.general.refreshInterval))).fontWeight(.semibold)
            }
        }
        SettingsSection(title: L10n.Settings.thisMac) {
            SettingsRow(title: L10n.Settings.chip) { Text(SystemInfo.chipName).fontWeight(.semibold) }
            SettingsRow(title: L10n.Panel.cores) {
                Text(PanelText.coreSplit() ?? L10n.Panel.coreCount(SystemInfo.coreCount)).fontWeight(.semibold)
            }
            SettingsRow(title: L10n.Memory.total) { Text(Format.memory(SystemInfo.physicalMemory)).fontWeight(.semibold) }
            SettingsRow(title: L10n.Settings.macOS) { Text(ProcessInfo.processInfo.operatingSystemVersionString).fontWeight(.semibold).lineLimit(1) }
        }
        HStack {
            Spacer()
            WellButton(title: L10n.Menu.quit) { NSApp.terminate(nil) }
        }
    }
}
