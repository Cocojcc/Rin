import SwiftUI

/// How loud a menu bar item should be. Color in the menu bar is reserved for warnings.
enum BarTone {
    case normal, warn, crit, dim

    var color: Color? {
        switch self {
        case .normal: return nil
        case .warn: return Color(nsColor: Theme.barWarn)
        case .crit: return Color(nsColor: Theme.barCrit)
        case .dim: return .primary.opacity(0.45)
        }
    }

    var emphasized: Bool { self == .warn || self == .crit }
}

/// Fixed-width text so the item doesn't change width as numbers change.
struct FixedText: View {
    var text: String
    var template: String
    var font: Font
    var alignment: Alignment = .trailing

    var body: some View {
        Text(template).font(font).hidden()
            .overlay(alignment: alignment) { Text(text).font(font).lineLimit(1).fixedSize() }
    }
}

enum BarFont {
    static func value(_ emphasized: Bool = false) -> Font { .system(size: 13, weight: emphasized ? .semibold : .regular).monospacedDigit() }
    static let stack = Font.system(size: 9, weight: .light).monospacedDigit()
    static let label = Font.system(size: 7, weight: .light)
    static let compactValue = Font.system(size: 12, weight: .regular).monospacedDigit()
}

/// Mini graph tile (28 × 16) used by the CPU and GPU "graph" style.
struct GraphTile: View {
    var values: [Double]
    var secondary: [Double]? = nil
    var color: Color
    var width: CGFloat = 28
    var height: CGFloat = 16

    var body: some View {
        Sparkline(values: values, color: color, lineWidth: 1.25, fillOpacity: 0.25, secondary: secondary, secondaryColor: secondary == nil ? nil : Theme.sys, minCount: 30)
            .frame(width: width, height: height)
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Horizontal capsule meter (22 × 10) for memory / disk.
struct PillMeter: View {
    var fraction: Double
    var color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.4), lineWidth: 1)
            .frame(width: 22, height: 10)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(color)
                    .frame(width: max(1, 17 * min(1, max(0, fraction))), height: 5)
                    .padding(.leading, 2.5)
            }
            .accessibilityHidden(true)
    }
}

/// Vertical bar (4 × 14) for the CPU / GPU "bar" style.
struct VerticalMeter: View {
    var fraction: Double
    var color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.4), lineWidth: 1)
            .frame(width: 5, height: 15)
            .overlay(alignment: .bottom) {
                Rectangle().fill(color)
                    .frame(width: 5, height: 15 * min(1, max(0, fraction)))
            }
            .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Ring meter (14 × 14) for memory.
struct RingMeter: View {
    var fraction: Double
    var color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.2), lineWidth: 2.2)
            Circle().trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 13, height: 13)
        .accessibilityHidden(true)
    }
}

/// Small Latin label over a value, the "two-line" style (7 pt light + 12 pt regular).
struct TwoLineValue: View {
    var label: String
    var value: String
    var template: String
    var tone: BarTone = .normal

    var body: some View {
        VStack(spacing: -1) {
            Text(label).font(BarFont.label).kerning(0.3)
            FixedText(text: value, template: template, font: BarFont.compactValue, alignment: .center)
                .fontWeight(tone.emphasized ? .semibold : .regular)
        }
        .frame(height: 18)
    }
}

/// Two stacked numbers (9 pt light, 10 pt rows), the network / disk read-write layout.
struct StackedValues: View {
    var top: String
    var bottom: String
    var template: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            FixedText(text: top, template: template, font: BarFont.stack).frame(height: 10)
            FixedText(text: bottom, template: template, font: BarFont.stack).frame(height: 10)
        }
    }
}

// MARK: - Per-module items

struct MenuBarItemView: View {
    let module: Module
    /// Used by the settings previews to draw a style other than the saved one.
    var override: Preferences? = nil
    var monitor = Monitor.shared
    var settings = SettingsStore.shared

