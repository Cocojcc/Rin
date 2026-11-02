import AppKit
import QuartzCore
import SwiftUI

// One small device per module, shaped like what it measures. The overview stands them on a shelf;
// module pages and dropdowns draw the same ones smaller beside their lead reading. Each is drawn in
// the design's own coordinates (150 tall, one stroke), so `scale` is all that differs between them.
//
// A window redraws with every reading, so what hasn't changed is kept out of that: the drawings are
// their own views holding only plain values, rounded to what can be seen, and SwiftUI leaves one
// alone while those stay the same. Levels step from one reading to the next rather than gliding: a
// temperature changes about every second, so a glide would redraw without pause for a pixel or two.

private enum Ink {
    static let stroke: CGFloat = 1.4
}

private extension GraphicsContext {
    /// A rectangle as the design's boards draw them: optional fill, optional stroke.
    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat = 0, fill: Color? = nil, stroke: Color? = nil, width: CGFloat = Ink.stroke) {
        let path = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r, style: .circular)
        if let fill { self.fill(path, with: .color(fill)) }
        if let stroke { self.stroke(path, with: .color(stroke), lineWidth: width) }
    }

    func disc(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, fill: Color? = nil, stroke: Color? = nil, width: CGFloat = Ink.stroke) {
        let path = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        if let fill { self.fill(path, with: .color(fill)) }
        if let stroke { self.stroke(path, with: .color(stroke), lineWidth: width) }
    }

    func line(_ d: String, _ color: Color, width: CGFloat = Ink.stroke) {
        stroke(Path(SVGPath.path(d)), with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}

/// How strong one heat cell is: faint at nothing, the module's full colour at everything.
private func heat(_ v: Double) -> Double { 0.07 + 0.93 * min(max(v, 0), 1) }

/// Sized by the design's box at `scale`, drawn in that box's coordinates.
private struct DeviceCanvas: View {
    var width: CGFloat = 150
    var height: CGFloat = 150
    var scale: CGFloat
    var draw: (GraphicsContext) -> Void

    var body: some View {
        Canvas { ctx, _ in
            var scaled = ctx
            scaled.scaleBy(x: scale, y: scale)
            draw(scaled)
        }
        .frame(width: width * scale, height: height * scale)
        .accessibilityHidden(true)
    }
}

/// A part that keeps moving between readings (a fan, the dots in a pipe, the disk's arm). Core
/// Animation runs it in the window server, so the app does no work until the speed changes; drawing
/// these frame by frame cost ten times the rest of the window. Lives in the design's coordinates at `scale`.
private struct MovingPart: NSViewRepresentable {
    enum Motion {
        /// Degrees a second about `center`.
        case spin(center: CGPoint, speed: Double)
        /// Along y a second, jumping back after `every`, which suits a repeating pattern.
        case slide(by: CGFloat, every: CGFloat, speed: Double)
        /// Swings to an angle about `center`, in about the time between two readings.
        case swing(center: CGPoint, degrees: Double)
    }

    var width: CGFloat = 150
    var height: CGFloat = 150
    var scale: CGFloat
    var path: CGPath
    var color: Color
    /// Strokes the path this wide instead of filling it.
    var line: CGFloat? = nil
    var clip: CGPath? = nil
    var motion: Motion

    func makeNSView(context: Context) -> MovingPartView { MovingPartView() }

    func updateNSView(_ view: MovingPartView, context: Context) {
        view.update(self, reduceMotion: context.environment.accessibilityReduceMotion)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MovingPartView, context: Context) -> CGSize? {
        CGSize(width: width * scale, height: height * scale)
    }
}

private final class MovingPartView: NSView {
    private let shape = CAShapeLayer()
    private let clipper = CAShapeLayer()
    private var speed: Float = -1
    private var configured = false

    override var isFlipped: Bool { true }
    // Clicks go through to the piece it sits on.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(shape)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func update(_ part: MovingPart, reduceMotion: Bool) {
        var ink = CGColor.clear
        effectiveAppearance.performAsCurrentDrawingAppearance { ink = NSColor(part.color).cgColor }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.fillColor = part.line == nil ? ink : nil
        shape.strokeColor = part.line == nil ? nil : ink
        shape.lineWidth = (part.line ?? 0) * part.scale
        shape.lineCap = .round
        if !configured {
            configure(part)
            configured = true
        }
        CATransaction.commit()
        switch part.motion {
        case .spin(_, let degrees): run(key: "transform.rotation.z", by: 2 * .pi, speed: reduceMotion ? 0 : degrees / 360)
        case .slide(let by, let every, let units): run(key: "transform.translation.y", by: by * every * part.scale, speed: reduceMotion ? 0 : units / Double(every))
        case .swing(_, let degrees): swing(to: degrees)
        }
    }

    /// Fixed for the view's life: the shape, where it turns, what clips it.
    private func configure(_ part: MovingPart) {
        var transform = CGAffineTransform(scaleX: part.scale, y: part.scale)
        var center = CGPoint.zero
        switch part.motion {
        case .spin(let c, _), .swing(let c, _): center = c
        case .slide: break
        }
        center = CGPoint(x: center.x * part.scale, y: center.y * part.scale)
        transform = transform.concatenating(CGAffineTransform(translationX: -center.x, y: -center.y))
        // The layer's own origin is where it turns, so the rotation and the shape agree.
        shape.bounds = .zero
        shape.position = center
        shape.path = part.path.copy(using: &transform)
        if let clip = part.clip {
            var scaled = CGAffineTransform(scaleX: part.scale, y: part.scale)
            clipper.path = clip.copy(using: &scaled)
            layer?.mask = clipper
        }
    }

    /// One endless animation; only its layer's clock changes speed, so nothing jumps.
    private func run(key: String, by: CGFloat, speed new: Double) {
        let next = Float(new)
        guard abs(next - speed) > 0.001 else { return }
        if shape.animation(forKey: "move") == nil {
            let move = CABasicAnimation(keyPath: key)
            move.fromValue = 0
            move.toValue = by
            move.duration = 1
            move.repeatCount = .infinity
            shape.add(move, forKey: "move")
        }
        let now = CACurrentMediaTime()
        shape.timeOffset = shape.convertTime(now, from: nil)
        shape.beginTime = now
        shape.speed = next
        speed = next
    }

    private func swing(to degrees: Double) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.85)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        shape.transform = CATransform3DMakeRotation(CGFloat(degrees) * .pi / 180, 0, 0, 1)
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        shape.contentsScale = window?.backingScaleFactor ?? 2
    }
}

