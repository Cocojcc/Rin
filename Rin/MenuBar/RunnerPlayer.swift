import AppKit
import QuartzCore
import SwiftUI

/// Where each character sits in a status item's picture, noted while the picture is laid out.
/// The item's picture leaves the spot empty; a `RunnerPlayer` plays the character there.
final class RunnerSlots {
    static let space = "rin.statusItem"
    /// Keyed by the module whose reading drives it, or `icon` for the combined item's icon.
    private(set) var rects: [String: CGRect] = [:]

    func record(_ key: String, _ rect: CGRect) {
        if rects[key] != rect { rects[key] = rect }
    }
}

private struct RunnerSlotsKey: EnvironmentKey {
    static let defaultValue: RunnerSlots? = nil
}

extension EnvironmentValues {
    /// Set while a status item is drawn for the menu bar; elsewhere characters draw a still.
    var runnerSlots: RunnerSlots? {
        get { self[RunnerSlotsKey.self] }
        set { self[RunnerSlotsKey.self] = newValue }
    }
}

/// A character's place in a menu bar item: empty room in the bar, where the player draws it;
/// the first frame in windows (settings previews).
struct RunnerSlotView: View {
    var runnerID: String
    var key: String
    /// The bar's height for characters; smaller in pickers.
    var height = RunnerLibrary.height
    var library = RunnerLibrary.shared
    @Environment(\.runnerSlots) private var slots

    var body: some View {
        let runner = library.runner(runnerID)
        // In the bar a character is always the frames' own height.
        let h = slots == nil ? height : RunnerLibrary.height
        let size = CGSize(width: (h * runner.aspect).rounded(), height: h)
        if let slots {
            Color.clear
                .frame(width: size.width, height: size.height)
                .background(GeometryReader { geo in
                    let _ = slots.record(key, geo.frame(in: .named(RunnerSlots.space)))
                    Color.clear
                })
        } else {
            RunnerStill(runner: runner).frame(width: size.width, height: size.height)
        }
    }
}

/// A character's first frame, in the foreground color unless it keeps its own.
struct RunnerStill: View {
    var runner: Runner
    var library = RunnerLibrary.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let frame = library.frames(runner, scale: 2, dark: scheme == .dark).first {
            if runner.colored {
                Image(decorative: frame, scale: 2).resizable().interpolation(.high)
            } else {
                Image(decorative: frame, scale: 2).renderingMode(.template).resizable().interpolation(.high)
            }
        } else {
            Color.clear
        }
    }
}

/// Plays a character in a status item. Its frames swap on the render server, a discrete
/// keyframe animation of a layer's contents, so nothing in Rin runs per frame; only the
/// speed changes, when a reading does. A shape is a mask over a layer filled with the menu
/// bar's text color, so a dark or light bar only changes that one color.
final class RunnerPlayer {
    let layer = CALayer()
    private let frameLayer = CALayer()
    private var frameKey = ""
    private var colored = false
    private var fps: Double = -1
    /// The animation's own pace; `speed` scales it to the reading.
    private static let baseFPS = 10.0

    init() {
        let still: [String: CAAction] = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull(),
                                         "backgroundColor": NSNull(), "hidden": NSNull()]
        layer.actions = still
        frameLayer.actions = still
        frameLayer.contentsGravity = .resize
        layer.speed = 0
        layer.mask = frameLayer
    }

    func show(_ runner: Runner, frames: [CGImage], rect: CGRect, color: CGColor, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = rect
        frameLayer.frame = layer.bounds
        frameLayer.contentsScale = scale
        if runner.colored != colored || frameKey.isEmpty {
            colored = runner.colored
            if colored {
                layer.mask = nil
                layer.addSublayer(frameLayer)
                layer.backgroundColor = nil
            } else {
                frameLayer.removeFromSuperlayer()
                layer.mask = frameLayer
            }
        }
        if !colored { layer.backgroundColor = color }
        let key = "\(runner.id)|\(frames.count)|\(frames.first.map { "\($0.width)x\($0.height)|\(ObjectIdentifier($0))" } ?? "")"
        if key != frameKey, !frames.isEmpty {
            frameKey = key
            frameLayer.removeAnimation(forKey: "frames")
            frameLayer.contents = frames[0]
            let animation = CAKeyframeAnimation(keyPath: "contents")
            animation.values = frames
            animation.calculationMode = .discrete
            animation.duration = Double(frames.count) / Self.baseFPS
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            animation.beginTime = 0
            frameLayer.add(animation, forKey: "frames")
            fps = -1
        }
        CATransaction.commit()
    }

    func setColor(_ color: CGColor) {
        guard !colored else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = color
        CATransaction.commit()
    }

    /// Frames per second; 0 holds the first frame. Small changes are ignored, so a reading
    /// that wobbles doesn't touch the layer.
    func setFPS(_ value: Double) {
        let target = max(0, value)
        if fps >= 0, (target == 0) == (fps == 0), abs(target - fps) < max(0.6, fps * 0.12) { return }
        fps = target
        let speed = Float(target / Self.baseFPS)
        let now = CACurrentMediaTime()
        // The pace is set on the host, which the frames inherit their time from: timing set on
        // a mask layer itself doesn't reliably reach the render server, and a character that
        // had stopped once never moved again. Carry on from the frame on screen at the new
        // pace; a stop goes back to the first.
        let local = speed == 0 ? 0 : layer.convertTime(now, from: nil)
        layer.speed = speed
        layer.timeOffset = local
        layer.beginTime = now
    }
}
