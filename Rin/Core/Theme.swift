import AppKit
import CoreText
import SwiftUI

/// Design tokens (light / dark pairs): one surface (white, or graphite when dark), no cards; space
/// and hairlines do the grouping. Everything is text greys except each module's own soft hue, for
/// the reading its page is about. Red is kept for what needs attention, amber for running high;
/// all-is-well is never colored.
struct RGBA {
    let r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat

    init(_ hex: UInt32, _ a: CGFloat = 1) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
        self.a = a
    }

    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) {
        self.r = r / 255
        self.g = g / 255
        self.b = b / 255
        self.a = a
    }

    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

extension NSColor {
    static func dynamic(_ light: RGBA, _ dark: RGBA) -> NSColor {
        NSColor(name: nil) { $0.isDark ? dark.nsColor : light.nsColor }
    }
}

extension Color {
    static func dyn(_ light: RGBA, _ dark: RGBA) -> Color {
        Color(nsColor: .dynamic(light, dark))
    }
}

enum Theme {
    // Surfaces: one solid color for the window and its rail, another for the dropdowns.
    /// The dropdowns' background.
    static let glass = Color.dyn(RGBA(0xFFFFFF), RGBA(0x161618))
    static let windowGlass = Color.dyn(RGBA(0xFFFFFF), RGBA(0x111113))
    static let glassRim = Color.dyn(RGBA(0, 0, 0, 0.08), RGBA(255, 255, 255, 0.07))

    /// A raised piece (the selected segment): a white chip with a soft shadow on light, a lighter step on dark.
    static let raised = Color.dyn(RGBA(0xFFFFFF), RGBA(255, 255, 255, 0.12))
    static let raisedShadowNear = Color.dyn(RGBA(0, 0, 0, 0.12), RGBA(0, 0, 0, 0))
    static let raisedRing = Color.dyn(RGBA(0, 0, 0, 0.06), RGBA(0, 0, 0, 0))

    /// The grey behind a group of segments, a button, a popup, the selected rail item.
    static let raise = Color.dyn(RGBA(0, 0, 0, 0.05), RGBA(255, 255, 255, 0.06))
    static let lgHover = Color.dyn(RGBA(0, 0, 0, 0.04), RGBA(255, 255, 255, 0.06))
    /// A dropdown row whose details are open beside it: raised off the panel.
    static let rowSelected = Color.dyn(RGBA(255, 255, 255, 0.7), RGBA(255, 255, 255, 0.1))
    /// The sidebar, running the window's full height.
    static let rail = Color.dyn(RGBA(0, 0, 0, 0.035), RGBA(255, 255, 255, 0.035))
    /// An icon on the picked sidebar tile.
    static let onTile = Color.dyn(RGBA(0xFFFFFF), RGBA(0x111113))
    /// Behind a plain program's black icon, which would vanish on the dark window.
    static let iconLift = Color.dyn(RGBA(0, 0, 0, 0), RGBA(255, 255, 255, 0.28))
    /// Tags and chips that are on ("90%" in a rule, a module in the menu bar).
    static let chip = Color.dyn(RGBA(0, 0, 0, 0.06), RGBA(255, 255, 255, 0.08))

    /// Groups of settings rows sit in a soft well.
    static let well = Color.dyn(RGBA(0, 0, 0, 0.03), RGBA(255, 255, 255, 0.045))
    static let switchOff = Color.dyn(RGBA(0, 0, 0, 0.12), RGBA(255, 255, 255, 0.16))
    static let switchKnob = Color.dyn(RGBA(0xFFFFFF), RGBA(0xD9D9DC))
    /// A switch that is on: Rin's green, with a white knob (a graphite one on the light green).
    static var switchOn: Color { green }
    static let switchOnKnob = Color.dyn(RGBA(0xFFFFFF), RGBA(0x111113))
    /// No cards: a "panel" is the window itself.
    static let panel = windowGlass
    static let line = Color.dyn(RGBA(0, 0, 0, 0.08), RGBA(255, 255, 255, 0.08))