// MARK: - CPU

/// A heat map on a chip: one row per core (performance, a small gap, efficiency), one column per reading, newest on the right.
struct ChipInstrument: View {
    var scale: CGFloat = 1
    var monitor = Monitor.shared

    private static let area: CGFloat = 102

    /// One square size for the real core count; the GPU's overview screen borrows it.
    static func pitch(cores: Int, groups: Int) -> CGFloat {
        (area - (groups > 1 ? 4 : 0)) / CGFloat(max(cores, 1))
    }

    var body: some View {
        let _ = monitor.tick
        let cpu = monitor.snapshot.cpu
        let isE = { (i: Int) in i < cpu.coreKinds.count && cpu.coreKinds[i] == .efficiency }
        let order = cpu.perCore.indices.filter { !isE($0) } + cpu.perCore.indices.filter(isE)
        let performance = cpu.perCore.indices.filter { !isE($0) }.count
        let recent = monitor.history.recentCores
        DeviceCanvas(scale: scale) { ctx in
            for p in stride(from: 30, through: 120, by: 15) {
                let x = CGFloat(p)
                ctx.line("M\(x) 1 V10 M\(x) 140 V149 M1 \(x) H10 M140 \(x) H149", Theme.ink)
            }
            ctx.box(10, 10, 130, 130, r: 10, fill: Theme.windowGlass, stroke: Theme.ink)
            let groups = performance > 0 && performance < order.count ? 2 : 1
            let pitch = Self.pitch(cores: order.count, groups: groups)
            let columns = Int(Self.area / pitch)
            let x0 = 24 + (Self.area - CGFloat(columns) * pitch + 1) / 2
            let hue = Theme.color(for: .cpu)
            for (row, core) in order.enumerated() {
                let y = 24 + CGFloat(row) * pitch + (groups > 1 && row >= performance ? 4 : 0)
                for c in 0..<columns {
                    let back = columns - 1 - c
                    let v = back < recent.count && core < recent[recent.count - 1 - back].count ? recent[recent.count - 1 - back][core] : 0
                    ctx.box(x0 + CGFloat(c) * pitch, y, pitch - 1, pitch - 1, r: 1.5, fill: hue.opacity(heat(v)))
                }
            }
        }
    }
}

