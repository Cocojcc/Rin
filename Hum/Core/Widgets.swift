import Foundation

/// A piece of a module's menu bar item. Icons, graphics and numbers are separate pieces that
/// sit side by side in the order they were picked, so "icon + number" or "graph + number" is
/// just two of them.
enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    // Icons and graphics
    case icon, label, line, bar, pie, tacho, ring, pill, dot, battery, chart, state
    /// An animated character whose pace follows the module's reading.
    case runner
    // Numbers
    case value, mini, memory, speed, details, time, fan, stack, pair, inside
    /// Bluetooth: chosen devices' batteries, and the lowest one.
    case devices, lowest
    /// Earlier pieces that combined an icon or graphic with a number; split up when settings load.
    case temp, iconValue, labelLine

    var id: String { rawValue }
}

extension Module {
    /// Widgets this module offers, in the order the settings strip shows them.
    var widgetKinds: [WidgetKind] {
        switch self {
        // The icon and the number first, then the graphics, then the other readings.
        case .cpu: return [.icon, .value, .runner, .line, .bar, .pie, .tacho, .pill, .label, .mini]
        case .gpu: return [.icon, .value, .line, .bar, .ring, .tacho, .pair, .label, .mini]
        case .memory: return [.icon, .value, .runner, .bar, .ring, .dot, .line, .memory, .label, .mini]
        case .network: return [.icon, .speed, .runner, .chart, .state, .label]
        case .disk: return [.icon, .value, .bar, .pie, .chart, .speed, .label, .mini]
        case .battery: return [.icon, .value, .battery, .inside, .time, .details, .ring, .bar, .label, .mini]
        case .bluetooth: return [.devices, .stack, .lowest, .icon, .label]
        case .sensors: return [.icon, .value, .fan, .bar, .stack, .label, .mini]
        }
    }

    var defaultWidgets: [WidgetKind] {
        switch self {
        case .cpu: return [.line, .value]
        case .gpu: return []
        case .memory: return [.bar, .value]
        case .network: return [.speed]
        case .disk: return []
        case .battery: return [.battery, .value]
        case .bluetooth: return [.devices]
        case .sensors: return [.icon, .value, .fan]
        }
    }

    /// Added when the module is switched on with nothing picked.
    var primaryWidgets: [WidgetKind] {
        switch self {
        case .gpu: return [.line, .value]
        case .disk: return [.icon, .value]
        default: return defaultWidgets
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
    /// The same for the number widget, off by default: the number is only as wide as it is,
    /// so the space beside it is just the widget gap.
    var numberFixed = false
    /// Bluetooth devices a widget shows (ids); empty means the connected ones, lowest first.
    var deviceIDs: [String] = []
    /// Bluetooth "lowest": nothing while every device is above the low level.
    var hideWhenFine = false
    /// The animation widget's character.
    var runner = RunnerLibrary.defaultID


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
        if let v = try c.decodeIfPresent(type(of: numberFixed), forKey: .numberFixed) { numberFixed = v }
        if let v = try c.decodeIfPresent(type(of: deviceIDs), forKey: .deviceIDs) { deviceIDs = v }
        if let v = try c.decodeIfPresent(type(of: hideWhenFine), forKey: .hideWhenFine) { hideWhenFine = v }
        if let v = try c.decodeIfPresent(type(of: runner), forKey: .runner) { runner = v }
    }

    static func defaults(_ module: Module, _ kind: WidgetKind) -> WidgetOptions {
        var o = WidgetOptions()
        switch (module, kind) {
        case (_, .mini): o.showLabel = true
        case (.cpu, .bar), (.memory, .ring), (.battery, .bar), (.sensors, .bar): o.color = .byValue
        case (.disk, .speed): o.showUnit = false
        case (.disk, .chart): o.secondColor = .purple
        case (.network, .state): o.firstColor = .green; o.secondColor = .red
        default: break
        }
        return o
    }
}

/// A module's menu bar widgets: which are on, in the order they sit; their options; the space
/// between them.
struct ModuleWidgets: Codable, Equatable {
    var enabled: [WidgetKind]
    var options: [String: WidgetOptions] = [:]
    /// The earlier on / off spacing (3 or 8 pt); stands in until a gap is set.
    var merged = true
    /// Points between widgets.
    var gap: Int?

    static let gapRange = 0...8
    static let defaultGap = 3
}

extension Preferences {
    /// Widgets before the user picks any.
    private func initialWidgets(_ m: Module) -> [WidgetKind] { m.defaultWidgets }

    /// Modules that were in the menu bar before widgets existed but have no default widget
    /// (disk, GPU) keep one, so they don't vanish. Runs once on saved settings.
    mutating func migrateWidgets() {
        for m in Module.allCases where widgetState[m.rawValue] == nil && isVisible(m) && m.defaultWidgets.isEmpty {
            widgetState[m.rawValue] = ModuleWidgets(enabled: m.primaryWidgets)
        }
        general.widgetsMigrated = true
    }

