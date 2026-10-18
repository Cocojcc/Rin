import Foundation

/// A menu bar widget. Like Stats, a module can show several at once, each as its own status
/// item or merged into one.
enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case label, mini, line, bar, pie, tacho, icon
    case ring, memory
    case speed, chart, state
    case value
    case battery, details
    case temp, fan, stack
    /// From the design's pick sheet: an icon with the value, a stacked label beside a graph, a
    /// capsule meter, two readings, a status dot, the number inside a battery, battery and time.
    case iconValue, labelLine, pill, pair, dot, inside, time

    var id: String { rawValue }
}

extension Module {
    /// Widgets this module offers, in the order the settings strip shows them.
    var widgetKinds: [WidgetKind] {
        switch self {
        // The pick sheet's styles in its order, then the plain label and icon.
        case .cpu: return [.iconValue, .line, .mini, .labelLine, .bar, .pie, .tacho, .pill, .label, .icon]
        case .gpu: return [.iconValue, .line, .mini, .bar, .ring, .pair, .tacho, .label, .icon]
        case .memory: return [.bar, .ring, .mini, .memory, .dot, .line, .iconValue, .label, .icon]
        case .network: return [.label, .speed, .chart, .state, .icon]
        case .disk: return [.value, .bar, .speed, .chart, .mini, .pie, .iconValue, .label, .icon]
        case .battery: return [.battery, .inside, .time, .details, .iconValue, .ring, .bar, .label, .mini, .icon]
        case .sensors: return [.temp, .value, .fan, .stack, .bar, .pair, .iconValue, .label, .mini]
        }
    }

    var defaultWidgets: [WidgetKind] {
        switch self {
        case .cpu: return [.line]
        case .gpu: return []
        case .memory: return [.bar]
        case .network: return [.speed]
        case .disk: return []
        case .battery: return [.battery]
        case .sensors: return [.temp, .fan]
        }
    }

    /// Added when the module is switched on with nothing selected.
    var primaryWidget: WidgetKind {
        switch self {
        case .cpu, .gpu: return .line
        case .memory: return .bar
        case .network: return .speed
        case .disk: return .value
        case .battery: return .battery
        case .sensors: return .temp
        }
    }
}

enum WidgetColor: String, Codable, CaseIterable { case mono, colored, byValue }
enum WidgetAlign: String, Codable, CaseIterable { case leading, center, trailing }
enum SpeedGlyph: String, Codable, CaseIterable { case arrows, triangles, dots, letters, none }
/// How a rate's unit is written: "120 KB/s", "120 KB" or "120K".
enum RateUnitStyle: String, Codable, CaseIterable { case perSecond, bytes, letter }
enum ValueLayout: String, Codable, CaseIterable { case twoLine, singleLine }
enum PaletteColor: String, Codable, CaseIterable { case blue, orange, purple, green, red, pink, teal, yellow }
enum BatteryDetails: String, Codable, CaseIterable { case percentAndTime, percent, time }
enum FanValue: String, Codable, CaseIterable { case rpm, percent }
enum TimeFormat: String, Codable, CaseIterable { case clock, minutes }

/// Every option any widget has; each widget reads the ones that apply to it.
struct WidgetOptions: Codable, Equatable {
    var labelText = ""                  // empty: the module's short label (CPU, RAM, NET…)
    var showLabel = false
    var showValue = true
    var boxed = true
    var color: WidgetColor = .mono
    var points = 60
    var align: WidgetAlign = .center
    var graphContent: CPUGraphContent = .total
    var monochrome = false
    var icon = 0
    var showSymbol = true
    var freeOnTop = false
    var glyph: SpeedGlyph = .arrows
    var layout: ValueLayout = .twoLine
    var showUnit = true
    var firstOnTop = true               // upload / read on top
    var firstColor: PaletteColor = .blue
    var secondColor: PaletteColor = .orange
    var showIcon = true
    var fanValue: FanValue = .rpm
    var monospaced = true
    var showPercent = true
    var showTime = false
    var hidePercentWhenFull = false
    var showBolt = true
    var colorWhenLow = true
    var details: BatteryDetails = .percentAndTime
    /// Network speed: the glyph after the number instead of before it.
    var glyphAfter = false
    var glyphGap = 3
    var unitStyle: RateUnitStyle = .perSecond
    /// Room for the widest value, so the item keeps its width as the numbers change.
    var fixedWidth = true
    var numberAlign: WidgetAlign = .trailing