// MARK: - GPU

/// A screen. macOS only reports the GPU as one figure, so on the overview each cell is one reading
/// of it, read like text with the newest at the bottom right. Elsewhere a curve already shows that,
/// so it is just how busy the GPU is now, lit from the bottom.
struct ScreenInstrument: View {
    var scale: CGFloat = 1
    /// The overview's heat map, in the CPU's square size.
    var history = false
    var monitor = Monitor.shared

    var body: some View {
        let _ = monitor.tick
        let level = monitor.snapshot.gpu.utilization
        ZStack {
            ScreenFrame(scale: scale)
            if history {
                let pitch = max(ChipInstrument.pitch(cores: monitor.snapshot.cpu.perCore.count, groups: SystemInfo.efficiencyCores > 0 ? 2 : 1), 4)
                let count = Int(132 / pitch) * Int(96 / pitch)
                ScreenHeat(scale: scale, pitch: pitch, recent: monitor.history.points(.gpu, range: .m5).suffix(count).map { $0.value / 100 })
            } else {
                ScreenLit(scale: scale, lit: Int((level * Double(ScreenLit.count)).rounded()))
            }
        }
        .frame(width: 150 * scale, height: 150 * scale)
    }
}

private struct ScreenFrame: View {
    var scale: CGFloat

    var body: some View {
        DeviceCanvas(scale: scale) { ctx in
            ctx.box(1, 1, 148, 112, r: 8, fill: Theme.windowGlass, stroke: Theme.ink)
            ctx.box(60, 113, 30, 31, fill: Theme.windowGlass, stroke: Theme.ink)
            ctx.box(38, 144, 74, 6, r: 3, fill: Theme.ink)
        }
    }
}

/// How busy the GPU is now, lit from the bottom.
private struct ScreenLit: View {
    var scale: CGFloat
    var lit: Int

    private static let pitch: CGFloat = 13, cols = 10, rows = 7
    static let count = cols * rows

    var body: some View {
        DeviceCanvas(scale: scale) { ctx in
            let p = Self.pitch
            let x0 = (150 - CGFloat(Self.cols) * p + 1) / 2, y0 = 1 + (112 - CGFloat(Self.rows) * p + 1) / 2
            let hue = Theme.color(for: .gpu)
            for i in 0..<Self.count {
                ctx.box(x0 + CGFloat(i % Self.cols) * p, y0 + CGFloat(Self.rows - 1 - i / Self.cols) * p, p - 1, p - 1, r: 1.5, fill: i < lit ? hue : Theme.cell)
            }
        }
    }
}

/// One cell per reading, read like text with the newest at the bottom right.
private struct ScreenHeat: View {
    var scale: CGFloat
    var pitch: CGFloat
    var recent: [Double]

    var body: some View {
        DeviceCanvas(scale: scale) { ctx in
            let cols = Int(132 / pitch), rows = Int(96 / pitch), count = cols * rows
            let x0 = (150 - CGFloat(cols) * pitch + 1) / 2, y0 = 1 + (112 - CGFloat(rows) * pitch + 1) / 2
            let hue = Theme.color(for: .gpu), blank = count - recent.count
            for i in 0..<count {
                let v = i < blank ? 0 : recent[i - blank]
                ctx.box(x0 + CGFloat(i % cols) * pitch, y0 + CGFloat(i / cols) * pitch, pitch - 1, pitch - 1, r: 1.5, fill: hue.opacity(heat(v)))
            }
        }
    }
}

// MARK: - Memory

/// A memory stick: six chips stacked, filling from the bottom.
struct StickInstrument: View {
    var scale: CGFloat = 1
    var monitor = Monitor.shared

