import AppKit
import SwiftUI

/// The "合并成一项" dropdown, for a glance: every module, in the order of the chips in 设置 › 菜单栏.
/// The first one in the menu bar, which the merged item shows, is a big reading with its last minute; the others follow one to a row (name, a small picture, reading); then the busiest
/// app and what keeps the Mac awake. Every row opens its details beside the dropdown.
struct CombinedPanel: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    var alerts = Alerts.shared
    var details = CombinedDetails.shared

    var body: some View {
        let s = monitor.snapshot
        let prefs = settings.prefs
        let _ = monitor.tick
        let bar = prefs.menubar
        let modules = prefs.combinedModules.filter { hasReading($0, s) }
        let busiest = bar.combinedTop ? (bar.combinedTopByMemory ? s.processes.byMemory : s.processes.byCPU).first : nil
        let awake = bar.combinedSleep ? details.blockers : []
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(L10n.App.name).ui(16, 600).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                // The same three places as every module's dropdown, here for the whole app.
                HStack(spacing: 2) {
                    HeaderButton(d: Icons.overview, label: L10n.Combined.openRin) { MainWindowController.shared.show(.overview) }
                    HeaderButton(d: Icons.gear, lineWidth: 1.3, label: L10n.Sidebar.settings) { MainWindowController.shared.show(.settings) }
                    HeaderButton(d: Icons.power, label: L10n.Panel.quitRin) { NSApp.terminate(nil) }
                }
                .padding(.trailing, -6)
            }
            .frame(height: 26)
            // Only something that needs attention earns a line here.
            if bar.combinedStatus, let event = alerts.current {
                Button { alerts.show(event) } label: { Attention(text: AlertText.headline(event)).ui(12).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
            }
            if let hero = modules.first {
                CombinedHero(module: hero).padding(.top, 10)
            }
            if modules.count > 1 {
                VStack(spacing: 0) {
                    ForEach(modules.dropFirst()) { ModuleLine(module: $0) }
                }
                .padding(.top, 10)
            }
            if busiest != nil || !awake.isEmpty {
                Hairline().padding(.vertical, 8)
                VStack(spacing: 0) {
                    if let busiest {
                        CombinedLine(label: L10n.Combined.topUsageRow, detail: .top) {
                            AppIcon(process: busiest)
                            Text(busiest.name).ui(14).lineLimit(1)
                            Text(bar.combinedTopByMemory ? L10n.Combined.topMemoryValue(Format.memory(busiest.memory)) : L10n.Combined.topCPUValue(Format.percentValue(busiest.cpu)))
                                .ui(14).foregroundStyle(Theme.sub).fixedSize()
                        }
                    }
                    if let first = awake.first {
                        CombinedLine(label: L10n.Combined.sleepRow, detail: .sleep) {
                            if let icon = Self.icon(first) { AppIcon(image: icon) }
                            Text(Self.name(first)).ui(14).lineLimit(1)
                            if awake.count > 1 { Text(L10n.Combined.sleepMore(awake.count)).ui(14).foregroundStyle(Theme.sub).fixedSize() }
                        }
                    }
                }
                .padding(.bottom, -8)
            }
        }
        .task(id: bar.combinedSleep) {
            guard bar.combinedSleep else { return }
            // Assertions come and go with playback and syncing; re-read while the dropdown is open.
            while !Task.isCancelled {
                details.blockers = Self.appBlockers()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onAppear { if RenderContext.offscreen { details.blockers = Self.appBlockers() } }
        // Nothing holding the Mac awake any more leaves nothing to detail.
        .onChange(of: awake.isEmpty) { _, empty in
            if empty && details.selection == .sleep { PanelController.shared.setDetail(nil) }
        }
    }

    /// Apps and processes holding the Mac awake; not macOS itself, and not Rin's own keep-awake.
    static func appBlockers() -> [SleepBlocker] {
        let me = ProcessInfo.processInfo.processIdentifier
        return SleepBlocker.read().filter { b in
            switch b.owner {
            case .app(let app): return app.processIdentifier != me
            case .process: return true
            case .system: return false
            }
        }
    }

    static func name(_ b: SleepBlocker) -> String {
        switch b.owner {
        case .app(let app): return app.localizedName ?? ""
        case .process(let name, _): return name
        case .system: return L10n.Sleep.macOS
        }
    }

    /// Whoever it is, as they look; macOS as the Finder.
    static func icon(_ b: SleepBlocker) -> NSImage? {
        switch b.owner {
        case .app(let app): return app.icon
        case .process: return AppIcon.image(bundle: nil)
        case .system: return AppIcon.image(bundle: "/System/Library/CoreServices/Finder.app")
        }
    }

    /// A module with nothing to show leaves no row: no battery, no device reporting one.
    private func hasReading(_ m: Module, _ s: Snapshot) -> Bool {
        switch m {
        case .battery: return s.battery.hasBattery
        case .bluetooth: return !s.bluetooth.withBattery.isEmpty
        case .sensors: return s.sensors.cpuAverage != nil
        default: return true
        }
    }
}