    static let text = Color.dyn(RGBA(0x1C1C1E), RGBA(0xF2F2F3))
    static let sub = Color.dyn(RGBA(0x6E6E73), RGBA(0x8B8B90))
    /// Secondary series and quiet marks (system CPU, efficiency cores).
    static let faint = Color.dyn(RGBA(0, 0, 0, 0.28), RGBA(255, 255, 255, 0.45))
    /// Levels that are not the page's lead (a volume on the overview, a temperature).
    static let mid = Color.dyn(RGBA(0, 0, 0, 0.45), RGBA(255, 255, 255, 0.55))
    static let low = Color.dyn(RGBA(0, 0, 0, 0.16), RGBA(255, 255, 255, 0.25))
    static let track = Color.dyn(RGBA(0, 0, 0, 0.07), RGBA(255, 255, 255, 0.08))
    static let grid = line
    static let cache = low
    static let cross = Color.dyn(RGBA(0, 0, 0, 0.28), RGBA(255, 255, 255, 0.45))
    static let barFg = Color.dyn(RGBA(0x1C1C1E), RGBA(0xF2F2F3))
    /// Menu bar ink: opaque black or white like the system's own menu bar text (`.primary` is
    /// 85% opaque, which rendered the items grey).
    static let barInk = Color.dyn(RGBA(0x000000), RGBA(0xFFFFFF))

    /// Each module's own soft hue: its rail icon, its page's lead figure and line, its dropdown.
    /// Deeper on white so lines and figures hold. Battery and Bluetooth have none: their levels
    /// stay neutral, Rin's green while charging, red when low.
    private static let hues: [Module: (light: UInt32, dark: UInt32)] = [
        .cpu: (0x3E8A4E, 0x7FC48A), .gpu: (0x6F7A1F, 0xB8C46A), .memory: (0x6B4FA8, 0xB39DDB),
        .network: (0x2F8A78, 0x6FC2B0), .disk: (0x9A7630, 0xD8B97A), .sensors: (0xB8602A, 0xE08E5A),
    ]
    private static let hueColors = hues.mapValues { Color.dyn(RGBA($0.light), RGBA($0.dark)) }
    /// A module's second series (CPU system, GPU tiler, wired memory): the same hue, lighter.
    private static let softColors = hues.mapValues { Color.dyn(RGBA($0.light, 0.42), RGBA($0.dark, 0.5)) }

    static func hue(_ module: Module) -> Color? { hueColors[module] }
    /// Rin's own green (the CPU's hue): switches, the keep-awake timer, a charging battery, buttons.
    static let green = hueColors[.cpu]!
    static let onGreen = Color.dyn(RGBA(0xFFFFFF), RGBA(0x111113))

    // Status: all is well is plain text; only running high and an alert are colored.
    static let ok = sub
    static let okBg = Color.dyn(RGBA(0, 0, 0, 0.05), RGBA(255, 255, 255, 0.06))
    static let warn = Color.dyn(RGBA(0xB07800), RGBA(0xFFB547))
    static let warnBg = Color.dyn(RGBA(176, 120, 0, 0.12), RGBA(255, 181, 71, 0.14))
    static let danger = Color.dyn(RGBA(0xD23A30), RGBA(0xFF6B57))
    static let dangerBg = Color.dyn(RGBA(210, 58, 48, 0.1), RGBA(255, 107, 87, 0.14))
    static let dangerFill = danger
    static let onDanger = Color.dyn(RGBA(0xFFFFFF), RGBA(0x111113))

    /// The battery chart's charging spans.
    static let chargeBand = Color.dyn(RGBA(0, 0, 0, 0.045), RGBA(255, 255, 255, 0.05))

    // Menu bar items keep Apple's vivid colors: they sit on the system menu bar.
    static let barCPU = Color.dyn(RGBA(0x34C759), RGBA(0x34C759))
    static let barMem = Color.dyn(RGBA(0x5E5CE6), RGBA(0x5E5CE6))
    static let barUp = Color.dyn(RGBA(0xFF9F0A), RGBA(0xFF9F0A))
    static let barDown = Color.dyn(RGBA(0x0A84FF), RGBA(0x0A84FF))
    static let barDisk = Color.dyn(RGBA(0xFF9F0A), RGBA(0xFF9F0A))
    static let barBat = Color.dyn(RGBA(0x34C759), RGBA(0x34C759))
    static let barTemp = Color.dyn(RGBA(0xFF375F), RGBA(0xFF375F))
    static let barGPU = Color.dyn(RGBA(0xFF6B98), RGBA(0xFF6B98))
    static let barWarn = NSColor.dynamic(RGBA(0xB25000), RGBA(0xFF9F0A))
    static let barCrit = NSColor.dynamic(RGBA(0xD70015), RGBA(0xFF453A))