    var body: some View {
        let _ = monitor.tick
        let m = monitor.snapshot.memory
        let color = m.pressure == .critical ? Theme.danger : m.pressure == .warning ? Theme.warn : Theme.color(for: .memory)
        StickDrawing(level: (m.usedFraction * 100).rounded() / 100, color: color, scale: scale)
    }
}

private struct StickDrawing: View {
    var level: Double
    var color: Color
    var scale: CGFloat

    var body: some View {
        DeviceCanvas(width: 90, scale: scale) { ctx in
            ctx.box(7, 0, 76, 138, r: 5, fill: Theme.windowGlass, stroke: Theme.ink)
            ctx.box(3, 92, 8, 10, r: 2, fill: Theme.windowGlass, stroke: Theme.windowGlass, width: 1)
            let h: CGFloat = (110 - 3 * 5) / 6
            for i in 0..<6 {
                let y = 8 + CGFloat(5 - i) * (h + 3)
                ctx.box(18, y, 54, h, r: 2, fill: Theme.cell)
                let part = CGFloat(min(max(level * 6 - Double(i), 0), 1))
                if part > 0 { ctx.box(18, y + h * (1 - part), 54, h * part, r: 2, fill: color) }
            }
            for i in 0..<10 { ctx.box(14 + CGFloat(i) * 6.7, 124, 3, 8, fill: Theme.ink) }
            ctx.box(0, 138, 90, 12, r: 2, fill: Theme.mid)
        }
    }
}

// MARK: - Network

/// Download and upload, two equal pipes: only the speed of the dots differs, and that is the traffic.
struct TubesInstrument: View {
    var scale: CGFloat = 1
    var monitor = Monitor.shared

    /// Units a second for a pipe's dots. Traffic spans six orders of magnitude, so the speed follows its logarithm; below 1 KB/s they stop.
    private func speed(_ bytes: Double) -> Double {
        let kb = bytes / 1000
        return kb < 1 ? 0 : log10(1 + kb) * 12
    }

    fileprivate static func dots(_ cx: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for y in stride(from: -14.0, to: 182, by: 16) { path.addEllipse(in: CGRect(x: cx - 4, y: y - 4 + 16, width: 8, height: 8)) }
        return path
    }

    fileprivate static func pipe(_ x: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: x, y: 22, width: 26, height: 127), cornerWidth: 13, cornerHeight: 13, transform: nil)
    }

    var body: some View {
        let _ = monitor.tick
        let n = monitor.snapshot.network
        ZStack {
            TubesShell(scale: scale)
            if !RenderContext.offscreen {
                MovingPart(width: 78, scale: scale, path: Self.dots(17), color: Theme.color(for: .network), clip: Self.pipe(4),
                           motion: .slide(by: 1, every: 16, speed: speed(n.down)))
                MovingPart(width: 78, scale: scale, path: Self.dots(61), color: Theme.color(for: .network), clip: Self.pipe(48),
                           motion: .slide(by: -1, every: 16, speed: speed(n.up)))
            }
        }
        .frame(width: 78 * scale, height: 150 * scale)
        .accessibilityHidden(true)
    }
}

private struct TubesShell: View {
    var scale: CGFloat

    var body: some View {
        DeviceCanvas(width: 78, scale: scale) { ctx in
            ctx.box(4, 1, 26, 148, r: 13, fill: Theme.windowGlass, stroke: Theme.ink)
            ctx.box(48, 1, 26, 148, r: 13, fill: Theme.windowGlass, stroke: Theme.ink)
            ctx.line("M17 7 V18 M12.5 13.5 L17 18 L21.5 13.5 M61 18 V7 M56.5 11.5 L61 7 L65.5 11.5", Theme.ink)
            // Stand-ins while there is no window server to run them (snapshots).
            if RenderContext.offscreen {
                for (x, cx) in [(CGFloat(4), CGFloat(17)), (48, 61)] {
                    var clipped = ctx
                    clipped.clip(to: Path(TubesInstrument.pipe(x)))
                    clipped.fill(Path(TubesInstrument.dots(cx)), with: .color(Theme.color(for: .network)))
                }
            }
        }
    }
}

// MARK: - Disk

