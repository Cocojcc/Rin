import AppKit
import SwiftUI

/// Design tokens from the Hum canvas (light / dark pairs). Data colors are shared by the
/// menu bar, popovers and monitor pages so a value reads the same everywhere.
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
    // Surfaces
    static let content = Color.dyn(RGBA(0xF5F5F7), RGBA(0x1C1C1E))
    static let side = Color.dyn(RGBA(232, 232, 236, 1), RGBA(38, 38, 42, 1))
    static let text = Color.dyn(RGBA(0x1D1D1F), RGBA(0xF5F5F7))
    static let sub = Color.dyn(RGBA(0x6E6E73), RGBA(0x98989D))
    static let faint = Color.dyn(RGBA(0x8E8E93), RGBA(0x7C7C82))
    static let group = Color.dyn(RGBA(0xFFFFFF), RGBA(0x2A2A2D))
    static let groupRim = Color.dyn(RGBA(0, 0, 0, 0.06), RGBA(255, 255, 255, 0.06))
    static let line = Color.dyn(RGBA(0, 0, 0, 0.07), RGBA(255, 255, 255, 0.07))
    static let chip = Color.dyn(RGBA(0, 0, 0, 0.055), RGBA(255, 255, 255, 0.08))
    static let well = chip
    static let segOn = Color.dyn(RGBA(0xFFFFFF), RGBA(0x56565B))
    static let rim = Color.dyn(RGBA(29, 29, 31, 0.4), RGBA(245, 245, 247, 0.45))
    static let track = Color.dyn(RGBA(0, 0, 0, 0.07), RGBA(255, 255, 255, 0.1))
    static let grid = Color.dyn(RGBA(0, 0, 0, 0.06), RGBA(255, 255, 255, 0.07))
    static let tip = Color.dyn(RGBA(0xFFFFFF), RGBA(0x3A3A3E))
    static let tipRim = Color.dyn(RGBA(0, 0, 0, 0.1), RGBA(255, 255, 255, 0.12))
    static let cross = Color.dyn(RGBA(29, 29, 31, 0.35), RGBA(245, 245, 247, 0.4))
    static let hover = Color.dyn(RGBA(0, 0, 0, 0.05), RGBA(255, 255, 255, 0.07))
    static let cache = Color.dyn(RGBA(0, 0, 0, 0.16), RGBA(255, 255, 255, 0.2))

    // Popover
    static let pop = Color.dyn(RGBA(238, 238, 242, 0.97), RGBA(36, 36, 40, 0.97))
    static let popRim = Color.dyn(RGBA(0, 0, 0, 0.14), RGBA(255, 255, 255, 0.12))
    static let popGroup = Color.dyn(RGBA(0xFFFFFF), RGBA(0x2E2E32))

    // Status
    static let danger = Color.dyn(RGBA(0xD70015), RGBA(0xD93A2F))
    static let dangerBg = Color.dyn(RGBA(255, 59, 48, 0.1), RGBA(255, 69, 58, 0.18))
    static let dangerText = Color.dyn(RGBA(0xC4211A), RGBA(0xFF8A80))
    static let warnBg = Color.dyn(RGBA(245, 135, 10, 0.14), RGBA(255, 159, 10, 0.2))
    static let warnText = Color.dyn(RGBA(0xA85A00), RGBA(0xFFB340))
    static let ok = Color.dyn(RGBA(0x1E8E3E), RGBA(0x30D158))
    static let okBg = Color.dyn(RGBA(40, 167, 69, 0.12), RGBA(48, 209, 88, 0.16))
    static let low = Color.dyn(RGBA(0xD70015), RGBA(0xFF453A))

    // Data
    static let cpu = Color.dyn(RGBA(0x28A745), RGBA(0x30D158))
    static let cpuSoft = Color.dyn(RGBA(40, 167, 69, 0.22), RGBA(48, 209, 88, 0.28))
    static let sys = Color.dyn(RGBA(0xF5870A), RGBA(0xFF9F0A))
    static let gpu = Color.dyn(RGBA(0xE0457B), RGBA(0xFF6B98))
    static let mem = Color.dyn(RGBA(0x5856D6), RGBA(0x7D7AFF))
    static let down = Color.dyn(RGBA(0x0A7AFF), RGBA(0x0A84FF))
    static let up = Color.dyn(RGBA(0xF5870A), RGBA(0xFF9F0A))
    static let read = Color.dyn(RGBA(0x0A7AFF), RGBA(0x0A84FF))
    static let write = Color.dyn(RGBA(0xAF52DE), RGBA(0xBF5AF2))
    static let disk = Color.dyn(RGBA(0x1A9CB0), RGBA(0x40C8E0))
    static let temp = Color.dyn(RGBA(0xF2603C), RGBA(0xFF6B4A))
    static let bat = Color.dyn(RGBA(0x28A745), RGBA(0x30D158))

    // Menu bar states
    static let barWarn = NSColor.dynamic(RGBA(0xB25000), RGBA(0xFF9F0A))
    static let barCrit = NSColor.dynamic(RGBA(0xD70015), RGBA(0xFF453A))

    static func color(for module: Module) -> Color {
        switch module {
        case .cpu: return cpu
        case .gpu: return gpu
        case .memory: return mem
        case .network: return down
        case .disk: return disk
        case .battery: return bat
        case .sensors: return temp
        }
    }
}

