import SwiftUI

/// Line icon path data from the design canvas (16 × 16 viewBox unless noted).
enum Icons {
    static let cpu = "M5 3.5h6a1.5 1.5 0 0 1 1.5 1.5v6a1.5 1.5 0 0 1-1.5 1.5H5a1.5 1.5 0 0 1-1.5-1.5V5A1.5 1.5 0 0 1 5 3.5zM6.25 1.2v2.3M9.75 1.2v2.3M6.25 12.5v2.3M9.75 12.5v2.3M1.2 6.25h2.3M1.2 9.75h2.3M12.5 6.25h2.3M12.5 9.75h2.3"
    static let cpuMenubar = "M5.5 3.5h5a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-5a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2zM6.85 6.25h2.3a.6.6 0 0 1 .6.6v2.3a.6.6 0 0 1-.6.6h-2.3a.6.6 0 0 1-.6-.6v-2.3a.6.6 0 0 1 .6-.6zM6.25 1.2v2.3M9.75 1.2v2.3M6.25 12.5v2.3M9.75 12.5v2.3M1.2 6.25h2.3M1.2 9.75h2.3M12.5 6.25h2.3M12.5 9.75h2.3"
    static let memory = "M2.7 4h10.6a1.5 1.5 0 0 1 1.5 1.5v4a1.5 1.5 0 0 1-1.5 1.5H2.7a1.5 1.5 0 0 1-1.5-1.5v-4A1.5 1.5 0 0 1 2.7 4zM4.5 6.6v1.8M8 6.6v1.8M11.5 6.6v1.8M3.5 11v2M6.5 11v2M9.5 11v2M12.5 11v2"
    static let network = "M5 13V3M2.5 5.5L5 3l2.5 2.5M11 3v10M8.5 10.5L11 13l2.5-2.5"
    static let disk = "M3 8.5h10a1.5 1.5 0 0 1 1.5 1.5v2a1.5 1.5 0 0 1-1.5 1.5H3A1.5 1.5 0 0 1 1.5 12v-2A1.5 1.5 0 0 1 3 8.5zM3 8.5L4.8 3h6.4L13 8.5M8.5 11h3"
    static let battery = "M2.5 4.5h9a1.5 1.5 0 0 1 1.5 1.5v4a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 1 10V6a1.5 1.5 0 0 1 1.5-1.5zM15 7v2M7.5 5.5L6 8h2.5L7 10.5"
    static let batteryOff = "M2.5 4.5h9a1.5 1.5 0 0 1 1.5 1.5v4a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 1 10V6a1.5 1.5 0 0 1 1.5-1.5zM15 7v2M2.5 2.5l11 11"
    static let sensors = "M9.5 9.6V3.5a1.5 1.5 0 0 0-3 0v6.1a3 3 0 1 0 3 0zM8 7v4.5"
    static let sensorsHot = "M9.5 9.6V3.5a1.5 1.5 0 0 0-3 0v6.1a3 3 0 1 0 3 0zM8 4.5v7"
    static let gpu = "M2.5 4h11a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1zM6 6a2 2 0 1 1 0 4a2 2 0 1 1 0-4zM10 6.5h2.5M10 9.5h2.5M3.5 12v1.5M6 12v1.5M8.5 12v1.5"
    static let overview = "M3 2.5h3.5a.5.5 0 0 1 .5.5v3.5a.5.5 0 0 1-.5.5H3a.5.5 0 0 1-.5-.5V3a.5.5 0 0 1 .5-.5zM9.5 2.5H13a.5.5 0 0 1 .5.5v3.5a.5.5 0 0 1-.5.5H9.5a.5.5 0 0 1-.5-.5V3a.5.5 0 0 1 .5-.5zM3 9h3.5a.5.5 0 0 1 .5.5V13a.5.5 0 0 1-.5.5H3a.5.5 0 0 1-.5-.5V9.5A.5.5 0 0 1 3 9zM9.5 9H13a.5.5 0 0 1 .5.5V13a.5.5 0 0 1-.5.5H9.5A.5.5 0 0 1 9 13V9.5a.5.5 0 0 1 .5-.5z"
    static let general = "M2.5 5h6M11.5 5h2M2.5 11h2M7.5 11h6M10 3.5a1.5 1.5 0 1 1 0 3a1.5 1.5 0 1 1 0-3zM6 9.5a1.5 1.5 0 1 1 0 3a1.5 1.5 0 1 1 0-3z"
    static let menubar = "M2.5 2.5h11a1.5 1.5 0 0 1 1.5 1.5v8a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 1 12V4a1.5 1.5 0 0 1 1.5-1.5zM1 5.5h14M9.5 4h1M12 4h1"
    static let alert = "M4 11V7a4 4 0 0 1 8 0v4l1.5 1.5h-11L4 11zM6.5 13.5a1.5 1.5 0 0 0 3 0"
    static let about = "M8 1.5a6.5 6.5 0 1 1 0 13a6.5 6.5 0 1 1 0-13zM8 7v4.5M8 4.75h.01"
    static let wifi = "M1.8 6.2a9 9 0 0 1 12.4 0M4.1 8.7a5.7 5.7 0 0 1 7.8 0M6.4 11.2a2.4 2.4 0 0 1 3.2 0"
    static let slash = "M2.5 2.5l11 11"
    static let check = "M3.5 8.5l3 3 6-7"
    static let drag = "M6 3h.01M10 3h.01M6 8h.01M10 8h.01M6 13h.01M10 13h.01"
    static let chevronRight = "M6 3.5L10.5 8L6 12.5"
    static let chevronLeft = "M10 3.5L5.5 8L10 12.5"
    static let close = "M4 4l8 8M12 4l-8 8"
    static let keyboard = "M2 4.5h12a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1H2a1 1 0 0 1-1-1v-5a1 1 0 0 1 1-1zM4 7h.01M6.5 7h.01M9 7h.01M11.5 7h.01M5 9.5h6"
    static let mouse = "M8 1.5a4 4 0 0 1 4 4v5a4 4 0 0 1-8 0v-5a4 4 0 0 1 4-4zM8 4v2.5"
    static let trackpad = "M2.5 3.5h11a1 1 0 0 1 1 1v7a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1v-7a1 1 0 0 1 1-1z"
    static let headphones = "M5.5 2.5a2 2 0 0 1 2 2v1a2 2 0 0 1-2 2v6M10.5 2.5a2 2 0 0 0-2 2v1a2 2 0 0 0 2 2v6"
    static let ups = "M3.5 2.5h9a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1h-9a1 1 0 0 1-1-1v-9a1 1 0 0 1 1-1zM8.5 4.5L6.5 8h3l-2 3.5"
    static let appMark = "M7 16.5v-3M12 16.5v-9M17 16.5v-6"   // 24 × 24
    static let power = "M8 1.5v6M4.4 3.9a5.5 5.5 0 1 0 7.2 0"
    static let quit = "M6 2.5H3.5a1 1 0 0 0-1 1v9a1 1 0 0 0 1 1H6M10 11l3-3-3-3M13 8H6"
    static let activity = "M1.5 8h3l2-5 3 10 2-5h3"

