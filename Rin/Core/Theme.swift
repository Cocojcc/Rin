import AppKit
import CoreText
import SwiftUI

/// Design tokens (light / dark pairs), monochrome: one surface (white, or graphite when dark), no
/// cards; space and hairlines do the grouping. Everything is text greys except one accent (lime,
/// a deeper green on white) for the one reading a page is about. Red is kept for what needs
/// attention, amber for running high; all-is-well is never colored.
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
    /// The selected rail item.
    static let selection = raise
    /// Tags and chips that are on ("90%" in a rule, a module in the menu bar).
    static let chip = Color.dyn(RGBA(0, 0, 0, 0.06), RGBA(255, 255, 255, 0.08))

    static let well = raise
    static let switchOff = Color.dyn(RGBA(0, 0, 0, 0.12), RGBA(255, 255, 255, 0.16))
    static let switchKnob = Color.dyn(RGBA(0xFFFFFF), RGBA(0xD9D9DC))
    /// A switch that is on: the accent, with a white knob (a graphite one on the lime).
    static var switchOn: Color { accent }
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
    /// Under a chart's line: a neutral wash, whatever the line's color.
    static let area = Color.dyn(RGBA(0, 0, 0, 0.035), RGBA(255, 255, 255, 0.045))
    static let cache = low
    static let cross = Color.dyn(RGBA(0, 0, 0, 0.28), RGBA(255, 255, 255, 0.45))
    static let barFg = Color.dyn(RGBA(0x1C1C1E), RGBA(0xF2F2F3))
    /// Menu bar ink: opaque black or white like the system's own menu bar text (`.primary` is
    /// 85% opaque, which rendered the items grey).
    static let barInk = Color.dyn(RGBA(0x000000), RGBA(0xFFFFFF))

    /// The one accent: lime on graphite, a deeper green on white so lines and figures hold.
    static let accent = Color.dyn(RGBA(0x4D8C00), RGBA(0xD7FF3A))
    static let accentSoft = Color.dyn(RGBA(77, 140, 0, 0.4), RGBA(215, 255, 58, 0.55))
    static let onAccent = Color.dyn(RGBA(0xFFFFFF), RGBA(0x111113))

    // Status: all is well is plain text; only running high and an alert are colored.
    static let ok = sub
    static let okBg = Color.dyn(RGBA(0, 0, 0, 0.05), RGBA(255, 255, 255, 0.06))
    static let warn = Color.dyn(RGBA(0xB07800), RGBA(0xFFB547))
    static let warnBg = Color.dyn(RGBA(176, 120, 0, 0.12), RGBA(255, 181, 71, 0.14))
    static let danger = Color.dyn(RGBA(0xD23A30), RGBA(0xFF6B57))
    static let dangerBg = Color.dyn(RGBA(210, 58, 48, 0.1), RGBA(255, 107, 87, 0.14))
    static let dangerFill = danger
    static let onDanger = Color.dyn(RGBA(0xFFFFFF), RGBA(0x111113))

    // Data: the lead reading wears the accent; the parts around it are greys.
    static var cpu: Color { accent }
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

    /// A module's lead color: the accent for all of them (battery and device levels go red when low).
    static func color(for module: Module) -> Color { accent }
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
    static func text(_ size: CGFloat, _ weight: CGFloat = 400, scale: CGFloat = 1) -> Font {
        let weight = size >= 24 && weight >= 500 ? weight - 40 : weight
        return scale == 1 ? ui(size, weight) : ui((size * scale * 2).rounded() / 2, weight)
    }

    /// The system font at a CSS weight (300...700, in between allowed), tabular figures. Menu bar
    /// previews use this directly so they keep the menu bar's own sizes.
    static func ui(_ size: CGFloat, _ weight: CGFloat = 400) -> Font {
        let key = "\(size)-\(weight)"
        lock.lock(); defer { lock.unlock() }
        if let f = cache[key] { return f }
        let font = Font(NSFont.monospacedDigitSystemFont(ofSize: size, weight: systemWeight(weight)) as CTFont)
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