    init() {}

    /// Missing keys keep their defaults, so options added later don't invalidate saved settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(type(of: labelText), forKey: .labelText) { labelText = v }
        if let v = try c.decodeIfPresent(type(of: showLabel), forKey: .showLabel) { showLabel = v }
        if let v = try c.decodeIfPresent(type(of: showValue), forKey: .showValue) { showValue = v }
        if let v = try c.decodeIfPresent(type(of: boxed), forKey: .boxed) { boxed = v }
        if let v = try c.decodeIfPresent(type(of: color), forKey: .color) { color = v }
        if let v = try c.decodeIfPresent(type(of: points), forKey: .points) { points = v }
        if let v = try c.decodeIfPresent(type(of: align), forKey: .align) { align = v }
        if let v = try c.decodeIfPresent(type(of: graphContent), forKey: .graphContent) { graphContent = v }
        if let v = try c.decodeIfPresent(type(of: monochrome), forKey: .monochrome) { monochrome = v }
        if let v = try c.decodeIfPresent(type(of: icon), forKey: .icon) { icon = v }
        if let v = try c.decodeIfPresent(type(of: showSymbol), forKey: .showSymbol) { showSymbol = v }
        if let v = try c.decodeIfPresent(type(of: freeOnTop), forKey: .freeOnTop) { freeOnTop = v }
        if let v = try c.decodeIfPresent(type(of: glyph), forKey: .glyph) { glyph = v }
        if let v = try c.decodeIfPresent(type(of: layout), forKey: .layout) { layout = v }
        if let v = try c.decodeIfPresent(type(of: showUnit), forKey: .showUnit) { showUnit = v }
        if let v = try c.decodeIfPresent(type(of: firstOnTop), forKey: .firstOnTop) { firstOnTop = v }
        if let v = try c.decodeIfPresent(type(of: firstColor), forKey: .firstColor) { firstColor = v }
        if let v = try c.decodeIfPresent(type(of: secondColor), forKey: .secondColor) { secondColor = v }
        if let v = try c.decodeIfPresent(type(of: showIcon), forKey: .showIcon) { showIcon = v }
        if let v = try c.decodeIfPresent(type(of: fanValue), forKey: .fanValue) { fanValue = v }
        if let v = try c.decodeIfPresent(type(of: monospaced), forKey: .monospaced) { monospaced = v }
        if let v = try c.decodeIfPresent(type(of: showPercent), forKey: .showPercent) { showPercent = v }
        if let v = try c.decodeIfPresent(type(of: showTime), forKey: .showTime) { showTime = v }
        if let v = try c.decodeIfPresent(type(of: hidePercentWhenFull), forKey: .hidePercentWhenFull) { hidePercentWhenFull = v }
        if let v = try c.decodeIfPresent(type(of: showBolt), forKey: .showBolt) { showBolt = v }
        if let v = try c.decodeIfPresent(type(of: colorWhenLow), forKey: .colorWhenLow) { colorWhenLow = v }
        if let v = try c.decodeIfPresent(type(of: details), forKey: .details) { details = v }
        if let v = try c.decodeIfPresent(type(of: glyphAfter), forKey: .glyphAfter) { glyphAfter = v }
        if let v = try c.decodeIfPresent(type(of: glyphGap), forKey: .glyphGap) { glyphGap = v }
        if let v = try c.decodeIfPresent(type(of: unitStyle), forKey: .unitStyle) { unitStyle = v }
        if let v = try c.decodeIfPresent(type(of: fixedWidth), forKey: .fixedWidth) { fixedWidth = v }
        if let v = try c.decodeIfPresent(type(of: numberAlign), forKey: .numberAlign) { numberAlign = v }
    }

    static func defaults(_ module: Module, _ kind: WidgetKind) -> WidgetOptions {
        var o = WidgetOptions()
        switch (module, kind) {
        case (_, .mini): o.showLabel = true
        case (.cpu, .bar), (.memory, .ring), (.battery, .bar), (.sensors, .bar): o.color = .byValue
        case (.disk, .speed): o.showUnit = false
        case (.disk, .chart): o.secondColor = .purple
        case (.network, .state): o.firstColor = .green; o.secondColor = .red
        case (.gpu, .tacho): o.showValue = false
        // The pick sheet pairs these with a cylinder, a bolt and a flame.
        case (.disk, .iconValue), (.battery, .iconValue), (.sensors, .iconValue): o.icon = 2
        default: break
        }
        return o
    }
}