    static func module(_ m: Module) -> String {
        switch m {
        case .cpu: return cpu
        case .gpu: return gpu
        case .memory: return memory
        case .network: return network
        case .disk: return disk
        case .battery: return battery
        case .sensors: return sensors
        }
    }
}

/// Up arrow over down arrow, the network glyph used in the menu bar (12 × 40 viewBox).
struct NetArrows: View {
    var upColor: Color = .primary
    var downColor: Color = .primary
    var upOnTop = true
    var height: CGFloat = 20

    var body: some View {
        Canvas { ctx, size in
            let s = size.height / 40
            let up = SVGShape(d: "M6 19V3M1.3 9.5L6 3L10.7 9.5", viewBox: CGSize(width: 12, height: 40)).path(in: CGRect(origin: .zero, size: size))
            let down = SVGShape(d: "M6 21v16M1.3 30.5L6 37L10.7 30.5", viewBox: CGSize(width: 12, height: 40)).path(in: CGRect(origin: .zero, size: size))
            let style = StrokeStyle(lineWidth: 2 * s, lineCap: .round, lineJoin: .round)
            if upOnTop {
                ctx.stroke(up, with: .color(upColor), style: style)
                ctx.stroke(down, with: .color(downColor), style: style)
            } else {
                // Flip: download arrow on top pointing down, upload below pointing up.
                let flipUp = SVGShape(d: "M6 21v16M1.3 27.5L6 21L10.7 27.5", viewBox: CGSize(width: 12, height: 40)).path(in: CGRect(origin: .zero, size: size))
                let flipDown = SVGShape(d: "M6 19V3M1.3 12.5L6 19L10.7 12.5", viewBox: CGSize(width: 12, height: 40)).path(in: CGRect(origin: .zero, size: size))
                ctx.stroke(flipDown, with: .color(downColor), style: style)
                ctx.stroke(flipUp, with: .color(upColor), style: style)
            }
        }
        .frame(width: height * 12 / 40, height: height)
        .accessibilityHidden(true)
    }
}