    /// The vivid menu bar color for a module ("彩色").
    static func barColor(_ module: Module) -> Color {
        switch module {
        case .cpu: return barCPU
        case .gpu: return barGPU
        case .memory: return barMem
        case .network: return barDown
        case .disk: return barDisk
        case .battery: return barBat
        case .bluetooth: return barDown
        case .sensors: return barTemp
        }
    }

    /// Named colors offered for chart and status widgets.
    static func palette(_ p: PaletteColor) -> Color {
        switch p {
        case .blue: return barDown
        case .orange: return barUp
        case .purple: return .dyn(RGBA(0xAF52DE), RGBA(0xBF5AF2))
        case .green: return barCPU
        case .red: return Color(nsColor: barCrit)
        case .pink: return barTemp
        case .teal: return .dyn(RGBA(0x30B0C7), RGBA(0x40C8E0))
        case .yellow: return .dyn(RGBA(0xD9A400), RGBA(0xFFD60A))
        }
    }

    /// A module's lead color: its hue, Rin's green for battery and Bluetooth.
    static func color(for module: Module) -> Color { hueColors[module] ?? green }
    /// A module's second series.
    static func soft(_ module: Module) -> Color { softColors[module] ?? faint }

    /// A battery level: red when low, else plain for a figure (`lead`); a line or bar is Rin's green
    /// while charging, else a mid grey.
    static func batteryLevel(_ b: BatterySample, lead: Bool = true) -> Color {
        if b.level <= 0.2 && !b.onAC { return danger }
        if lead { return text }
        return b.isCharging ? green : mid
    }
}


/// The system font (SF Pro, PingFang for Chinese) with tabular figures, for the window and panels.
enum Fonts {
    private static var cache: [String: Font] = [:]
    private static let lock = NSLock()

    /// How much larger than the design's sizes the main window draws its text. The console's
    /// type ramp (13 for body text) already reads well at 85%, so it is 1; kept as a knob.
    static let windowTextScale: CGFloat = 1

    /// Interface text at a design size, enlarged by the surface's text scale (half points).
    /// Big readouts sit 40 units lighter: with the system's font smoothing on they would
    /// otherwise read heavier than the design's numbers.
    static func text(_ size: CGFloat, _ weight: CGFloat = 400, scale: CGFloat = 1, proportional: Bool = false) -> Font {
        let weight = size >= 24 && weight >= 500 ? weight - 40 : weight
        return ui(scale == 1 ? size : (size * scale * 2).rounded() / 2, weight, proportional: proportional)
    }

    /// The system font at a CSS weight (300...700, in between allowed), tabular figures unless
    /// asked otherwise (a big lead reading). Menu bar previews use this directly so they keep the
    /// menu bar's own sizes.
    static func ui(_ size: CGFloat, _ weight: CGFloat = 400, proportional: Bool = false) -> Font {
        let key = "\(size)-\(weight)-\(proportional)"
        lock.lock(); defer { lock.unlock() }
        if let f = cache[key] { return f }
        let nsFont = proportional ? NSFont.systemFont(ofSize: size, weight: systemWeight(weight))
                                  : NSFont.monospacedDigitSystemFont(ofSize: size, weight: systemWeight(weight))
        let font = Font(nsFont as CTFont)
        cache[key] = font
        return font
    }

    /// CSS weights onto AppKit's scale, straight between the named stops.
    private static func systemWeight(_ css: CGFloat) -> NSFont.Weight {
        let stops: [(CGFloat, NSFont.Weight)] = [(300, .light), (400, .regular), (500, .medium), (600, .semibold), (700, .bold)]
        guard css > stops[0].0 else { return stops[0].1 }
        for (a, b) in zip(stops, stops.dropFirst()) where css <= b.0 {
            let t = (css - a.0) / (b.0 - a.0)
            return NSFont.Weight(a.1.rawValue + (b.1.rawValue - a.1.rawValue) * t)
        }
        return stops[stops.count - 1].1
    }
}
