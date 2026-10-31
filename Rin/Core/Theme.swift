import AppKit
import CoreText
import SwiftUI

/// Design tokens (light / dark pairs) for the monitoring console: solid neutral surfaces (charcoal
/// with a trace of warmth when dark, white and light grey when light) and color only for data and
/// state. Each module owns one hue and its parts (user / system, down / up, read / write) are
/// shades of it; green, amber and red only ever mean status.
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
    // Surfaces: solid, no glass.
    /// The dropdowns' background.
    static let glass = Color.dyn(RGBA(0xFFFFFF), RGBA(0x1A191C))
    static let windowGlass = Color.dyn(RGBA(0xFFFFFF), RGBA(0x151416))
    static let side = Color.dyn(RGBA(0xF5F5F7), RGBA(0x111012))
    static let glassRim = Color.dyn(RGBA(0, 0, 0, 0.1), RGBA(255, 255, 255, 0.14))
    static let glassEdge = Color.dyn(RGBA(0, 0, 0, 0.08), RGBA(0, 0, 0, 0.5))
    static let menu = Color.dyn(RGBA(0xFFFFFF), RGBA(0x242326))

    // Selected pieces: a white chip on light, a lighter step on dark.
    static let raised = Color.dyn(RGBA(0xFFFFFF), RGBA(255, 255, 255, 0.15))
    static let raisedShadowNear = Color.dyn(RGBA(0, 0, 0, 0.08), RGBA(0, 0, 0, 0))
    static let raisedShadowFar = Color.dyn(RGBA(0, 0, 0, 0.04), RGBA(0, 0, 0, 0))

    // Segmented groups: a flat track and a flat thumb on the selected piece.
    static let lgFill = Color.dyn(RGBA(0, 0, 0, 0.06), RGBA(255, 255, 255, 0.08))
    static let lgEdgeLight = Color.clear
    static let lgEdgeLine = Color.clear
    static let lgThumb = raised
    static let lgThumbLight = Color.clear
    static let lgThumbRing = Color.clear
    static let lgThumbLine = Color.dyn(RGBA(0, 0, 0, 0.06), RGBA(0, 0, 0, 0))
    static let lgThumbShadow = Color.dyn(RGBA(0, 0, 0, 0.08), RGBA(0, 0, 0, 0))
    static let lgHover = Color.dyn(RGBA(0, 0, 0, 0.04), RGBA(255, 255, 255, 0.05))
    /// The selected sidebar row.
    static let selection = Color.dyn(RGBA(0, 0, 0, 0.06), RGBA(255, 255, 255, 0.09))

    static let well = Color.dyn(RGBA(0, 0, 0, 0.07), RGBA(255, 255, 255, 0.08))
    static let switchOff = Color.dyn(RGBA(0, 0, 0, 0.12), RGBA(255, 255, 255, 0.14))
    static let switchKnob = Color.dyn(RGBA(0xFFFFFF), RGBA(0x9C99A1))
    static let panel = Color.dyn(RGBA(0xF4F4F6), RGBA(0x1D1C1F))
    /// A clickable panel under the pointer (the overview's tiles).
    static let panelHover = Color.dyn(RGBA(0xECECEF), RGBA(0x242326))
    /// A panel's 1 pt inner edge.
    static let panelEdge = Color.dyn(RGBA(0, 0, 0, 0.06), RGBA(255, 255, 255, 0.06))
    static let line = Color.dyn(RGBA(0, 0, 0, 0.08), RGBA(255, 255, 255, 0.08))

    static let text = Color.dyn(RGBA(0x1C1C1E), RGBA(0xEDEBEE))
    static let sub = Color.dyn(RGBA(0x6B6A70), RGBA(0x9C99A1))
    /// Decoration and the quietest hints; text that has to be read uses `sub`.
    static let faint = Color.dyn(RGBA(0x8E8D93), RGBA(0x77747B))
    static let neutral = Color.dyn(RGBA(0x8E8D93), RGBA(0xC9C6CC))
    static let track = Color.dyn(RGBA(0, 0, 0, 0.07), RGBA(255, 255, 255, 0.08))
    static let grid = Color.dyn(RGBA(0, 0, 0, 0.07), RGBA(255, 255, 255, 0.07))
    static let cache = Color.dyn(RGBA(0, 0, 0, 0.18), RGBA(255, 255, 255, 0.22))
    static let cross = Color.dyn(RGBA(0, 0, 0, 0.3), RGBA(255, 255, 255, 0.35))
    static let rim = Color.dyn(RGBA(29, 29, 31, 0.4), RGBA(245, 245, 247, 0.45))
    static let tile = Color.dyn(RGBA(29, 29, 31, 0.08), RGBA(245, 245, 247, 0.1))
    static let bar = Color.dyn(RGBA(255, 255, 255, 0.5), RGBA(30, 30, 32, 0.5))
    static let barFg = Color.dyn(RGBA(0x1C1C1E), RGBA(0xEDEBEE))
    /// Menu bar ink: opaque black or white like the system's own menu bar text (`.primary` is
    /// 85% opaque, which rendered the items grey).
    static let barInk = Color.dyn(RGBA(0x000000), RGBA(0xFFFFFF))

    static let ink = Color.dyn(RGBA(0x1C1C1E), RGBA(0xEDEBEE))
    static let onInk = Color.dyn(RGBA(0xFFFFFF), RGBA(0x151416))
    /// Filled controls (a switch that is on, the main button): ink, so color stays with the data.
    static let accent = ink
    static let onAccent = onInk
    /// A plain wallpaper for the About page's laptop when the desktop picture can't be read.
    static let wall = Color.dyn(RGBA(0xE8E8EB), RGBA(0x232226))

    // Status
    static let ok = Color.dyn(RGBA(0x17844A), RGBA(0x5ED38C))
    static let okBg = Color.dyn(RGBA(23, 132, 74, 0.1), RGBA(94, 211, 140, 0.14))
    static let warn = Color.dyn(RGBA(0xC78A00), RGBA(0xF5C24C))
    static let warnBg = Color.dyn(RGBA(199, 138, 0, 0.12), RGBA(245, 194, 76, 0.14))
    static let danger = Color.dyn(RGBA(0xD93A31), RGBA(0xFF5A52))
    static let dangerBg = Color.dyn(RGBA(217, 58, 49, 0.1), RGBA(255, 90, 82, 0.14))
    static let dangerFill = Color.dyn(RGBA(0xD93A31), RGBA(0xFF5A52))
    static let onDanger = Color.dyn(RGBA(0xFFFFFF), RGBA(0x151416))

    // Data: one hue per module, one step darker on white so it holds.
    static let cpu = Color.dyn(RGBA(0x2B6BE8), RGBA(0x4D8EFF))
    static let sys = Color.dyn(RGBA(0xA9C5FB), RGBA(0x2F5FC4))
    static let gpu = Color.dyn(RGBA(0x6E9A12), RGBA(0xB6DB4C))
    static let mem = Color.dyn(RGBA(0x8A4FE6), RGBA(0xB47CFF))
    static let memWired = Color.dyn(RGBA(0x5E2FB8), RGBA(0x7E4FD0))
    static let memCompressed = Color.dyn(RGBA(0xC7A6F5), RGBA(0xD6B8FF))
    static let memCache = Color.dyn(RGBA(138, 79, 230, 0.25), RGBA(180, 124, 255, 0.35))
    static let down = Color.dyn(RGBA(0x0B9BB8), RGBA(0x3FCBE3))
    static let up = Color.dyn(RGBA(0x8EDCEB), RGBA(0x1E8FA6))
    static let read = Color.dyn(RGBA(0x4F58E0), RGBA(0x7C86FF))
    static let write = Color.dyn(RGBA(0xA9AEF7), RGBA(0x4B55C9))
    static let disk = read
    static let purgeable = Color.dyn(RGBA(79, 88, 224, 0.3), RGBA(124, 134, 255, 0.45))
    /// Temperature and power.
    static let temp = Color.dyn(RGBA(0xEE7A1E), RGBA(0xFF9B54))
    /// Battery and device levels use the status colors.
    static let bat = ok
    static let chargeBand = Color.dyn(RGBA(23, 132, 74, 0.08), RGBA(94, 211, 140, 0.1))

    // Menu bar items keep Apple's vivid colors: they sit on the system menu bar, not on glass.
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

    static func color(for module: Module) -> Color {
        switch module {
        case .cpu: return cpu
        case .gpu: return gpu
        case .memory: return mem
        case .network: return down
        case .disk: return disk
        case .battery: return bat
        case .bluetooth: return down
        case .sensors: return temp
        }
    }
}