    var body: some View {
        content
            .padding(.horizontal, 5)
            .frame(maxHeight: .infinity)
            .foregroundStyle(tone.color ?? .primary)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MenuBarText.accessibility(module, monitor.snapshot, prefs))
    }

    private var prefs: Preferences { override ?? settings.prefs }
    private var s: Snapshot { monitor.snapshot }
    private var globallyColored: Bool { prefs.menubar.iconColor == .color }

    private var tone: BarTone { MenuBarText.tone(module, s, prefs) }

    @ViewBuilder private var content: some View {
        switch module {
        case .cpu: cpu
        case .gpu: gpu
        case .memory: memory
        case .network: network
        case .disk: disk
        case .battery: battery
        case .sensors: sensors
        }
    }

    private func dataColor(_ colored: Bool, _ c: Color) -> Color {
        tone.color ?? (colored || globallyColored ? c : .primary)
    }

    // CPU
    @ViewBuilder private var cpu: some View {
        let p = prefs.cpu
        let value = Format.percent(s.cpu.total)
        let color = dataColor(p.color == .color, Theme.cpu)
        switch p.style {
        case .graph:
            HStack(spacing: 4) {
                let history = monitor.history
                let _ = monitor.tick
                if p.graphContent == .userSystem {
                    GraphTile(values: history.latest(.cpuUser, seconds: 60).map { $0 / 100 },
                              secondary: history.latest(.cpuSystem, seconds: 60).map { $0 / 100 }, color: color)
                } else {
                    GraphTile(values: history.latest(.cpu, seconds: 60).map { $0 / 100 }, color: color)
                }
                if p.showValue { FixedText(text: value, template: "100%", font: BarFont.value(tone.emphasized)) }
            }
        case .bar:
            HStack(spacing: 4) {
                VerticalMeter(fraction: s.cpu.total, color: color)
                if p.showValue { FixedText(text: value, template: "100%", font: BarFont.value(tone.emphasized)) }
            }
        case .iconValue:
            HStack(spacing: 3) {
                LineIcon(d: Icons.cpuMenubar, size: 16, lineWidth: 1.4).foregroundStyle(color)
                if p.showValue { FixedText(text: value, template: "100%", font: BarFont.value(tone.emphasized)) }
            }
        case .twoLine:
            TwoLineValue(label: Module.cpu.compactLabel, value: value, template: "100%", tone: tone)
        }
    }

    // GPU
    @ViewBuilder private var gpu: some View {
        let p = prefs.gpu
        let value = p.valueType == .memory ? MenuBarText.gigabytes(s.gpu.memoryUsed) : Format.percent(s.gpu.utilization)
        let template = p.valueType == .memory ? "99.9G" : "100%"
        let color = dataColor(p.color == .color, Theme.gpu)
        switch p.style {
        case .graph:
            HStack(spacing: 4) {
                let _ = monitor.tick
                GraphTile(values: monitor.history.latest(.gpu, seconds: 60).map { $0 / 100 }, color: color)
                if p.showValue { FixedText(text: value, template: template, font: BarFont.value()) }
            }
        case .bar:
            HStack(spacing: 4) {
                VerticalMeter(fraction: s.gpu.utilization, color: color)
                if p.showValue { FixedText(text: value, template: template, font: BarFont.value()) }
            }
        case .iconValue:
            HStack(spacing: 3) {
                LineIcon(d: Icons.gpu, size: 16, lineWidth: 1.4).foregroundStyle(color)
                if p.showValue { FixedText(text: value, template: template, font: BarFont.value()) }
            }
        case .twoLine:
            TwoLineValue(label: Module.gpu.compactLabel, value: value, template: template)
        }
    }

    // Memory
    @ViewBuilder private var memory: some View {
        let p = prefs.memory
        let value = p.valueType == .usedGB ? MenuBarText.gigabytes(s.memory.used, binary: true) : Format.percent(s.memory.usedFraction)
        let template = p.valueType == .usedGB ? "99.9G" : "100%"
        let color: Color = {
            if let t = tone.color { return t }
            if p.color == .pressure {
                switch s.memory.pressure {
                case .normal: return Theme.ok
                case .warning: return Theme.sys
                case .critical: return Theme.low
                }
            }
            return globallyColored ? Theme.mem : .primary
        }()
        switch p.style {
        case .bar:
            HStack(spacing: 4) {
                PillMeter(fraction: s.memory.usedFraction, color: color)
                if p.showValue { FixedText(text: value, template: template, font: BarFont.value(tone.emphasized)) }
            }
        case .ring:
            HStack(spacing: 4) {
                RingMeter(fraction: s.memory.usedFraction, color: color)
                if p.showValue { FixedText(text: value, template: template, font: BarFont.value(tone.emphasized)) }
            }
        case .iconValue:
            HStack(spacing: 3) {
                LineIcon(d: Icons.memory, size: 16, lineWidth: 1.4).foregroundStyle(color)
                if p.showValue { FixedText(text: value, template: template, font: BarFont.value(tone.emphasized)) }
            }
        case .twoLine:
            TwoLineValue(label: Module.memory.compactLabel, value: value, template: template, tone: tone)
        }
    }

    // Network
    @ViewBuilder private var network: some View {
        let p = prefs.network
        let n = s.network
        let offline = !n.connected
        let colored = (p.color == .color || globallyColored) && !offline
        let upColor: Color = colored ? Theme.up : .primary
        let downColor: Color = colored ? Theme.down : .primary
        let upText = offline ? L10n.Common.dash : (p.showUnit ? Format.rate(n.up, unit: p.speedUnit) : Format.rateCompact(n.up, unit: p.speedUnit))
        let downText = offline ? L10n.Common.dash : (p.showUnit ? Format.rate(n.down, unit: p.speedUnit) : Format.rateCompact(n.down, unit: p.speedUnit))
        let template = p.showUnit ? "999 KB/s" : "999K"
        let upTop = p.order == .uploadTop
        switch p.style {
        case .arrows:
            HStack(spacing: 3) {
                NetArrows(upColor: upColor, downColor: downColor, upOnTop: upTop, height: 20)
                    .opacity(offline ? 0.45 : 1)
                StackedValues(top: upTop ? upText : downText, bottom: upTop ? downText : upText, template: template)
            }
        case .dots:
            HStack(spacing: 3) {
                VStack(spacing: 4) {
                    Circle().fill(upTop ? upColor : downColor).frame(width: 4, height: 4)
                    Circle().fill(upTop ? downColor : upColor).frame(width: 4, height: 4)
                }
                .opacity(offline ? 0.45 : (colored ? 1 : 0.7))
                StackedValues(top: upTop ? upText : downText, bottom: upTop ? downText : upText, template: template)
            }
        case .singleLine:
            let down = offline ? L10n.Common.dash : Format.rateCompact(n.down, unit: p.speedUnit)
            let up = offline ? L10n.Common.dash : Format.rateCompact(n.up, unit: p.speedUnit)
            HStack(spacing: 4) {
                HStack(spacing: 1) {
                    Text(MenuBarText.downArrow).foregroundStyle(colored ? Theme.down : .primary.opacity(0.55))
                    FixedText(text: down, template: "999K", font: .system(size: 12).monospacedDigit())
                }
                HStack(spacing: 1) {
                    Text(MenuBarText.upArrow).foregroundStyle(colored ? Theme.up : .primary.opacity(0.55))
                    FixedText(text: up, template: "999K", font: .system(size: 12).monospacedDigit())
                }
            }
            .font(.system(size: 11))
        case .iconOnly:
            LineIcon(d: Icons.network, size: 16, lineWidth: 1.5)
                .opacity(offline ? 0.45 : 1)
        }
    }

    // Disk
    @ViewBuilder private var disk: some View {
        let p = prefs.disk
        let volume = MenuBarText.volume(s.disk, prefs.disk.volume)
        let free = volume.map { MenuBarText.gigabytes(UInt64(max(0, $0.available)), decimal: true) } ?? L10n.Common.dash
        let used = volume.map { Format.percent($0.usedFraction) } ?? L10n.Common.dash
        let color = dataColor(false, Theme.disk)
        switch p.style {
        case .iconValue:
            HStack(spacing: 3) {
                LineIcon(d: Icons.disk, size: 14, lineWidth: 1.4).foregroundStyle(color)
                switch p.content {
                case .free: FixedText(text: free, template: "999G", font: BarFont.value())
                case .usedPercent: FixedText(text: used, template: "100%", font: BarFont.value())
                case .readWrite: StackedValues(top: MenuBarText.readShort(s.disk.read), bottom: MenuBarText.writeShort(s.disk.write), template: "R 999M")
                }
            }
        case .bar:
            HStack(spacing: 4) {
                PillMeter(fraction: volume?.usedFraction ?? 0, color: color)
                FixedText(text: p.content == .free ? free : used, template: p.content == .free ? "999G" : "100%", font: BarFont.value())
            }
        case .readWrite:
            StackedValues(top: MenuBarText.readShort(s.disk.read), bottom: MenuBarText.writeShort(s.disk.write), template: "R 999M")
        case .twoLine:
            TwoLineValue(label: Module.disk.compactLabel, value: p.content == .free ? free : used, template: p.content == .free ? "999G" : "100%")
        }
    }

    // Battery
    @ViewBuilder private var battery: some View {
        let p = prefs.battery
        let b = s.battery
        let low = p.colorWhenLow && b.level <= 0.2 && !b.isCharging && !b.onAC
        let fill: Color = low ? Color(nsColor: Theme.barCrit) : (globallyColored ? Theme.bat : .primary)
        let value = Format.percent(b.level)
        let timeLeft: String? = p.showTimeRemaining ? (b.isCharging ? b.minutesToFull : b.minutesToEmpty).map { Format.clockDuration(minutes: $0) } : nil
        let glyph = BatteryGlyph(level: b.level, charging: p.showBolt && b.isCharging, fill: fill)
        Group {
            switch p.style {
            case .iconPercent:
                HStack(spacing: 4) {
                    glyph
                    FixedText(text: value, template: "100%", font: BarFont.value())
                    if let timeLeft { Text(timeLeft).font(.system(size: 11).monospacedDigit()).opacity(0.7) }
                }
            case .iconOnly:
                glyph
            case .percentOnly:
                HStack(spacing: 4) {
                    FixedText(text: value, template: "100%", font: BarFont.value())
                    if let timeLeft { Text(timeLeft).font(.system(size: 11).monospacedDigit()).opacity(0.7) }
                }
            case .twoLine:
                TwoLineValue(label: Module.battery.compactLabel, value: value, template: "100%")
            }
        }
    }

    // Sensors
    @ViewBuilder private var sensors: some View {
        let p = prefs.sensors
        let unit = prefs.general.temperatureUnit
        let celsius = MenuBarText.sensorValue(s.sensors, p.sensor)
        let value = celsius.map { Format.temperature($0, unit: unit) } ?? L10n.Common.dash
        let iconColor: Color = {
            if let t = tone.color { return t }
            if p.color == .byTemp, let c = celsius {
                return c >= 80 ? Theme.low : c >= 60 ? Theme.sys : Theme.ok
            }
            return globallyColored ? Theme.temp : .primary
        }()
        switch p.style {
        case .iconTemp:
            HStack(spacing: 2) {
                LineIcon(d: tone == .crit ? Icons.sensorsHot : Icons.sensors, size: 16, lineWidth: 1.4).foregroundStyle(iconColor)
                FixedText(text: value, template: "100°", font: BarFont.value(tone.emphasized))
            }
        case .tempOnly:
            FixedText(text: value, template: "100°", font: BarFont.value(tone.emphasized))
                .foregroundStyle(p.color == .byTemp ? iconColor : (tone.color ?? .primary))
        case .fan:
            HStack(spacing: 3) {
                Image(systemName: "fan").font(.system(size: 13)).foregroundStyle(iconColor)
                FixedText(text: s.sensors.fans.first.map { "\(Int($0.rpm))" } ?? L10n.Common.dash, template: "8888", font: BarFont.value())
            }
        case .twoLine:
            TwoLineValue(label: Module.sensors.compactLabel, value: value, template: "100°", tone: tone)
        }
    }
}

