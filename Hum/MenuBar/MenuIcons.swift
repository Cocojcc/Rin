import SwiftUI

/// One icon an icon widget can show: an outline, sometimes a filled block, or the module's
/// short name in a rounded box.
struct MenuIcon {
    var stroke: String = ""
    var lineWidth: CGFloat = 1.4
    /// A filled rounded block inside the outline (the solid chip, the upright battery).
    var fill: CGRect? = nil
    var fillRadius: CGFloat = 0
    var wordmark = false
}

/// Each module's six menu bar icons, from the design's pick sheet (network keeps its four).
enum MenuIcons {
    private static let gauge = MenuIcon(stroke: "M2 11.5a6 6 0 1 1 12 0M8 11.5l2.6-3.4M4.2 7.4l.9.6M8 5.5v1M11.8 7.4l-.9.6")
    private static let pie = MenuIcon(stroke: "M7.2 2.6a5.6 5.6 0 1 0 6.2 6.2H7.2zM9 1.4a5.6 5.6 0 0 1 5.6 5.6H9z")
    private static let wordmark = MenuIcon(wordmark: true)

    static func all(_ m: Module) -> [MenuIcon] {
        switch m {
        case .cpu: return [
            MenuIcon(stroke: Icons.cpu),
            MenuIcon(stroke: "M6.25 1.2v2.3M9.75 1.2v2.3M6.25 12.5v2.3M9.75 12.5v2.3M1.2 6.25h2.3M1.2 9.75h2.3M12.5 6.25h2.3M12.5 9.75h2.3",
                     fill: CGRect(x: 3.5, y: 3.5, width: 9, height: 9), fillRadius: 1.6),
            MenuIcon(stroke: "M3 3h4v4H3zM9 3h4v4H9zM3 9h4v4H3zM9 9h4v4H9z"),
            gauge,
            MenuIcon(stroke: "M1.5 8.5h3l1.5-4 3 8 1.5-4h4"),
            wordmark,
        ]
        case .gpu: return [
            MenuIcon(stroke: Icons.gpu),
            MenuIcon(stroke: "M8 1.8l5.6 3.1v6.2L8 14.2l-5.6-3.1V4.9zM2.4 4.9L8 8l5.6-3.1M8 8v6.2"),
            MenuIcon(stroke: "M2.5 3h11a1 1 0 0 1 1 1v6.5a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM6 14h4M8 11.5V14M6.5 5.5h3v3h-3z"),
            MenuIcon(stroke: "M2.5 3h11a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM4.5 10l2.2-2.6 2 1.6 3-3.6"),
            gauge,
            wordmark,
        ]
        case .memory: return [
            MenuIcon(stroke: Icons.memory),
            MenuIcon(stroke: "M3 4.5h10v7H3zM5.5 4.5V2.5M8 4.5V2.5M10.5 4.5V2.5M5.5 11.5v2M8 11.5v2M10.5 11.5v2"),
            MenuIcon(stroke: "M8 2.5l6 3-6 3-6-3zM2 8.5l6 3 6-3M2 11.5l6 3 6-3"),
            pie,
            gauge,
            wordmark,
        ]
        case .network: return [
            MenuIcon(stroke: Icons.network),
            MenuIcon(stroke: Icons.gauge),
            MenuIcon(stroke: Icons.wave),
            MenuIcon(stroke: Icons.monitorWindow),
        ]
        case .disk: return [
            MenuIcon(stroke: Icons.disk),
            MenuIcon(stroke: "M2.5 4.5h11a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1v-5a1 1 0 0 1 1-1zM4.5 7h3.5v2H4.5zM11 7h.01M12.6 7h.01M11 9h.01M12.6 9h.01"),
            MenuIcon(stroke: "M3 4c0-1.1 2.2-2 5-2s5 .9 5 2v8c0 1.1-2.2 2-5 2s-5-.9-5-2zM3 4c0 1.1 2.2 2 5 2s5-.9 5-2M3 8c0 1.1 2.2 2 5 2s5-.9 5-2"),
            MenuIcon(stroke: "M8 2a6 6 0 1 1 0 12a6 6 0 1 1 0-12zM8 6.6a1.4 1.4 0 1 1 0 2.8a1.4 1.4 0 1 1 0-2.8zM12.6 3.6L9.3 7"),
            pie,
            wordmark,
        ]
        case .battery: return [
            MenuIcon(stroke: Icons.battery),
            MenuIcon(stroke: "M5.5 3.5h5a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1h-5a1 1 0 0 1-1-1v-9a1 1 0 0 1 1-1zM7 1.8h2",
                     fill: CGRect(x: 6, y: 7, width: 4, height: 6), fillRadius: 0.6),
            MenuIcon(stroke: "M9 1.5L4 9h4l-1 5.5L12 7H8z"),
            MenuIcon(stroke: "M6 1.5v3M10 1.5v3M4 4.5h8V7a4 4 0 0 1-8 0zM8 11v3.5"),
            gauge,
            wordmark,
        ]
        case .sensors: return [
            MenuIcon(stroke: Icons.sensors),
            MenuIcon(stroke: Icons.sensors + "M11.5 4.2h2M11.5 6.6h2M11.5 9h2"),
            MenuIcon(stroke: "M8 14.2a4.2 4.2 0 0 0 4.2-4.2c0-3-3-4.4-3-8.4-2.2 1.4-5.4 4-5.4 8.4A4.2 4.2 0 0 0 8 14.2zM8 14.2a1.7 1.7 0 0 1-1.7-1.7c0-1.1.9-1.9 1.7-3 .8 1.1 1.7 1.9 1.7 3A1.7 1.7 0 0 1 8 14.2z"),
            MenuIcon(stroke: Icons.fan),
            MenuIcon(stroke: "M8 1.5v13M2.4 4.75l11.2 6.5M2.4 11.25l11.2-6.5M6.4 2.4L8 4l1.6-1.6M6.4 13.6L8 12l1.6 1.6"),
            wordmark,
        ]
        }
    }

    static func icon(_ m: Module, _ index: Int) -> MenuIcon {
        let icons = all(m)
        return icons[min(max(0, index), icons.count - 1)]
    }
}

/// Draws a `MenuIcon` 16 pt tall (the wordmark is 20 pt wide) in the foreground color.
struct MenuIconView: View {
    var icon: MenuIcon
    var module: Module
    var size: CGFloat = 16
    @Environment(\.widgetUIFont) private var ui

    var body: some View {
        let s = size / 16
        if icon.wordmark {
            RoundedRectangle(cornerRadius: 3 * s, style: .continuous)
                .strokeBorder(.foreground, lineWidth: 1.3 * s)
                .frame(width: 19.8 * s, height: 12.8 * s)
                .overlay { BarText(module.widgetLabel, font: BarFont.font(6.6 * s, 700, ui: ui)) }
                .frame(width: 20 * s, height: size)
        } else {
            LineIcon(d: icon.stroke, size: size, lineWidth: icon.lineWidth)
                .overlay {
                    if let r = icon.fill {
                        Canvas { ctx, _ in
                            let rect = CGRect(x: r.minX * s, y: r.minY * s, width: r.width * s, height: r.height * s)
                            ctx.fill(Path(roundedRect: rect, cornerRadius: icon.fillRadius * s), with: .foreground)
                        }
                    }
                }
        }
    }
}