/// The user-selectable accent. Orange is the brand color; "system" follows the macOS accent.
enum AccentPalette: String, Codable, CaseIterable, Identifiable {
    case system, green, teal, indigo, orange, graphite

    var id: String { rawValue }

    private var values: (RGBA, RGBA, RGBA, RGBA, RGBA, RGBA)? {
        switch self {
        case .system: return nil
        case .green: return (RGBA(0x22A45D), RGBA(0x30D158), RGBA(34, 164, 93, 0.13), RGBA(48, 209, 88, 0.2), RGBA(0x17763F), RGBA(0x6EE59A))
        case .teal: return (RGBA(0x0F9D8A), RGBA(0x2CC5AE), RGBA(15, 157, 138, 0.13), RGBA(44, 197, 174, 0.2), RGBA(0x0B7A6B), RGBA(0x6ADBC8))
        case .indigo: return (RGBA(0x5856D6), RGBA(0x7D7AFF), RGBA(88, 86, 214, 0.12), RGBA(125, 122, 255, 0.22), RGBA(0x4644B8), RGBA(0xB0AEFF))
        case .orange: return (RGBA(0xF7821B), RGBA(0xFF9F2E), RGBA(247, 130, 27, 0.13), RGBA(255, 159, 46, 0.2), RGBA(0xB3570A), RGBA(0xFFB766))
        case .graphite: return (RGBA(0x1D1D1F), RGBA(0xF5F5F7), RGBA(0, 0, 0, 0.07), RGBA(255, 255, 255, 0.12), RGBA(0x1D1D1F), RGBA(0xF5F5F7))
        }
    }

    var colors: AccentColors {
        guard let v = values else {
            let accent = NSColor.controlAccentColor
            return AccentColors(
                accent: Color(nsColor: accent),
                tint: Color(nsColor: accent.withAlphaComponent(0.14)),
                tintText: Color(nsColor: NSColor(name: nil) { ap in
                    let base = accent.usingColorSpace(.sRGB) ?? accent
                    return ap.isDark ? base.blended(withFraction: 0.35, of: .white) ?? base
                                     : base.blended(withFraction: 0.25, of: .black) ?? base
                }),
                onAccent: .white
            )
        }
        return AccentColors(
            accent: .dyn(v.0, v.1),
            tint: .dyn(v.2, v.3),
            tintText: .dyn(v.4, v.5),
            onAccent: self == .graphite ? .dyn(RGBA(0xFFFFFF), RGBA(0x1D1D1F)) : .white
        )
    }

    /// Swatch shown in the accent picker.
    var swatch: Color {
        if self == .system { return Color(nsColor: .controlAccentColor) }
        return colors.accent
    }
}

struct AccentColors {
    var accent: Color
    var tint: Color
    var tintText: Color
    var onAccent: Color
}

private struct AccentKey: EnvironmentKey {
    static let defaultValue = AccentPalette.orange.colors
}

extension EnvironmentValues {
    var accent: AccentColors {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}

enum Fonts {
    /// Rounded heavy numerals used for headline values.
    static func big(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
}