/// How full a volume is, as a platter: the part that can be reclaimed lighter, a red tick where the
/// low-space alert sits, the arm swinging in with the read and write speed.
struct PlatterInstrument: View {
    var scale: CGFloat = 1
    var volume: Volume?
    /// The alert's place on the platter, 0...1 used.
    var tick: Double? = nil
    /// Reads and writes in bytes a second; nil draws no arm (macOS reports them for all disks together).
    var io: Double? = nil

    /// Parked at no activity, right over the platter at a gigabyte a second.
    private var armAngle: Double? { io.map { 50 * (1 - min(1, log10(1 + $0 / 1000) / 6)) } }

    var body: some View {
        let total = Double(max(volume?.total ?? 1, 1))
        // To a tenth of a percent, about what a pixel of the ring comes to.
        let used = (Double(volume?.used ?? 0) / total * 1000).rounded() / 1000
        let purge = (Double(volume?.purgeable ?? 0) / total * 1000).rounded() / 1000
        PlatterFace(scale: scale, used: used, purge: purge, tick: tick)
            .overlay(alignment: .topLeading) {
                if let armAngle {
                    if RenderContext.offscreen {
                        DeviceCanvas(scale: scale) { ctx in
                            var turned = ctx
                            turned.translateBy(x: 141, y: 141)
                            turned.rotate(by: .degrees(armAngle))
                            turned.translateBy(x: -141, y: -141)
                            turned.stroke(Path(Self.armPath), with: .color(Theme.mid), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        }
                    } else {
                        MovingPart(scale: scale, path: Self.armPath, color: Theme.mid, line: 3, motion: .swing(center: CGPoint(x: 141, y: 141), degrees: armAngle))
                    }
                    ArmPivot(scale: scale)
                }
            }
    }

    private static let armPath: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 141, y: 141))
        p.addLine(to: CGPoint(x: 104, y: 103))
        return p
    }()
}

private struct PlatterFace: View {
    var scale: CGFloat
    var used: Double
    var purge: Double
    var tick: Double?

    var body: some View {
        DeviceCanvas(scale: scale) { ctx in
            ctx.disc(75, 75, 72, fill: Theme.windowGlass, stroke: Theme.ink)
            ctx.disc(75, 75, 55, stroke: Theme.cell, width: 24)
            let hue = Theme.color(for: .disk)
            arc(ctx, from: 0, to: max(0, used - purge), hue)
            if purge > 0 { arc(ctx, from: max(0, used - purge), to: used, hue.opacity(0.45)) }
            if let tick {
                let a = (tick * 360 - 90) * .pi / 180
                ctx.line("M\(75 + 41 * cos(a)) \(75 + 41 * sin(a)) L\(75 + 69 * cos(a)) \(75 + 69 * sin(a))", Theme.danger, width: 3)
            }
            ctx.disc(75, 75, 9, fill: Theme.windowGlass, stroke: Theme.ink)
        }
    }

    private func arc(_ ctx: GraphicsContext, from: Double, to: Double, _ color: Color) {
        var p = Path()
        p.addArc(center: CGPoint(x: 75, y: 75), radius: 55, startAngle: .degrees(from * 360 - 90), endAngle: .degrees(to * 360 - 90), clockwise: false)
        ctx.stroke(p, with: .color(color), lineWidth: 24)
    }
}

private struct ArmPivot: View {
    var scale: CGFloat

    var body: some View {
        DeviceCanvas(scale: scale) { ctx in ctx.disc(141, 141, 5, fill: Theme.mid) }
    }
}

// MARK: - Battery

/// A battery: green while charging, red when low, with a bolt while charging and a plug on the adapter.
struct CellInstrument: View {
    var scale: CGFloat = 1
    var monitor = Monitor.shared

    var body: some View {
        let b = monitor.snapshot.battery
        let color = b.isCharging ? Theme.green : b.level <= 0.2 ? Theme.danger : Theme.faint
        CellDrawing(level: (b.level * 100).rounded() / 100, color: color, bolt: b.isCharging, plug: !b.isCharging && b.onAC, scale: scale)
    }
}