// MARK: - Readings

/// What each module shows in the combined dropdown.
private enum CombinedReading {
    static func name(_ m: Module) -> String { m.title }

    static func lowestDevice(_ s: Snapshot) -> BluetoothDevice? {
        s.bluetooth.withBattery.min { ($0.level ?? 1) < ($1.level ?? 1) }
    }

    /// The reading as figure and unit (the hero shows them apart).
    static func value(_ m: Module, _ s: Snapshot, _ prefs: Preferences) -> (String, String?) {
        switch m {
        case .cpu: return (Format.percentNumber(s.cpu.total), "%")
        case .gpu: return (Format.percentNumber(s.gpu.utilization), "%")
        case .memory: return (Format.percentNumber(s.memory.usedFraction), "%")
        case .disk: return (s.disk.root.map { Format.percentNumber($0.usedFraction) } ?? L10n.Common.dash, "%")
        case .battery: return (Format.percentNumber(s.battery.level), "%")
        case .sensors:
            let unit = prefs.general.temperatureUnit
            return (s.sensors.cpuAverage.map { Format.temperatureNumber($0, unit: unit) } ?? L10n.Common.dash, Format.temperatureSymbol(unit))
        case .bluetooth: return (lowestDevice(s)?.level.map(Format.percentNumber) ?? L10n.Common.dash, "%")
        case .network:
            let p = Format.rateParts(s.network.down, unit: prefs.network.speedUnit)
            return (s.network.connected ? p.0 : L10n.Common.dash, s.network.connected ? p.1 : nil)
        }
    }

    static func isLow(_ m: Module, _ s: Snapshot, _ prefs: Preferences) -> Bool {
        switch m {
        case .battery: return s.battery.level <= 0.2 && !s.battery.onAC
        case .bluetooth: return lowestDevice(s).map { BluetoothText.isLow($0, prefs) } ?? false
        default: return false
        }
    }

    /// The last minute: a line for most, two mirrored for traffic; nothing for Bluetooth, whose level barely moves.
    @ViewBuilder static func chart(_ m: Module, color: Color, width: CGFloat, fill: Bool, height: CGFloat) -> some View {
        let h = Monitor.shared.history
        switch m {
        case .cpu: spark(h.points(.cpu, range: .m5), color, width, fill, height)
        case .gpu: spark(h.points(.gpu, range: .m5), color, width, fill, height)
        case .memory: spark(h.points(.memory, range: .m5), color, width, fill, height)
        case .sensors: spark(h.points(.cpuTemp, range: .m5), color, width, fill, height)
        case .battery: spark(h.points(.battery, range: .m5), color, width, fill, height)
        case .network: mirrored(h.points(.netDown, range: .m5), h.points(.netUp, range: .m5), color, width, floor: 10_000, height)
        case .disk: mirrored(h.points(.diskRead, range: .m5), h.points(.diskWrite, range: .m5), color, width, floor: 1_000_000, height)
        case .bluetooth: Color.clear.frame(height: height)
        }
    }

    private static func spark(_ points: [ChartPoint], _ color: Color, _ width: CGFloat, _ fill: Bool, _ height: CGFloat) -> some View {
        ConsoleChart(kind: .area, series: ChartSeries.line(points, color, width: width, fill: fill), span: 60, maxValue: 100, height: height, midline: false)
    }

    /// Up against its own last-minute peak, down against its own; a floor keeps a trickle low.
    private static func mirrored(_ top: [ChartPoint], _ bottom: [ChartPoint], _ color: Color, _ width: CGFloat, floor: Double, _ height: CGFloat) -> some View {
        let from = Date().addingTimeInterval(-60)
        func peak(_ points: [ChartPoint]) -> Double {
            ConsoleChart.niceMax(max(points.filter { $0.date >= from }.map(\.value).max() ?? 0, floor) * 1.1)
        }
        return ConsoleChart(kind: .mirroredArea, series: ChartSeries.mirrored(top, color, bottom, color, lineWidth: width),
                            span: 60, maxValue: peak(top), bottomMax: peak(bottom), height: height)
    }
}

/// The first module, large: its name, the reading, its last minute edge to edge under them.
private struct CombinedHero: View {
    let module: Module
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    var details = CombinedDetails.shared
    @State private var hovering = false