/// Everything in one item: label-over-value columns, the "合并成一项" layout.
struct CombinedMenuBarView: View {
    var monitor = Monitor.shared
    var settings = SettingsStore.shared

    var body: some View {
        let prefs = settings.prefs
        let s = monitor.snapshot
        let modules = prefs.menubar.order.filter { prefs.isVisible($0) && MenuBarText.available($0, s) }
        HStack(spacing: 11) {
            if modules.isEmpty {
                LineIcon(d: Icons.appMark, size: 16, viewBox: 24, lineWidth: 2.4)
            }
            ForEach(modules) { m in
                column(m, s, prefs)
                    .foregroundStyle(MenuBarText.tone(m, s, prefs).color ?? .primary)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxHeight: .infinity)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MenuBarText.combinedAccessibility(modules, s, prefs))
    }

    @ViewBuilder private func column(_ m: Module, _ s: Snapshot, _ prefs: Preferences) -> some View {
        let tone = MenuBarText.tone(m, s, prefs)
        switch m {
        case .network:
            let offline = !s.network.connected
            HStack(spacing: 2.5) {
                NetArrows(upOnTop: prefs.network.order == .uploadTop, height: 20).opacity(offline ? 0.45 : 1)
                let up = offline ? L10n.Common.dash : Format.rateCompact(s.network.up, unit: prefs.network.speedUnit)
                let down = offline ? L10n.Common.dash : Format.rateCompact(s.network.down, unit: prefs.network.speedUnit)
                StackedValues(top: prefs.network.order == .uploadTop ? up : down,
                              bottom: prefs.network.order == .uploadTop ? down : up, template: "999K")
            }
        default:
            TwoLineValue(label: m.compactLabel, value: MenuBarText.shortValue(m, s, prefs), template: m == .sensors ? "100°" : "100%", tone: tone)
        }
    }
}