private struct CellDrawing: View {
    var level: Double
    var color: Color
    var bolt: Bool
    var plug: Bool
    var scale: CGFloat

    var body: some View {
        DeviceCanvas(width: 90, scale: scale) { ctx in
            ctx.box(27, 0, 36, 10, r: 3, fill: Theme.ink)
            ctx.box(1, 8, 88, 141, r: 14, fill: Theme.windowGlass, stroke: Theme.ink)
            let h = 127 * CGFloat(min(max(level, 0), 1))
            ctx.box(8, 15 + 127 - h, 74, h, r: 9, fill: color)
            var mark = ctx
            mark.translateBy(x: 45, y: 78.5)
            mark.scaleBy(x: 0.8, y: 0.8)
            mark.translateBy(x: -50, y: -108)
            if bolt { mark.fill(Path(SVGPath.path("M54 70 L36 112 H49 L44 146 L66 98 H52 Z")), with: .color(Theme.windowGlass)) }
            if plug { mark.line("M41 80 V94 M59 80 V94 M33 94 H67 V104 A17 17 0 0 1 33 104 Z M50 121 V136", Theme.windowGlass, width: 5) }
        }
    }
}

// MARK: - Accessories

/// One equal battery per device, its glyph above it, centred.
struct PackInstrument: View {
    var scale: CGFloat = 1
    var settings = SettingsStore.shared
    var monitor = Monitor.shared

    private static let most = 8

    var body: some View {
        let _ = monitor.tick
        let prefs = settings.prefs
        PackDrawing(scale: scale, devices: monitor.snapshot.bluetooth.withBattery.prefix(Self.most).map {
            PackDrawing.Device(kind: $0.kind, level: (($0.level ?? 0) * 100).rounded() / 100, low: BluetoothText.isLow($0, prefs))
        })
        .equatable()
    }
}

private struct PackDrawing: View, Equatable {
    struct Device: Equatable {
        var kind: BluetoothDevice.Kind
        var level: Double
        var low: Bool
    }

    var scale: CGFloat
    var devices: [Device]

    var body: some View {
        DeviceCanvas(scale: scale) { ctx in
            let n = devices.count
            // Four fit at the design's width; more narrow to stay on the shelf.
            let gap: CGFloat = n > 4 ? 5 : 9
            let w = min(28, (150 - CGFloat(max(n - 1, 0)) * gap) / CGFloat(max(n, 1)))
            let x0 = (150 - CGFloat(n) * w - CGFloat(max(n - 1, 0)) * gap) / 2
            for (i, d) in devices.enumerated() {
                let x = x0 + CGFloat(i) * (w + gap)
                let level = CGFloat(min(max(d.level, 0), 1))
                var mark = ctx
                mark.translateBy(x: x + w / 2 - 8, y: 0)
                mark.line(Icons.device(d.kind), d.low ? Theme.danger : Theme.sub)
                ctx.box(x + w / 2 - 6, 16, 12, 6, r: 2, fill: Theme.ink)
                ctx.box(x, 21, w, 129, r: 6, fill: Theme.windowGlass, stroke: d.low ? Theme.danger : Theme.ink)
                let h = max(4, 121 * level)
                ctx.box(x + 4, 25 + 121 - h, w - 8, h, r: 3, fill: d.low ? Theme.danger : Theme.mid)
            }
        }
    }
}

// MARK: - Sensors

/// A thermometer marked at 70 and 90 °C, and the fan beside it turning faster as it speeds up.
struct SensorInstrument: View {
    var scale: CGFloat = 1
    var monitor = Monitor.shared

    private static let fanCenter = CGPoint(x: 107, y: 113)
    private static let radius: CGFloat = 36

    /// Degrees a second on screen: real rotation is far too fast to see, so a fan's range maps to a visible one; a stopped fan stands still.
    private func spin(_ fan: Fan?) -> Double {
        guard let fan, fan.rpm > 0 else { return 0 }
        return 90 + 630 * min(max((fan.rpm - fan.min) / max(fan.max - fan.min, 1), 0), 1)
    }