/// Soft two-layer shadow under raised controls.
struct RaisedShadow: ViewModifier {
    var on = true

    func body(content: Content) -> some View {
        content
            .shadow(color: on ? Theme.raisedShadowNear : .clear, radius: 1, y: 1)
            .shadow(color: on ? Theme.raisedShadowFar : .clear, radius: 5, y: 3)
    }
}

extension View {
    func raisedShadow(_ on: Bool = true) -> some View { modifier(RaisedShadow(on: on)) }
}

/// Space Grotesk for the window and panels (bundled, OFL); the menu bar keeps the system font.
enum Fonts {
    private static var registered = false
    private static var cache: [String: Font] = [:]
    private static let lock = NSLock()

    static func register() {
        guard !registered, let url = Bundle.main.url(forResource: "SpaceGrotesk", withExtension: "ttf") else { return }
        registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

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

    /// Space Grotesk at an exact weight (variable font, 300...700), tabular figures. Menu bar
    /// previews use this directly so they keep the menu bar's own sizes.
    static func ui(_ size: CGFloat, _ weight: CGFloat = 400) -> Font {
        let key = "\(size)-\(weight)"
        lock.lock(); defer { lock.unlock() }
        if let f = cache[key] { return f }
        register()
        let wght: UInt32 = 0x7767_6874 // 'wght'
        let base = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: "Space Grotesk",
            kCTFontVariationAttribute: [NSNumber(value: wght): NSNumber(value: Double(weight))],
        ] as CFDictionary)
        let tabular = CTFontDescriptorCreateCopyWithFeature(base, kNumberSpacingType as CFNumber, kMonospacedNumbersSelector as CFNumber)
        let font = Font(CTFontCreateWithFontDescriptor(tabular, size, nil))
        cache[key] = font
        return font
    }
}