    var body: some View {
        let s = monitor.snapshot
        let prefs = settings.prefs
        let selected = details.selection == .module(module)
        let v = CombinedReading.value(module, s, prefs)
        let low = CombinedReading.isLow(module, s, prefs)
        let line = low ? Theme.danger : module == .battery ? Theme.batteryLevel(s.battery, lead: false) : Theme.hue(module) ?? Theme.mid
        Button { PanelController.shared.toggleDetail(.module(module)) } label: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    SmallLabel(text: CombinedReading.name(module))
                    BigValue(value: v.0, unit: v.1, size: BigValue.panelLead, color: low ? Theme.danger : Theme.text)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                CombinedReading.chart(module, color: line, width: 1.5, fill: true, height: 62)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            }
            .padding(.top, 8)
            .overlay(alignment: .trailing) { DetailChevron(visible: hovering || selected).padding(.trailing, 3) }
            .background { if hovering { Theme.lgHover } }
            .hoverAnimation(hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -20)
        .onHover { hovering = $0 }
        .accessibilityHint(L10n.Combined.showDetails)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Name, a small picture (a bar for how full, a curve for a rate), the reading; the row opens the module's details.
private struct ModuleLine: View {
    let module: Module
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    var details = CombinedDetails.shared
    @State private var hovering = false

    /// One column for all the names, as wide as the longest in this language.
    private static let nameWidth: CGFloat = max(52, Module.allCases.map {
        ($0.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14)]).width.rounded(.up)
    }.max() ?? 0)

    var body: some View {
        let s = monitor.snapshot
        let prefs = settings.prefs
        let selected = details.selection == .module(module)
        Button { PanelController.shared.toggleDetail(.module(module)) } label: {
            HStack(spacing: 12) {
                Text(CombinedReading.name(module)).ui(14).foregroundStyle(Theme.sub).lineLimit(1).frame(width: Self.nameWidth, alignment: .leading)
                picture(s, prefs).frame(maxWidth: .infinity).accessibilityHidden(true)
                reading(s, prefs).frame(width: 112, alignment: .trailing)
            }
            .frame(height: 40)
            .detailRow(selected: selected, hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.Combined.showDetails)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func picture(_ s: Snapshot, _ prefs: Preferences) -> some View {
        switch module {
        case .memory: LevelBar(fraction: s.memory.usedFraction, color: Theme.color(for: .memory))
        case .disk: LevelBar(fraction: s.disk.root?.usedFraction ?? 0, color: Theme.color(for: .disk))
        case .battery: LevelBar(fraction: s.battery.level, color: Theme.batteryLevel(s.battery, lead: false))
        case .bluetooth:
            LevelBar(fraction: CombinedReading.lowestDevice(s)?.level ?? 0, color: CombinedReading.isLow(module, s, prefs) ? Theme.danger : Theme.mid)
        case .sensors: TempBar(celsius: s.sensors.cpuAverage ?? 0, color: Theme.color(for: .sensors))
        case .network: CombinedReading.chart(module, color: Theme.color(for: .network), width: 1.25, fill: true, height: 26)
        case .cpu, .gpu: CombinedReading.chart(module, color: Theme.color(for: module), width: 1.25, fill: true, height: 24)
        }
    }

    @ViewBuilder private func reading(_ s: Snapshot, _ prefs: Preferences) -> some View {
        if module == .network {
            // Both directions of one reading, so they look the same.
            let n = s.network, unit = prefs.network.speedUnit
            if n.connected {
                VStack(alignment: .trailing, spacing: 0) {
                    Reading(text: MenuBarText.downArrow + " " + Format.rate(n.down, unit: unit), size: 12)
                    Reading(text: MenuBarText.upArrow + " " + Format.rate(n.up, unit: unit), size: 12)
                }
            } else {
                Text(L10n.Common.dash).ui(14, 500)
            }
        } else if module == .sensors {
            // The temperature and the fan, as the menu bar shows them.
            let v = CombinedReading.value(module, s, prefs)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(v.0).ui(14, 500)
                    Text(verbatim: "°").ui(14).foregroundStyle(Theme.sub)
                }
                if let f = s.sensors.fans.first { Reading(text: Format.rpm(f.rpm)) }
            }
            .lineLimit(1)
            .fixedSize()
        } else {
            let v = CombinedReading.value(module, s, prefs)
            Reading(text: v.0 + (v.1 == "%" ? "%" : v.1.map { " " + $0 } ?? ""), color: CombinedReading.isLow(module, s, prefs) ? Theme.danger : Theme.text)
        }
    }
}

/// "占用最多   Xcode  CPU 38.2%": a grey label and who it is, on a row that opens its details.
private struct CombinedLine<Value: View>: View {
    var label: String
    var detail: CombinedDetail
    @ViewBuilder var value: Value
    var details = CombinedDetails.shared
    @State private var hovering = false