/// Text and state rules shared by the menu bar views, the accessibility labels and settings previews.
enum MenuBarText {
    static var upArrow: String { "↑" }
    static var downArrow: String { "↓" }

    static func gigabytes(_ bytes: UInt64, binary: Bool = false, decimal: Bool = false) -> String {
        let divisor: Double = decimal ? 1_000_000_000 : 1_073_741_824
        let gb = Double(bytes) / divisor
        if gb >= 1000 { return String(format: "%.1fT", gb / 1000) }
        if gb >= 100 || decimal { return "\(Int(gb.rounded()))G" }
        return String(format: "%.1fG", gb)
    }

    static func readShort(_ v: Double) -> String { "R " + Format.rateCompact(v) }
    static func writeShort(_ v: Double) -> String { "W " + Format.rateCompact(v) }

    static func volume(_ d: DiskSample, _ name: String) -> Volume? {
        if !name.isEmpty, let v = d.volumes.first(where: { $0.name == name }) { return v }
        return d.root
    }

    static func sensorValue(_ s: SensorsSample, _ choice: SensorChoice) -> Double? {
        switch choice {
        case .cpuAverage: return s.cpuAverage
        case .cpuPerformance: return s.value(.cpuPerformance)
        case .cpuEfficiency: return s.value(.cpuEfficiency)
        case .gpu: return s.value(.gpu)
        case .ssd: return s.value(.ssd)
        case .battery: return s.value(.battery)
        }
    }