    /// Widgets used to pair a graphic with its number; now each is its own piece. Splits saved
    /// picks once, keeping how they looked: "icon and value" becomes icon + value, a graph that
    /// showed its number becomes graph + value, and so on. The pieces sit tight together.
    mutating func splitCompoundWidgets() {
        for m in Module.allCases {
            guard var state = widgetState[m.rawValue] else { continue }
            var options = state.options
            func old(_ k: WidgetKind) -> WidgetOptions { options[k.rawValue] ?? .defaults(m, k) }
            func edit(_ k: WidgetKind, _ change: (inout WidgetOptions) -> Void) {
                var o = old(k)
                change(&o)
                options[k.rawValue] = o
            }
            var out: [WidgetKind] = []
            func add(_ k: WidgetKind) { if !out.contains(k) { out.append(k) } }
            for kind in state.enabled {
                let o = old(kind)
                switch kind {
                case .iconValue:
                    edit(.icon) { $0.icon = o.icon }
                    add(.icon); add(.value)
                case .labelLine:
                    add(.label); add(.line)
                case .temp:
                    if o.showIcon { add(.icon) }
                    edit(.value) { $0.color = o.color }
                    add(.value)
                case .pair where m == .sensors:
                    add(.icon); add(.value); add(.fan)
                case .value where m == .disk:
                    if o.showIcon { add(.icon) }
                    add(.value)
                case .battery:
                    add(.battery)
                    if o.showPercent {
                        edit(.value) { $0.hidePercentWhenFull = o.hidePercentWhenFull }
                        add(.value)
                    }
                    if o.showTime { add(.time) }
                case .time:
                    add(.battery); add(.time)
                case .line, .pie, .tacho:
                    if o.showLabel { add(.label) }
                    add(kind)
                    if o.showValue { add(.value) }
                case .bar where m == .cpu:
                    if o.showLabel { add(.label) }
                    add(.bar)
                case .bar, .ring, .pill, .dot:
                    add(kind)
                    if o.showValue { add(.value) }
                default:
                    add(kind)
                }
            }
            state.enabled = out.filter(m.widgetKinds.contains)
            state.options = options
            state.merged = true
            widgetState[m.rawValue] = state
        }
        general.widgetsSplit = true
    }

    /// The "在菜单栏显示" switch. Off keeps the picked widgets for next time; on brings them
    /// back, or the module's usual widgets when none are picked.
    mutating func setInMenubar(_ m: Module, _ on: Bool) {
        setVisible(m, on)
        if on && widgets(m).isEmpty {
            for kind in m.primaryWidgets { setWidget(kind, true, for: m) }
        }
    }

    /// The picked widgets in the order they sit (the order they were picked or dragged into).
    func widgets(_ m: Module) -> [WidgetKind] {
        let enabled = widgetState[m.rawValue]?.enabled ?? initialWidgets(m)
        return enabled.filter(m.widgetKinds.contains)
    }

    /// Moves a picked widget to where another one sits.
    mutating func moveWidget(_ kind: WidgetKind, to target: WidgetKind, for m: Module) {
        var state = widgetState[m.rawValue] ?? ModuleWidgets(enabled: initialWidgets(m))
        guard let from = state.enabled.firstIndex(of: kind), let to = state.enabled.firstIndex(of: target), from != to else { return }
        state.enabled.remove(at: from)
        state.enabled.insert(kind, at: to)
        widgetState[m.rawValue] = state
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

    func widgetGap(_ m: Module) -> Int {
        guard let state = widgetState[m.rawValue] else { return ModuleWidgets.defaultGap }
        return state.gap ?? (state.merged ? ModuleWidgets.defaultGap : 8)
    }

    mutating func setWidgetGap(_ gap: Int, _ m: Module) {
        var state = widgetState[m.rawValue] ?? ModuleWidgets(enabled: initialWidgets(m))
        state.gap = min(max(gap, ModuleWidgets.gapRange.lowerBound), ModuleWidgets.gapRange.upperBound)
        widgetState[m.rawValue] = state
    }

    /// Shown in the menu bar: switched on and at least one widget picked (so clearing every
    /// widget also takes it out).
    func showsInMenubar(_ m: Module) -> Bool { isEnabled(m) && isVisible(m) && !widgets(m).isEmpty }

    /// False while the combined item shows a single icon: no module's widgets are in the bar.
    var barShowsWidgets: Bool { !(menubar.displayMode == .combined && menubar.combinedIconOnly) }

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
        if a.bluetoothLowOn || a.bluetoothDisconnectOn { out.insert(.bluetooth) }
        return out.filter(isEnabled)
    }
}