    var body: some View {
        let selected = details.selection == detail
        Button { PanelController.shared.toggleDetail(detail) } label: {
            HStack(spacing: 8) {
                Text(label).ui(14).foregroundStyle(Theme.sub).lineLimit(1).fixedSize()
                HStack(spacing: 8) { value }.frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: 38)
            .detailRow(selected: selected, hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.Combined.showDetails)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The small › that says a row opens something, only while it is under the pointer or open.
private struct DetailChevron: View {
    var visible: Bool

    var body: some View {
        LineIcon(d: Icons.chevronRight, size: 10, lineWidth: 1.7).foregroundStyle(Theme.sub).opacity(visible ? 0.8 : 0).accessibilityHidden(true)
    }
}

private extension View {
    /// A row that opens details: inset 14 from the sides, grey under the pointer, raised while its details are open.
    func detailRow(selected: Bool, hovering: Bool) -> some View {
        padding(.horizontal, 14)
            .overlay(alignment: .trailing) { DetailChevron(visible: hovering || selected).padding(.trailing, 3) }
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.rowSelected)
                        .shadow(color: Theme.raisedShadowNear, radius: 1.5, x: 0, y: 1)
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).inset(by: -0.25).stroke(Theme.raisedRing, lineWidth: 0.5))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.lgHover)
                }
            }
            .padding(.horizontal, -14)
            .hoverAnimation(hovering)
            .contentShape(Rectangle())
    }
}

// MARK: - Details

/// What the combined dropdown can open beside itself.
enum CombinedDetail: Hashable {
    case module(Module)
    case top
    case sleep
}

/// The combined dropdown's open details, and what its rows and those details share.
@Observable
final class CombinedDetails {
    static let shared = CombinedDetails()

    var selection: CombinedDetail?
    /// Apps holding the Mac awake, re-read while the dropdown is open.
    var blockers: [SleepBlocker] = []
}

/// The panel beside the combined dropdown. A module shows what its own dropdown shows; quitting
/// stays on the dropdown.
struct CombinedDetailRoot: View {
    var details = CombinedDetails.shared

    var body: some View {
        PanelChrome {
            switch details.selection {
            case .module(let m): ModulePanel(module: m).environment(\.panelQuits, false)
            case .top: TopUsageDetail()
            case .sleep: SleepDetail()
            case nil: EmptyView()
            }
        }
    }
}

/// A detail's title, a note beside it, and the page it leads to.
private struct DetailHeader: View {
    var title: String
    var subtitle: String? = nil
    var icon: String
    var label: String
    var action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).ui(16, 600).accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).ui(13).foregroundStyle(Theme.sub).lineLimit(1) }
            }
            Spacer(minLength: 0)
            HeaderButton(d: icon, label: label, action: action).padding(.trailing, -6)
        }
        .frame(height: 26)
    }
}

/// The busiest apps by CPU and by memory.
private struct TopUsageDetail: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared
    var quitCenter = QuitCenter.shared

    var body: some View {
        let p = monitor.snapshot.processes
        let _ = monitor.tick
        DetailHeader(title: L10n.Combined.topUsageRow, icon: Icons.processes, label: L10n.Combined.openProcesses) {
            MainWindowController.shared.showProcesses(sortedBy: settings.prefs.menubar.combinedTopByMemory ? .memory : .cpu)
        }
        HeadRow(title: L10n.Module.cpu).padding(.top, 14)
        ProcessTable(processes: Array(p.byCPU.prefix(5)), value: { Format.percentValue($0.cpu) }, minRows: 5)
        HeadRow(title: L10n.Module.memory).padding(.top, 16)
        ProcessTable(processes: Array(p.byMemory.prefix(5)), value: { Format.memory($0.memory) }, minRows: 5)
        if let toast = quitCenter.toast { QuitToast(toast: toast).padding(.top, 12) }
    }
}

/// Who is holding the Mac awake, why and for how long.
private struct SleepDetail: View {
    var details = CombinedDetails.shared

    var body: some View {
        let now = Date()
        DetailHeader(title: L10n.Combined.sleepRow, icon: Icons.sleep, label: L10n.Combined.openSleep) {
            MainWindowController.shared.show(.sleep)
        }
        VStack(spacing: 0) { ForEach(details.blockers) { row($0, now: now) } }
            .padding(.top, 10)
    }

    private func row(_ b: SleepBlocker, now: Date) -> some View {
        let name = CombinedPanel.name(b)
        return HStack(spacing: 10) {
            if let icon = CombinedPanel.icon(b) { AppIcon(image: icon, size: 22) }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).ui(14).lineLimit(1)
                Text(b.reason).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(SleepPage.held(now.timeIntervalSince(b.since))).ui(14, 500).lineLimit(1).fixedSize()
            // Holds its column even without a button, so the times line up.
            ZStack {
                if case .app(let app) = b.owner {
                    IconAction(d: Icons.openExternal, label: L10n.Sleep.openNamed(name), size: 24) { app.activate() }
                }
            }
            .frame(width: 24, height: 24)
        }
        .frame(height: 44)
        .accessibilityElement(children: .combine)
    }
}