/// A module's menu bar widgets: which are on (in order), their options, merged or not.
struct ModuleWidgets: Codable, Equatable {
    var enabled: [WidgetKind]
    var options: [String: WidgetOptions] = [:]
    var merged = false
}

extension Preferences {
    /// Widgets before the user picks any.
    private func initialWidgets(_ m: Module) -> [WidgetKind] { m.defaultWidgets }

    /// Modules that were in the menu bar before widgets existed but have no default widget
    /// (disk, GPU) keep one, so they don't vanish. Runs once on saved settings.
    mutating func migrateWidgets() {
        for m in Module.allCases where widgetState[m.rawValue] == nil && isVisible(m) && m.defaultWidgets.isEmpty {
            widgetState[m.rawValue] = ModuleWidgets(enabled: [m.primaryWidget])
        }
        general.widgetsMigrated = true
    }

    /// The "在菜单栏显示" switch. Off keeps the picked widgets for next time; on brings them
    /// back, or the module's usual widgets when none are picked.
    mutating func setInMenubar(_ m: Module, _ on: Bool) {
        setVisible(m, on)
        if on && widgets(m).isEmpty {
            for kind in m.defaultWidgets.isEmpty ? [m.primaryWidget] : m.defaultWidgets { setWidget(kind, true, for: m) }
        }
    }

    func widgets(_ m: Module) -> [WidgetKind] {
        let enabled = widgetState[m.rawValue]?.enabled ?? initialWidgets(m)
        return m.widgetKinds.filter(enabled.contains)
    }

    mutating func setWidget(_ kind: WidgetKind, _ on: Bool, for m: Module) {
        var state = widgetState[m.rawValue] ?? ModuleWidgets(enabled: initialWidgets(m))
        state.enabled.removeAll { $0 == kind }
        if on { state.enabled.append(kind) }
        widgetState[m.rawValue] = state
    }

    func options(_ m: Module, _ kind: WidgetKind) -> WidgetOptions {
        widgetState[m.rawValue]?.options[kind.rawValue] ?? .defaults(m, kind)
    }

    mutating func setOptions(_ o: WidgetOptions, _ m: Module, _ kind: WidgetKind) {
        var state = widgetState[m.rawValue] ?? ModuleWidgets(enabled: initialWidgets(m))
        state.options[kind.rawValue] = o
        widgetState[m.rawValue] = state
    }

    func widgetsMerged(_ m: Module) -> Bool { widgetState[m.rawValue]?.merged ?? false }

    mutating func setWidgetsMerged(_ on: Bool, _ m: Module) {
        var state = widgetState[m.rawValue] ?? ModuleWidgets(enabled: initialWidgets(m))
        state.merged = on
        widgetState[m.rawValue] = state
    }

    /// Shown in the menu bar: switched on and at least one widget picked (so clearing every
    /// widget also takes it out).
    func showsInMenubar(_ m: Module) -> Bool { isVisible(m) && !widgets(m).isEmpty }

    /// Modules an alert rule watches; they are read even when not in the menu bar.
    var alertedModules: Set<Module> {
        let a = alerts
        guard a.enabled else { return [] }
        var out: Set<Module> = []
        if a.cpuOn { out.insert(.cpu) }
        if a.gpuOn { out.insert(.gpu) }
        if a.memoryOn { out.insert(.memory) }
        if a.diskOn { out.insert(.disk) }
        if a.batteryOn { out.insert(.battery) }
        if a.tempOn { out.insert(.sensors) }
        if a.networkOn { out.insert(.network) }
        return out
    }
}
