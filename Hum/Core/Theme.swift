import AppKit
import CoreText
import SwiftUI

/// Design tokens from the Hum canvas (light / dark pairs). Surfaces are neutral and
/// translucent; color is reserved for data, so a value reads the same everywhere.
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
    static let glass = Color.dyn(RGBA(255, 255, 255, 0.62), RGBA(38, 38, 40, 0.6))
    static let side = Color.dyn(RGBA(255, 255, 255, 0.28), RGBA(20, 20, 22, 0.25))
    static let glassRim = Color.dyn(RGBA(255, 255, 255, 0.8), RGBA(255, 255, 255, 0.14))
    static let glassEdge = Color.dyn(RGBA(0, 0, 0, 0.08), RGBA(0, 0, 0, 0.5))
    static let menu = Color.dyn(RGBA(250, 250, 250, 0.82), RGBA(48, 48, 50, 0.85))

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

    static let text = Color.dyn(RGBA(0x1D1D1D), RGBA(0xF2F2F2))
    static let sub = Color.dyn(RGBA(0x5C5C5C), RGBA(0xABABAB))
    static let faint = Color.dyn(RGBA(0x8C8C8C), RGBA(0x7E7E7E))
    static let track = Color.dyn(RGBA(0, 0, 0, 0.07), RGBA(255, 255, 255, 0.1))
    static let grid = Color.dyn(RGBA(0, 0, 0, 0.07), RGBA(255, 255, 255, 0.08))
    static let cache = Color.dyn(RGBA(0, 0, 0, 0.18), RGBA(255, 255, 255, 0.22))
    static let cross = Color.dyn(RGBA(0, 0, 0, 0.3), RGBA(255, 255, 255, 0.35))
    static let rim = Color.dyn(RGBA(29, 29, 31, 0.4), RGBA(245, 245, 247, 0.45))
    static let tile = Color.dyn(RGBA(29, 29, 31, 0.08), RGBA(245, 245, 247, 0.1))
    static let bar = Color.dyn(RGBA(255, 255, 255, 0.5), RGBA(30, 30, 32, 0.5))
    static let barFg = Color.dyn(RGBA(0x1D1D1D), RGBA(0xF2F2F2))
    /// Menu bar ink: opaque black or white like the system's own menu bar text (`.primary` is
    /// 85% opaque, which rendered the items grey).
    static let barInk = Color.dyn(RGBA(0x000000), RGBA(0xFFFFFF))

    static let ink = Color.dyn(RGBA(0x1D1D1D), RGBA(0xF2F2F2))
    static let onInk = Color.dyn(RGBA(0xFFFFFF), RGBA(0x1D1D1D))
    /// The design canvas's mint wallpaper, on the About page's laptop when the desktop picture can't be read.
    static let wall = Color.dyn(RGBA(0xCDE5CE), RGBA(0x1F3527))

    // Status
    static let ok = Color.dyn(RGBA(0x316A3C), RGBA(0x8FD09C))
    static let okBg = Color.dyn(RGBA(79, 143, 92, 0.15), RGBA(127, 192, 140, 0.18))
    static let warn = Color.dyn(RGBA(0x85541A), RGBA(0xF0C080))
    static let warnBg = Color.dyn(RGBA(201, 138, 62, 0.18), RGBA(226, 168, 98, 0.2))
    static let danger = Color.dyn(RGBA(0xB23F2C), RGBA(0xF09A88))
    static let dangerBg = Color.dyn(RGBA(196, 80, 60, 0.12), RGBA(238, 138, 120, 0.16))
    static let dangerFill = Color.dyn(RGBA(0xB23F2C), RGBA(0xE07A66))
    static let onDanger = Color.dyn(RGBA(0xFFFFFF), RGBA(0x1D1D1D))

    // Data
    static let cpu = Color.dyn(RGBA(0x4F8F5C), RGBA(0x7FC08C))
    static let sys = Color.dyn(RGBA(0xC98A3E), RGBA(0xE2A862))
    static let gpu = Color.dyn(RGBA(0xC05A7C), RGBA(0xE890AC))
    static let mem = Color.dyn(RGBA(0x6A64A8), RGBA(0xA49EDB))
    static let down = Color.dyn(RGBA(0x4F7FB0), RGBA(0x86AEDB))
    static let up = Color.dyn(RGBA(0xC98A3E), RGBA(0xE2A862))
    static let read = Color.dyn(RGBA(0x4F7FB0), RGBA(0x86AEDB))
    static let write = Color.dyn(RGBA(0x9A6AA8), RGBA(0xC9A0D6))
    static let disk = Color.dyn(RGBA(0x3D8C88), RGBA(0x73C2BC))
    static let temp = Color.dyn(RGBA(0xC4683F), RGBA(0xE69470))
    static let bat = Color.dyn(RGBA(0x4F8F5C), RGBA(0x7FC08C))

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

/// The user-selectable accent. Graphite (ink) is the default; "system" follows the macOS accent.
enum AccentPalette: String, Codable, CaseIterable, Identifiable {
    case system, green, teal, indigo, orange, graphite

    var id: String { rawValue }

    var colors: AccentColors {
        switch self {
        case .system: return AccentColors(accent: Color(nsColor: .controlAccentColor), onAccent: .white)
        case .green: return AccentColors(accent: .dyn(RGBA(0x22A45D), RGBA(0x30D158)), onAccent: .white)
        case .teal: return AccentColors(accent: .dyn(RGBA(0x0F9D8A), RGBA(0x2CC5AE)), onAccent: .white)
        case .indigo: return AccentColors(accent: .dyn(RGBA(0x5856D6), RGBA(0x7D7AFF)), onAccent: .white)
        case .orange: return AccentColors(accent: .dyn(RGBA(0xF7821B), RGBA(0xFF9F2E)), onAccent: .white)
        case .graphite: return AccentColors(accent: Theme.ink, onAccent: Theme.onInk)
        }
    }

    /// Swatch shown in the accent picker.
    var swatch: Color { colors.accent }
}

struct AccentColors {
    var accent: Color
    var onAccent: Color
}

private struct AccentKey: EnvironmentKey {
    static let defaultValue = AccentPalette.graphite.colors
}

extension EnvironmentValues {
    var accent: AccentColors {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
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
    static func text(_ size: CGFloat, _ weight: CGFloat = 400, scale: CGFloat = 1) -> Font {
        scale == 1 ? ui(size, weight) : ui((size * scale * 2).rounded() / 2, weight)
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