    /// Whether this Mac has the hardware a module reports on.
    static func available(_ m: Module, _ s: Snapshot) -> Bool {
        switch m {
        case .battery: return s.battery.hasBattery
        case .sensors: return !s.sensors.temps.isEmpty || !s.sensors.fans.isEmpty
        default: return true
        }
    }

    static func shortValue(_ m: Module, _ s: Snapshot, _ prefs: Preferences) -> String {
        switch m {
        case .cpu: return Format.percent(s.cpu.total)
        case .gpu: return Format.percent(s.gpu.utilization)
        case .memory: return Format.percent(s.memory.usedFraction)
        case .network: return Format.rateCompact(s.network.down)
        case .disk: return volume(s.disk, prefs.disk.volume).map { Format.percent($0.usedFraction) } ?? L10n.Common.dash
        case .battery: return Format.percent(s.battery.level)
        case .sensors: return sensorValue(s.sensors, prefs.sensors.sensor).map { Format.temperature($0, unit: prefs.general.temperatureUnit) } ?? L10n.Common.dash
        }
    }

    /// Warn / critical coloring when "负载过高时变色" is on, plus offline dimming.
    static func tone(_ m: Module, _ s: Snapshot, _ prefs: Preferences) -> BarTone {
        if m == .network && !s.network.connected { return .dim }
        let alerts = Alerts.shared.active
        if prefs.alerts.enabled && prefs.alerts.colorMenubar, let level = alerts[m] { return level }
        guard prefs.menubar.colorOnHighLoad else { return .normal }
        switch m {
        case .cpu: return s.cpu.total >= 0.9 ? .warn : .normal
        case .gpu: return s.gpu.utilization >= 0.95 ? .warn : .normal
        case .memory: return s.memory.pressure == .critical ? .crit : s.memory.pressure == .warning ? .warn : .normal
        case .sensors:
            guard let t = sensorValue(s.sensors, prefs.sensors.sensor) else { return .normal }
            return t >= 95 ? .crit : t >= 85 ? .warn : .normal
        case .disk:
            guard let v = volume(s.disk, prefs.disk.volume) else { return .normal }
            return v.available < 10_000_000_000 ? .warn : .normal
        default: return .normal
        }
    }