/// The menu bar battery glyph (25 × 12): rim, fill and optional charging bolt.
struct BatteryGlyph: View {
    var level: Double
    var charging = false
    var fill: Color = .primary
    var rim: Color = .primary.opacity(0.45)
    var scale: CGFloat = 1

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 25
            let outer = Path(roundedRect: CGRect(x: 0.75 * s, y: 0.75 * s, width: 21 * s, height: 10.5 * s), cornerRadius: 3 * s)
            ctx.stroke(outer, with: .color(rim), lineWidth: 1 * s)
            let width = max(1.2, 18 * min(1, max(0, level))) * s
            let inner = Path(roundedRect: CGRect(x: 2.25 * s, y: 2.25 * s, width: width, height: 7.5 * s), cornerRadius: 1.6 * s)
            ctx.fill(inner, with: .color(fill))
            var cap = Path()
            cap.move(to: CGPoint(x: 23.6 * s, y: 4.3 * s))
            cap.addLine(to: CGPoint(x: 23.6 * s, y: 7.7 * s))
            ctx.stroke(cap, with: .color(rim), style: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round))
            if charging {
                // Knock the bolt out of the fill so the menu bar shows through, as the system glyph does.
                let bolt = SVGShape(d: "M11 2.6L8.2 6.6h2l-0.7 2.8 2.9-4h-2z", viewBox: CGSize(width: 25, height: 12)).path(in: CGRect(origin: .zero, size: size))
                var cut = ctx
                cut.blendMode = .destinationOut
                cut.fill(bolt, with: .color(.black))
                cut.stroke(bolt, with: .color(.black), lineWidth: 0.8 * s)
            }
        }
        .frame(width: 25 * scale, height: 12 * scale)
        .accessibilityHidden(true)
    }
}

/// Sparkline with a soft area fill, drawn to fill its frame. Values are 0...1.
struct Sparkline: View {
    var values: [Double]
    var color: Color = .primary
    var lineWidth: CGFloat = 1.25
    var fillOpacity: Double = 0.25
    var secondary: [Double]? = nil
    var secondaryColor: Color? = nil
    var minCount = 30

    var body: some View {
        Canvas { ctx, size in
            draw(ctx, size, values, color, fillOpacity)
            if let secondary { draw(ctx, size, secondary, secondaryColor ?? color.opacity(0.6), fillOpacity * 0.9) }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ data: [Double], _ color: Color, _ fill: Double) {
        guard !data.isEmpty else { return }
        let count = max(data.count, minCount)
        let step = size.width / CGFloat(max(count - 1, 1))
        let offset = CGFloat(count - data.count) * step
        var line = Path()
        for (i, v) in data.enumerated() {
            let p = CGPoint(x: offset + CGFloat(i) * step, y: size.height - CGFloat(min(1, max(0, v))) * (size.height - lineWidth) - lineWidth / 2)
            if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
        }
        if fill > 0 {
            var area = line
            area.addLine(to: CGPoint(x: offset + CGFloat(data.count - 1) * step, y: size.height))
            area.addLine(to: CGPoint(x: offset, y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .color(color.opacity(fill)))
        }
        ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}
