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
    static let wifi = "M1.8 6.2a9 9 0 0 1 12.4 0M4.1 8.7a5.7 5.7 0 0 1 7.8 0M6.4 11.2a2.4 2.4 0 0 1 3.2 0M8 13.4h.01"
    static let slash = "M2.5 2.5l11 11"
    static let check = "M3.5 8.5l3 3 6-7"
    static let drag = "M6 3h.01M10 3h.01M6 8h.01M10 8h.01M6 13h.01M10 13h.01"
    static let chevronRight = "M6 3.5L10.5 8L6 12.5"
    static let chevronLeft = "M10 3.5L5.5 8L10 12.5"
    static let close = "M4 4l8 8M12 4l-8 8"
    static let ups = "M3.5 2.5h9a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1h-9a1 1 0 0 1-1-1v-9a1 1 0 0 1 1-1zM8.5 4.5L6.5 8h3l-2 3.5"
    static let appMark = "M7 16.5v-3M12 16.5v-9M17 16.5v-6"   // 24 × 24
    static let power = "M8 1.75v5.5M4.6 4a5.25 5.25 0 1 0 6.8 0"
    static let quit = "M6 2.5H3.5a1 1 0 0 0-1 1v9a1 1 0 0 0 1 1H6M10 11l3-3-3-3M13 8H6"
    static let gear = "M13.02 6.65L14.62 6.95L14.62 9.05L13.02 9.35L12.50 10.60L13.42 11.94L11.94 13.42L10.60 12.50L9.35 13.02L9.05 14.62L6.95 14.62L6.65 13.02L5.40 12.50L4.06 13.42L2.58 11.94L3.50 10.60L2.98 9.35L1.38 9.05L1.38 6.95L2.98 6.65L3.50 5.40L2.58 4.06L4.06 2.58L5.40 3.50L6.65 2.98L6.95 1.38L9.05 1.38L9.35 2.98L10.60 3.50L11.94 2.58L13.42 4.06L12.50 5.40ZM10.1 8a2.1 2.1 0 1 1-4.2 0a2.1 2.1 0 1 1 4.2 0z"
    static let pause = "M5.75 3.5v9M10.25 3.5v9"
    static let play = "M5 3.2v9.6L12.8 8z"
    static let gauge = "M2 11.5a6 6 0 1 1 12 0M8 11.5l2.6-3.4M4.2 7.4l.9.6M8 5.5v1M11.8 7.4l-.9.6"
    static let wave = "M1.5 8.5h3l1.5-4 3 8 1.5-4h4"
    static let activity = "M1.5 8h3l2-5 3 10 2-5h3"
    static let monitorWindow = "M2.5 3h11a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM4.5 10l2.2-2.6 2 1.6 3-3.6"
    static let notch = "M2.5 3h11a1.5 1.5 0 0 1 1.5 1.5v7a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 1 11.5v-7A1.5 1.5 0 0 1 2.5 3zM6 3v1.3a1 1 0 0 0 1 1h2a1 1 0 0 0 1-1V3"
    static let fan = "M8 6.6c-.4-2.2.2-4.1 1.8-4.1s1.8 2.2-.6 4.1M9.3 8.6c2 .9 3.2 2.5 2.4 3.9s-2.8.7-3.3-2.2M6.8 8.9c-1.7 1.4-3.7 1.6-4.3.2s1.3-2.6 4.2-2.1M8 6.6a1.4 1.4 0 1 1 0 2.8a1.4 1.4 0 1 1 0-2.8z"
    static let upDown = "M1.5 4.5L4 2l2.5 2.5M1.5 7.5L4 10l2.5-2.5"     // 8 × 12
    static let chevronSmallRight = "M4.5 2.5L8 6l-3.5 3.5"             // 12 × 12
    static let chevronSmallLeft = "M7.5 2.5L4 6l3.5 3.5"               // 12 × 12
    static let minusSmall = "M2 5h6"                                   // 10 × 10
    static let plusSmall = "M2 5h6M5 2v6"                              // 10 × 10
    static let arrowUpSmall = "M3 5.4V0.9M1.1 2.7L3 0.8L4.9 2.7"       // 6 × 6
    static let arrowDownSmall = "M3 0.6V5.1M1.1 3.3L3 5.2L4.9 3.3"     // 6 × 6
    static let bolt = "M6.8 1L2.8 6.8h2.7L5 11l4.2-6H6.4z"              // 12 × 12, filled
    static let bluetooth = "M4.5 5.2L11.5 11L8 14V2l3.5 3L4.5 10.8"
    static let chargingBolt = "M4.6 0.5L0.8 6.2h2.7L2.9 10.5l4.3-6.1H4.4z"  // 8 × 11, filled
    static let bell = "M4 11V7a4 4 0 0 1 8 0v4l1.5 1.5h-11L4 11zM6.5 13.5a1.5 1.5 0 0 0 3 0"
    static let plus = "M7 2.5v9M2.5 7h9"                              // 14 × 14
    static let processes = "M5.5 4h8M5.5 8h8M5.5 12h8M2.5 4h.01M2.5 8h.01M2.5 12h.01"
    static let sleep = "M13.5 9.6A5.8 5.8 0 1 1 6.4 2.5a4.6 4.6 0 0 0 7.1 7.1z"
    static let mac = "M3.5 3.5h9a1 1 0 0 1 1 1v6.5h-11V4.5a1 1 0 0 1 1-1zM1 11h14l-.5 1a1 1 0 0 1-.9.5H2.4a1 1 0 0 1-.9-.5z"
    static let linkChevron = "M1 1l4 4-4 4"                           // 6 × 10
    static let sortChevron = "M1.5 3l2.5 2.5L6.5 3"                   // 8 × 8
    static let search = "M5.2 1.5a3.7 3.7 0 1 1 0 7.4a3.7 3.7 0 1 1 0-7.4zM8 8l2.6 2.6"  // 12 × 12
    static let closeSmall = "M2 2l6 6M8 2L2 8"                         // 10 × 10
    static let cup = "M3 6.5h8v3a4 4 0 0 1-8 0zM11 7.5h1a1.5 1.5 0 0 1 0 3h-1.3M5.5 2.5c-.5.6.5 1.2 0 1.8M8 2.5c-.5.6.5 1.2 0 1.8"
    static let infinity = "M8 8c-1.2-1.6-2.4-2.4-3.5-2.4a2.4 2.4 0 1 0 0 4.8c1.1 0 2.3-.8 3.5-2.4zm0 0c1.2 1.6 2.4 2.4 3.5 2.4a2.4 2.4 0 1 0 0-4.8c-1.1 0-2.3.8-3.5 2.4z"
    static let clock = "M8 2.5a5.5 5.5 0 1 1 0 11a5.5 5.5 0 1 1 0-11zM8 5v3l2 1.5"
    static let sunset = "M2 11.5h12M4.5 11.5a3.5 3.5 0 0 1 7 0M8 3.5v2M3.2 6.2l1.2 1.2M12.8 6.2l-1.2 1.2M5 14h6"
    static let plug = "M6 2v3M10 2v3M4.5 5h7v2.5a3.5 3.5 0 0 1-7 0zM8 11v3"
    static let sliders = "M2.5 5h6M11.5 5h2M2.5 11h2M7.5 11h6M10 3.5a1.5 1.5 0 1 1 0 3a1.5 1.5 0 1 1 0-3zM6 9.5a1.5 1.5 0 1 1 0 3a1.5 1.5 0 1 1 0-3z"

    /// A Bluetooth accessory by kind (16 × 16).
    static func device(_ kind: BluetoothDevice.Kind) -> String {
        switch kind {
        case .keyboard: return "M2 4.5h12a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1H2a1 1 0 0 1-1-1v-5a1 1 0 0 1 1-1zM4 7h.01M6.5 7h.01M9 7h.01M11.5 7h.01M5 9.5h6"
        case .trackpad: return "M2.5 3.5h11a1 1 0 0 1 1 1v7a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1v-7a1 1 0 0 1 1-1z"
        case .mouse: return "M8 1.5a4 4 0 0 1 4 4v5a4 4 0 0 1-8 0v-5a4 4 0 0 1 4-4zM8 4v2.5"
        case .earbuds: return "M5.5 2.5a2 2 0 0 1 2 2v1a2 2 0 0 1-2 2v6M10.5 2.5a2 2 0 0 0-2 2v1a2 2 0 0 0 2 2v6"
        case .headphones: return "M2.5 10.5V8a5.5 5.5 0 0 1 11 0v2.5M2.5 10h2.2v4H3.5a1 1 0 0 1-1-1v-3zM13.5 10h-2.2v4h1.2a1 1 0 0 0 1-1v-3z"
        case .gamepad: return "M5 5h6a3.5 3.5 0 0 1 3.4 4.3l-.6 2.5a1.5 1.5 0 0 1-2.6.6L10 11H6l-1.2 1.4a1.5 1.5 0 0 1-2.6-.6l-.6-2.5A3.5 3.5 0 0 1 5 5zM5.5 7v2.5M4.25 8.25h2.5M10.5 7.5h.01M11.75 9h.01"
        case .phone: return "M5 1.5h6a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-11a1 1 0 0 1 1-1zM7 12h2"
        case .tablet: return "M3.5 1.5h9a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1h-9a1 1 0 0 1-1-1v-11a1 1 0 0 1 1-1zM7 12h2"
        case .other: return bluetooth
        }
    }

    static func module(_ m: Module) -> String {
        switch m {
        case .cpu: return cpu
        case .gpu: return gpu
        case .memory: return memory
        case .network: return network
        case .disk: return disk
        case .battery: return battery
        case .bluetooth: return bluetooth
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
/// Without explicit colors it draws in the foreground style (rim at `rimOpacity`).
struct BatteryGlyph: View {
    var level: Double
    var charging = false
    var fill: Color? = nil
    var rim: Color? = nil
    var rimOpacity: Double = 0.45
    var scale: CGFloat = 1

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 25
            let fillShading: GraphicsContext.Shading = fill.map { .color($0) } ?? .foreground
            let rimShading: GraphicsContext.Shading = rim.map { .color($0) } ?? .foreground
            var rimCtx = ctx
            rimCtx.opacity = rimOpacity
            let outer = Path(roundedRect: CGRect(x: 0.75 * s, y: 0.75 * s, width: 21 * s, height: 10.5 * s), cornerRadius: 3 * s)
            rimCtx.stroke(outer, with: rimShading, lineWidth: 1 * s)
            var cap = Path()
            cap.move(to: CGPoint(x: 23.6 * s, y: 4.3 * s))
            cap.addLine(to: CGPoint(x: 23.6 * s, y: 7.7 * s))
            rimCtx.stroke(cap, with: rimShading, style: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round))
            let width = max(1.2, 18 * min(1, max(0, level))) * s
            let inner = Path(roundedRect: CGRect(x: 2.25 * s, y: 2.25 * s, width: width, height: 7.5 * s), cornerRadius: 1.6 * s)
            ctx.fill(inner, with: fillShading)
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

/// Line (and optional soft fill) in the foreground style, for small trend tiles. Values are 0...1.
struct TrendLine: View {
    var values: [Double]
    var lineWidth: CGFloat = 1.2
    var fillOpacity: Double = 0
    var minCount = 30

    var body: some View {
        Canvas { ctx, size in
            guard !values.isEmpty else { return }
            let count = max(values.count, minCount)
            let step = size.width / CGFloat(max(count - 1, 1))
            let offset = CGFloat(count - values.count) * step
            var line = Path()
            for (i, v) in values.enumerated() {
                let p = CGPoint(x: offset + CGFloat(i) * step, y: size.height - CGFloat(min(1, max(0, v))) * (size.height - lineWidth) - lineWidth / 2)
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            if fillOpacity > 0 {
                var area = line
                area.addLine(to: CGPoint(x: offset + CGFloat(values.count - 1) * step, y: size.height))
                area.addLine(to: CGPoint(x: offset, y: size.height))
                area.closeSubpath()
                var fillCtx = ctx
                fillCtx.opacity = fillOpacity
                fillCtx.fill(area, with: .foreground)
            }
            ctx.stroke(line, with: .foreground, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
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