    /// Seven blades about the fan's centre.
    private static let blades: CGPath = {
        let r = radius, path = CGMutablePath()
        for i in 0..<7 {
            let turn = CGAffineTransform(translationX: fanCenter.x, y: fanCenter.y).rotated(by: CGFloat(i) * 2 * .pi / 7)
            path.move(to: CGPoint(x: 0, y: -r * 0.2), transform: turn)
            path.addCurve(to: CGPoint(x: 0, y: -r * 0.86), control1: CGPoint(x: r * 0.36, y: -r * 0.42), control2: CGPoint(x: r * 0.3, y: -r * 0.82), transform: turn)
            path.addCurve(to: CGPoint(x: 0, y: -r * 0.2), control1: CGPoint(x: -r * 0.12, y: -r * 0.68), control2: CGPoint(x: -r * 0.1, y: -r * 0.4), transform: turn)
            path.closeSubpath()
        }
        return path
    }()

    var body: some View {
        let _ = monitor.tick
        let s = monitor.snapshot.sensors
        let t = s.cpuAverage ?? 20
        let color = t >= 90 ? Theme.danger : t >= 70 ? Theme.warn : Theme.color(for: .sensors)
        let hue = Theme.color(for: .sensors)
        ZStack {
            ThermometerDrawing(temperature: t.rounded(), color: color, scale: scale)
            if !s.fans.isEmpty {
                FanDisc(scale: scale, center: Self.fanCenter, radius: Self.radius, standIn: Self.blades)
                if !RenderContext.offscreen {
                    MovingPart(scale: scale, path: Self.blades, color: hue, motion: .spin(center: Self.fanCenter, speed: spin(s.fans.first)))
                }
                FanHub(scale: scale, center: Self.fanCenter, radius: Self.radius * 0.17)
            }
        }
        .frame(width: 150 * scale, height: 150 * scale)
        .accessibilityHidden(true)
    }
}

private struct FanDisc: View {
    var scale: CGFloat
    var center: CGPoint
    var radius: CGFloat
    var standIn: CGPath

    var body: some View {
        DeviceCanvas(scale: scale) { ctx in
            ctx.disc(center.x, center.y, radius, fill: Theme.windowGlass, stroke: Theme.ink)
            // Blades while there is no window server to turn them (snapshots).
            if RenderContext.offscreen { ctx.fill(Path(standIn), with: .color(Theme.color(for: .sensors))) }
        }
    }
}

private struct FanHub: View {
    var scale: CGFloat
    var center: CGPoint
    var radius: CGFloat

    var body: some View {
        DeviceCanvas(scale: scale) { ctx in ctx.disc(center.x, center.y, radius, fill: Theme.windowGlass, stroke: Theme.color(for: .sensors)) }
    }
}

private struct ThermometerDrawing: View {
    var temperature: Double
    var color: Color
    var scale: CGFloat

    private static let top: CGFloat = 10, range: CGFloat = 96

    /// Where a temperature sits on the tube, which runs from 100 °C at the top down to 20 °C.
    private func y(_ t: Double) -> CGFloat { Self.top + Self.range * CGFloat(1 - (t - 20) / 80) }

    var body: some View {
        DeviceCanvas(scale: scale) { ctx in
            ctx.box(22, 2, 26, 112, r: 13, fill: Theme.windowGlass, stroke: Theme.ink)
            ctx.disc(35, 124, 25, fill: Theme.windowGlass, stroke: Theme.ink)
            let t = min(max(temperature, 20), 100)
            ctx.box(29, y(t), 12, Self.range * CGFloat((t - 20) / 80) + 14, r: 6, fill: color)
            ctx.disc(35, 124, 19, fill: color)
            ctx.line("M54 \(y(70)) H63", Theme.warn, width: 1.8)
            ctx.line("M54 \(y(90)) H63", Theme.danger, width: 1.8)
        }
    }
}

// MARK: - Stand

/// A reading beside its instrument, both standing on one rule, as on the overview.
struct Stand<Reading: View, Device: View>: View {
    var top: CGFloat = 6
    var gap: CGFloat = 28
    @ViewBuilder var reading: Reading
    @ViewBuilder var device: Device

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: gap) {
                reading.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 10)
                device
            }
            Rectangle().fill(Theme.low).frame(height: 1)
        }
        .padding(.top, top)
    }
}