    /// Whether the item has to keep its colors (otherwise it is drawn as a template image).
    static func needsColor(_ m: Module, _ s: Snapshot, _ prefs: Preferences) -> Bool {
        let t = tone(m, s, prefs)
        if t.emphasized { return true }
        if t == .dim { return false }
        let global = prefs.menubar.iconColor == .color
        switch m {
        case .cpu: return global || prefs.cpu.color == .color
        case .gpu: return global || prefs.gpu.color == .color
        case .memory: return global || prefs.memory.color == .pressure
        case .network: return (global || prefs.network.color == .color) && s.network.connected
        case .disk: return global
        case .battery:
            let b = s.battery
            return global || (prefs.battery.colorWhenLow && b.level <= 0.2 && !b.isCharging && !b.onAC)
        case .sensors: return global || prefs.sensors.color == .byTemp
        }
    }

    static func accessibility(_ m: Module, _ s: Snapshot, _ prefs: Preferences) -> String {
        let unit = prefs.general.temperatureUnit
        switch m {
        case .cpu: return L10n.A11y.cpu(Format.percent(s.cpu.total))
        case .gpu: return L10n.A11y.gpu(Format.percent(s.gpu.utilization))
        case .memory: return L10n.A11y.memory(Format.percent(s.memory.usedFraction))
        case .network:
            return s.network.connected ? L10n.A11y.network(Format.rate(s.network.up), Format.rate(s.network.down)) : L10n.A11y.networkOffline
        case .disk:
            return L10n.A11y.disk(volume(s.disk, prefs.disk.volume).map { Format.storage($0.available) } ?? L10n.Common.dash)
        case .battery:
            let base = L10n.A11y.battery(Format.percent(s.battery.level))
            if s.battery.isCharging { return base + L10n.Battery.chargingA11y }
            if s.battery.level <= 0.2 && !s.battery.onAC { return base + L10n.Battery.lowA11y }
            return base
        case .sensors:
            return L10n.A11y.temperature(sensorValue(s.sensors, prefs.sensors.sensor).map { Format.temperatureNumber($0, unit: unit) } ?? L10n.Common.dash)
        }
    }

    static func combinedAccessibility(_ modules: [Module], _ s: Snapshot, _ prefs: Preferences) -> String {
        ([L10n.App.name] + modules.map { accessibility($0, s, prefs) }).joined(separator: L10n.A11y.separator)
    }
}
