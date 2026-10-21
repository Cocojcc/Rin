import AppKit
import CoreText
import SwiftUI

/// Design tokens (light / dark pairs), in the night-sakura palette (夜樱): plum-ink text on faintly
/// pink glass, sakura rose and plum for data with slate blue for traffic, jade for all is well,
/// vermilion only for alerts and her seal. Color is reserved for data and state, so a value reads
/// the same everywhere.
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
    // Glass surfaces
    static let glass = Color.dyn(RGBA(252, 248, 249, 0.64), RGBA(42, 36, 40, 0.62))
    /// The main window's tint: more solid than the dropdowns' glass, so dense pages read the same
    /// over any wallpaper or window behind them.
    static let windowGlass = Color.dyn(RGBA(252, 248, 249, 0.84), RGBA(42, 36, 40, 0.82))
    static let side = Color.dyn(RGBA(255, 255, 255, 0.28), RGBA(20, 20, 22, 0.25))
    static let glassRim = Color.dyn(RGBA(255, 255, 255, 0.8), RGBA(255, 255, 255, 0.14))
    static let glassEdge = Color.dyn(RGBA(0, 0, 0, 0.08), RGBA(0, 0, 0, 0.5))
    static let menu = Color.dyn(RGBA(250, 246, 247, 0.84), RGBA(52, 45, 50, 0.86))

    // Raised controls (selected segments, sidebar selection, inline values)
    static let raised = Color.dyn(RGBA(0xFFFFFF), RGBA(255, 255, 255, 0.2))
    static let raisedShadowNear = Color.dyn(RGBA(0, 0, 0, 0.08), RGBA(0, 0, 0, 0.3))
    static let raisedShadowFar = Color.dyn(RGBA(0, 0, 0, 0.06), RGBA(0, 0, 0, 0))

    // Liquid-glass controls: a track behind segmented groups, a thumb for the selected piece.
    static let lgFill = Color.dyn(RGBA(255, 255, 255, 0.05), RGBA(255, 255, 255, 0.03))
    static let lgEdgeLight = Color.dyn(RGBA(255, 255, 255, 0.55), RGBA(255, 255, 255, 0.1))
    static let lgEdgeLine = Color.dyn(RGBA(0, 0, 0, 0.1), RGBA(255, 255, 255, 0.1))
    // The design asks for 7–8% white, which barely shows on the real window; filled enough to read as selected.
    static let lgThumb = Color.dyn(RGBA(255, 255, 255, 0.78), RGBA(255, 255, 255, 0.16))
    static let lgThumbLight = Color.dyn(RGBA(255, 255, 255, 0.8), RGBA(255, 255, 255, 0.28))
    static let lgThumbRing = Color.dyn(RGBA(255, 255, 255, 0.35), RGBA(255, 255, 255, 0.14))
    static let lgThumbLine = Color.dyn(RGBA(0, 0, 0, 0.14), RGBA(0, 0, 0, 0.5))
    static let lgThumbShadow = Color.dyn(RGBA(0, 0, 0, 0.12), RGBA(0, 0, 0, 0.45))
    static let lgHover = Color.dyn(RGBA(255, 255, 255, 0.4), RGBA(255, 255, 255, 0.08))

    static let well = Color.dyn(RGBA(0, 0, 0, 0.055), RGBA(255, 255, 255, 0.08))
    static let panel = Color.dyn(RGBA(0, 0, 0, 0.035), RGBA(255, 255, 255, 0.05))
    static let line = Color.dyn(RGBA(0, 0, 0, 0.08), RGBA(255, 255, 255, 0.1))

    static let text = Color.dyn(RGBA(0x221C1F), RGBA(0xF6F1F3))
    /// Secondary text, a step darker than the design's #5C5C5C / #ABABAB: small grey labels on
    /// glass read too faintly at the window's scale.
    static let sub = Color.dyn(RGBA(0x54494E), RGBA(0xBDB1B6))
    /// The quietest text (empty states, hints), dark enough for about 4.5 : 1 on the panels.
    static let faint = Color.dyn(RGBA(0x76696F), RGBA(0x988B91))
    static let track = Color.dyn(RGBA(0, 0, 0, 0.07), RGBA(255, 255, 255, 0.1))
    static let grid = Color.dyn(RGBA(0, 0, 0, 0.07), RGBA(255, 255, 255, 0.08))
    static let cache = Color.dyn(RGBA(0, 0, 0, 0.18), RGBA(255, 255, 255, 0.22))
    static let cross = Color.dyn(RGBA(0, 0, 0, 0.3), RGBA(255, 255, 255, 0.35))
    static let rim = Color.dyn(RGBA(29, 29, 31, 0.4), RGBA(245, 245, 247, 0.45))
    static let tile = Color.dyn(RGBA(29, 29, 31, 0.08), RGBA(245, 245, 247, 0.1))
    static let bar = Color.dyn(RGBA(255, 255, 255, 0.5), RGBA(30, 30, 32, 0.5))
    static let barFg = Color.dyn(RGBA(0x221C1F), RGBA(0xF6F1F3))
    /// Menu bar ink: opaque black or white like the system's own menu bar text (`.primary` is
    /// 85% opaque, which rendered the items grey).
    static let barInk = Color.dyn(RGBA(0x000000), RGBA(0xFFFFFF))

    static let ink = Color.dyn(RGBA(0x221C1F), RGBA(0xF6F1F3))
    static let onInk = Color.dyn(RGBA(0xFCF8F9), RGBA(0x221C1F))
    /// Filled controls (a switch that is on, the main button): ink, so the window stays grey.
    static let accent = ink
    static let onAccent = onInk
    /// Her seal's vermilion (朱), a touch brighter on dark so it doesn't sink.
    static let seal = Color.dyn(RGBA(0xC8402E), RGBA(0xD9533F))
    static let onSeal = Color.dyn(RGBA(0xFFF9F2), RGBA(0xFFF9F2))
    /// A soft wallpaper for the About page's laptop when the desktop picture can't be read.
    static let wall = Color.dyn(RGBA(0xEBDDE2), RGBA(0x2B2228))

    // Status
    static let ok = Color.dyn(RGBA(0x3F7A6A), RGBA(0x8CCBB8))
    static let okBg = Color.dyn(RGBA(63, 122, 106, 0.14), RGBA(140, 203, 184, 0.18))
    static let warn = Color.dyn(RGBA(0x8A6420), RGBA(0xE6C27E))
    static let warnBg = Color.dyn(RGBA(190, 150, 70, 0.18), RGBA(230, 194, 126, 0.18))
    static let danger = Color.dyn(RGBA(0xC8402E), RGBA(0xF08A74))
    static let dangerBg = Color.dyn(RGBA(200, 64, 46, 0.12), RGBA(240, 138, 116, 0.16))
    static let dangerFill = Color.dyn(RGBA(0xC8402E), RGBA(0xE0624C))
    static let onDanger = Color.dyn(RGBA(0xFFF9F2), RGBA(0x1B1D22))

    // Data: CPU's system share is the paler sakura beside its user rose.
    static let cpu = Color.dyn(RGBA(0xC4607A), RGBA(0xEE9BB0))
    static let sys = Color.dyn(RGBA(0xE6B3C0), RGBA(0x8E5A6A))
    static let gpu = Color.dyn(RGBA(0x9A7BC0), RGBA(0xC6B0E8))
    static let mem = Color.dyn(RGBA(0x7D4E8C), RGBA(0xC39AD6))
    static let down = Color.dyn(RGBA(0x5E7C9C), RGBA(0x9DB8D6))
    static let up = Color.dyn(RGBA(0xC4607A), RGBA(0xEE9BB0))
    static let read = Color.dyn(RGBA(0x5E7C9C), RGBA(0x9DB8D6))
    static let write = Color.dyn(RGBA(0x7D4E8C), RGBA(0xC39AD6))
    static let disk = Color.dyn(RGBA(0x5E8E8A), RGBA(0x96C6C0))
    static let temp = Color.dyn(RGBA(0xB88A5A), RGBA(0xE2BA8C))
    static let bat = Color.dyn(RGBA(0x6E9A72), RGBA(0xA6D0A8))

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

    /// The main window draws its text this much larger than the design's sizes. Its layout stays
    /// at the design's numbers (scaled by `UIScale`); only the type grows, so pages read
    /// comfortably at 85% without getting bigger. Dropdowns keep the design's sizes.
    static let windowTextScale: CGFloat = 1.08

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
