import AppKit
import CoreGraphics
import ImageIO
import Observation
import UniformTypeIdentifiers

/// An animated character for the menu bar ("动画"), RunCat style. Its frames are prepared once,
/// when it is imported: shapes the bar fills with its own text color, or pictures kept in their
/// colors.
struct Runner: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var frameCount: Int
    /// Frame width over height.
    var aspect: Double
    /// Pictures kept in their colors rather than shapes in the bar's text color.
    var colored = false
    /// A second set for dark menu bars, kept only when it differs from the light one.
    var hasDarkSet = false
    var added = Date()

    var isBuiltIn: Bool { id.hasPrefix(RunnerLibrary.builtInPrefix) }
}

/// The built-in characters and the imported ones. Imported frames are kept in Application
/// Support/Rin/Runners, ready-made: 1x and 2x, a light set and, when it differs, a dark one.
/// The equalizer is drawn in code; her and the cat ship in the app as the same kind of frames.
@Observable
final class RunnerLibrary {
    static let shared = RunnerLibrary()
    static let builtInPrefix = "builtin."
    static let defaultID = "builtin.equalizer"
    /// Points a frame is tall in the menu bar.
    static let height: CGFloat = 18
    static let maxFrames = 60

    private(set) var imported: [Runner] = []
    var all: [Runner] { Self.builtIns + imported }

    @ObservationIgnored private var cache: [String: [CGImage]] = [:]

    static let equalizer = Runner(id: defaultID, name: "", frameCount: 8, aspect: 14.0 / 18.0)
    /// Frames in the app bundle as `runner-<name>-<1x|2x>-<i>.png`.
    /// One loop cut from a short image-to-video clip each, so every frame follows from the last.
    static let girl = Runner(id: builtInPrefix + "girl", name: "", frameCount: 21, aspect: 333.0 / 424.0)
    static let cat = Runner(id: builtInPrefix + "cat", name: "", frameCount: 23, aspect: 491.0 / 370.0)
    static let builtIns = [equalizer, girl, cat]

    private init() {
        imported = Self.loadIndex()
    }

    func runner(_ id: String) -> Runner { all.first { $0.id == id } ?? Self.equalizer }

    func name(_ r: Runner) -> String {
        switch r.id {
        case Self.defaultID: return L10n.Runner.equalizer
        case Self.girl.id: return L10n.Runner.girl
        case Self.cat.id: return L10n.Runner.cat
        default: return r.name
        }
    }

    /// The frames at a pixel scale (1 or 2) for a light or a dark menu bar.
    func frames(_ r: Runner, scale: Int, dark: Bool) -> [CGImage] {
        let set = r.hasDarkSet && dark ? "dark" : "light"
        let key = "\(r.id)|\(scale)|\(set)"
        if let cached = cache[key] { return cached }
        let frames = r.id == Self.defaultID ? Self.equalizerFrames(scale: scale)
            : r.isBuiltIn ? Self.bundled(r, scale: scale)
            : Self.load(r, scale: scale, set: set)
        cache[key] = frames
        return frames
    }

    // MARK: Import

    enum ImportError: Error {
        case noImages, unreadable, tooManyFrames(Int)

        var message: String {
            switch self {
            case .noImages: return L10n.Runner.noImages
            case .unreadable: return L10n.Runner.unreadable
            case .tooManyFrames(let n): return L10n.Runner.tooManyFrames(n)
            }
        }
    }

    /// Reads a folder of numbered PNGs (a light_ / dark_ pair of sets is fine), an animated GIF,
    /// or one PNG strip of square frames, prepares every frame and saves the result.
    @discardableResult
    func importRunner(from url: URL) throws -> Runner {
        let source = try RunnerSource.read(url)
        guard source.light.count <= Self.maxFrames else { throw ImportError.tooManyFrames(source.light.count) }
        let prepared = try RunnerPrep.prepare(light: source.light, dark: source.dark)
        let id = UUID().uuidString
        let dir = Self.folder.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (set, frames) in [("light", prepared.light), ("dark", prepared.dark ?? [])] {
            for (i, frame) in frames.enumerated() {
                for scale in [1, 2] {
                    let image = RunnerPrep.scaled(frame, height: Int(Self.height) * scale)
                    try Self.writePNG(image, to: dir.appendingPathComponent("\(set)@\(scale)x-\(i).png"))
                }
            }
        }
        let runner = Runner(id: id, name: source.name, frameCount: prepared.light.count, aspect: prepared.aspect,
                            colored: prepared.colored, hasDarkSet: prepared.dark != nil)
        try JSONEncoder().encode(runner).write(to: dir.appendingPathComponent("runner.json"), options: .atomic)
        imported.append(runner)
        return runner
    }

    func delete(_ id: String) {
        guard !id.hasPrefix(Self.builtInPrefix) else { return }
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(id, isDirectory: true))
        imported.removeAll { $0.id == id }
        cache = cache.filter { !$0.key.hasPrefix(id + "|") }
    }

    // MARK: Storage

    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rin/Runners", isDirectory: true)
    }

    private static func loadIndex() -> [Runner] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("runner.json")) else { return nil }
            return try? JSONDecoder().decode(Runner.self, from: data)
        }
        .sorted { $0.added < $1.added }
    }

    private static func load(_ r: Runner, scale: Int, set: String) -> [CGImage] {
        let dir = folder.appendingPathComponent(r.id, isDirectory: true)
        return (0..<r.frameCount).compactMap { i in
            let url = dir.appendingPathComponent("\(set)@\(scale)x-\(i).png")
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
    }

    private static func bundled(_ r: Runner, scale: Int) -> [CGImage] {
        let name = r.id.dropFirst(builtInPrefix.count)
        return (0..<r.frameCount).compactMap { i in
            guard let url = Bundle.main.url(forResource: "runner-\(name)-\(scale)x-\(i)", withExtension: "png"),
                  let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ImportError.unreadable
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw ImportError.unreadable }
    }

    // MARK: Built-in

    /// Rin's three bars bouncing like an equalizer, each a little behind the one before.
    private static func equalizerFrames(scale: Int) -> [CGImage] {
        let s = CGFloat(scale)
        let w = Int((height * equalizer.aspect * s).rounded()), h = Int(height * s)
        let bar = 2.4 * s, gap = 2.6 * s
        let left = (CGFloat(w) - bar * 3 - gap * 2) / 2
        return (0..<equalizer.frameCount).compactMap { f in
            guard let ctx = RunnerPrep.context(w, h) else { return nil }
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            for b in 0..<3 {
                let phase = (Double(f) / Double(equalizer.frameCount) + Double(b) * 0.28) * 2 * .pi
                let level = 0.25 + 0.75 * (0.5 + 0.5 * sin(phase))
                let barHeight = (3 * s + (CGFloat(h) - 7 * s) * level).rounded()
                let rect = CGRect(x: left + CGFloat(b) * (bar + gap), y: 2 * s, width: bar, height: barHeight)
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: bar / 2, cornerHeight: bar / 2, transform: nil))
                ctx.fillPath()
            }
            return ctx.makeImage()
        }
    }
}

// MARK: - Reading

/// The frames found at an imported URL, in playing order.
private struct RunnerSource {
    var name: String
    var light: [CGImage]
    var dark: [CGImage]?

    static func read(_ url: URL) throws -> RunnerSource {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { throw RunnerLibrary.ImportError.unreadable }
        if isDir.boolValue { return try folder(url) }
        return try file(url, name: url.deletingPathExtension().lastPathComponent)
    }

    /// A GIF's frames, a strip's frames, or a single picture.
    private static func file(_ url: URL, name: String) throws -> RunnerSource {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw RunnerLibrary.ImportError.unreadable }
        let count = CGImageSourceGetCount(src)
        let images = (0..<count).compactMap { CGImageSourceCreateImageAtIndex(src, $0, nil) }
        guard let first = images.first else { throw RunnerLibrary.ImportError.noImages }
        if images.count > 1 { return RunnerSource(name: name, light: images) }
        // A strip of square frames side by side.
        if first.width >= first.height * 2, first.width % first.height == 0 {
            let n = first.width / first.height
            let frames = (0..<n).compactMap { first.cropping(to: CGRect(x: $0 * first.height, y: 0, width: first.height, height: first.height)) }
            return RunnerSource(name: name, light: frames)
        }
        return RunnerSource(name: name, light: [first])
    }

    /// Numbered pictures, ordered by their number ("ikun_10" after "ikun_9"). Files share a
    /// prefix per set; with a light and a dark set the light one leads and the dark one is
    /// compared with it later.
    private static func folder(_ url: URL) throws -> RunnerSource {
        let files = ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["png", "gif", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
        let gifs = files.filter { $0.pathExtension.lowercased() == "gif" }
        if files.count == 1 || (gifs.count == 1 && files.count == gifs.count) {
            guard let only = gifs.first ?? files.first else { throw RunnerLibrary.ImportError.noImages }
            return try file(only, name: displayName(url))
        }
        guard !files.isEmpty else { throw RunnerLibrary.ImportError.noImages }
        var groups: [String: [(Int, URL)]] = [:]
        for f in files {
            let stem = f.deletingPathExtension().lastPathComponent
            let digits = String(stem.reversed().prefix { $0.isNumber }.reversed())
            let prefix = String(stem.dropLast(digits.count))
            groups[prefix, default: []].append((Int(digits) ?? 0, f))
        }
        func images(_ list: [(Int, URL)]) -> [CGImage] {
            list.sorted { $0.0 < $1.0 }.compactMap { _, f in
                CGImageSourceCreateWithURL(f as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
            }
        }
        let lightKey = groups.keys.first { $0.lowercased().contains("light") }
        let darkKey = groups.keys.first { $0.lowercased().contains("dark") }
        let mainKey = lightKey ?? groups.max { $0.value.count < $1.value.count }!.key
        let light = images(groups[mainKey] ?? [])
        guard !light.isEmpty else { throw RunnerLibrary.ImportError.noImages }
        let dark = darkKey.map { images(groups[$0] ?? []) }.flatMap { $0.count == light.count ? $0 : nil }
        // "light_ikun_" names the character "ikun".
        let stripped = mainKey.replacingOccurrences(of: "light", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_- .").union(.whitespaces))
        return RunnerSource(name: stripped.isEmpty ? displayName(url) : stripped, light: light, dark: dark)
    }

    /// The folder's name, or its parent's when it is a generic one like "PNG".
    private static func displayName(_ url: URL) -> String {
        let name = url.lastPathComponent
        let generic = ["png", "gif", "frames", "images", "img", "sprites"]
        return generic.contains(name.lowercased()) ? url.deletingLastPathComponent().lastPathComponent : name
    }
}

// MARK: - Preparing

enum RunnerPrep {
    struct Prepared {
        var light: [CGImage]
        var dark: [CGImage]?
        var aspect: Double
        var colored: Bool
    }

    /// One frame's pixels, straight (not premultiplied) RGBA in 0...1.
    private struct Pixels {
        var w: Int, h: Int
        var rgba: [Float]

        func alpha(_ x: Int, _ y: Int) -> Float { rgba[(y * w + x) * 4 + 3] }
    }

    static func context(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    static func prepare(light: [CGImage], dark: [CGImage]?) throws -> Prepared {
        guard let first = light.first else { throw RunnerLibrary.ImportError.noImages }
        let w = first.width, h = first.height
        var lightPx = light.map { pixels($0, w, h) }
        var darkPx = dark?.map { pixels($0, w, h) }
        // Opaque pictures lose the background they were drawn on (the corners' color).
        if lightPx.allSatisfy({ $0.rgba.enumerated().allSatisfy { $0.offset % 4 != 3 || $0.element > 0.99 } }) {
            lightPx = lightPx.map(removeBackground)
            darkPx = darkPx?.map(removeBackground)
        }
        let colored = saturation(lightPx) > 0.2
        // One crop for every frame, so the character keeps its place as it moves.
        var minX = w, minY = h, maxX = -1, maxY = -1
        for p in lightPx + (darkPx ?? []) {
            for y in 0..<h { for x in 0..<w where p.alpha(x, y) > 0.03 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            } }
        }
        guard maxX >= minX, maxY >= minY else { throw RunnerLibrary.ImportError.noImages }
        // Empty rows go only when there is real room to gain: frames drawn for the bar (36 px)
        // stay their height and scale 1:1, rather than by an odd fraction that blurs them.
        if Double(maxY - minY + 1) > Double(h) * 0.8 { minY = 0; maxY = h - 1 }
        let crop = (x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1)
        func render(_ p: Pixels, shape: Bool, darkFigure: Bool) -> CGImage? {
            image(p, crop: crop, shape: shape, darkFigure: darkFigure)
        }
        let lightDark = meanLuminance(lightPx) < 0.5
        var lightOut = lightPx.compactMap { render($0, shape: !colored, darkFigure: lightDark) }
        var darkOut = darkPx.map { set in set.compactMap { render($0, shape: !colored, darkFigure: meanLuminance(set) < 0.5) } }
        if !colored, let d = darkOut, shapesMatch(lightOut, d) { darkOut = nil }
        lightOut = normalized(lightOut)
        darkOut = darkOut.map(normalized)
        return Prepared(light: lightOut, dark: darkOut, aspect: Double(crop.w) / Double(crop.h), colored: colored)
    }

    /// Scaled to `height` pixels, keeping the aspect.
    static func scaled(_ image: CGImage, height: Int) -> CGImage {
        let width = max(1, Int((Double(image.width) * Double(height) / Double(image.height)).rounded()))
        guard let ctx = context(width, height) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? image
    }

    private static func pixels(_ image: CGImage, _ w: Int, _ h: Int) -> Pixels {
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        buffer.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var rgba = [Float](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let a = Float(buffer[i * 4 + 3]) / 255
            for c in 0..<3 { rgba[i * 4 + c] = a > 0 ? min(1, Float(buffer[i * 4 + c]) / 255 / a) : 0 }
            rgba[i * 4 + 3] = a
        }
        return Pixels(w: w, h: h, rgba: rgba)
    }

    private static func removeBackground(_ p: Pixels) -> Pixels {
        let corners = [(0, 0), (p.w - 1, 0), (0, p.h - 1), (p.w - 1, p.h - 1)]
        var bg: [Float] = [0, 0, 0]
        for (x, y) in corners { for c in 0..<3 { bg[c] += p.rgba[(y * p.w + x) * 4 + c] / 4 } }
        var out = p
        for i in 0..<(p.w * p.h) {
            var d: Float = 0
            for c in 0..<3 { let v = p.rgba[i * 4 + c] - bg[c]; d += v * v }
            out.rgba[i * 4 + 3] = min(1, d.squareRoot() / 0.35)
        }
        return out
    }

    private static func saturation(_ frames: [Pixels]) -> Float {
        var sum: Float = 0, n: Float = 0
        for p in frames {
            for i in 0..<(p.w * p.h) where p.rgba[i * 4 + 3] > 0.5 {
                let r = p.rgba[i * 4], g = p.rgba[i * 4 + 1], b = p.rgba[i * 4 + 2]
                let hi = max(r, g, b), lo = min(r, g, b)
                sum += hi > 0 ? (hi - lo) / hi : 0
                n += 1
            }
        }
        return n > 0 ? sum / n : 0
    }

    private static func meanLuminance(_ frames: [Pixels]) -> Float {
        var sum: Float = 0, n: Float = 0
        for p in frames {
            for i in 0..<(p.w * p.h) where p.rgba[i * 4 + 3] > 0.5 {
                sum += 0.2126 * p.rgba[i * 4] + 0.7152 * p.rgba[i * 4 + 1] + 0.0722 * p.rgba[i * 4 + 2]
                n += 1
            }
        }
        return n > 0 ? sum / n : 0
    }

    /// The cropped frame: a shape (black with coverage as alpha) or the picture itself. A
    /// shape's coverage follows brightness as well as alpha, so lighter strokes inside a dark
    /// figure (or darker ones inside a light figure) stay visible as gaps.
    private static func image(_ p: Pixels, crop: (x: Int, y: Int, w: Int, h: Int), shape: Bool, darkFigure: Bool) -> CGImage? {
        guard let ctx = context(crop.w, crop.h), let data = ctx.data else { return nil }
        let out = data.bindMemory(to: UInt8.self, capacity: crop.w * crop.h * 4)
        let row = ctx.bytesPerRow
        for y in 0..<crop.h {
            for x in 0..<crop.w {
                // Both buffers keep the picture's top row first.
                let i = ((y + crop.y) * p.w + (x + crop.x)) * 4
                let o = y * row + x * 4
                let a = p.rgba[i + 3]
                if shape {
                    let lum = 0.2126 * p.rgba[i] + 0.7152 * p.rgba[i + 1] + 0.0722 * p.rgba[i + 2]
                    let coverage = a * (darkFigure ? 1 - lum : lum)
                    out[o] = 0; out[o + 1] = 0; out[o + 2] = 0
                    out[o + 3] = UInt8(max(0, min(255, coverage * 255)))
                } else {
                    for c in 0..<3 { out[o + c] = UInt8(max(0, min(255, p.rgba[i + c] * a * 255))) }
                    out[o + 3] = UInt8(max(0, min(255, a * 255)))
                }
            }
        }
        return ctx.makeImage()
    }

    /// Shapes stretched so the most solid part of the character is fully opaque.
    private static func normalized(_ frames: [CGImage]) -> [CGImage] {
        var peak: UInt8 = 1
        for f in frames {
            guard let data = f.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { continue }
            for i in stride(from: 3, to: CFDataGetLength(data), by: 4) { peak = max(peak, bytes[i]) }
        }
        guard peak < 250 else { return frames }
        let gain = 255 / Float(peak)
        return frames.map { f in
            guard let ctx = context(f.width, f.height), let out = ctx.data?.bindMemory(to: UInt8.self, capacity: f.width * f.height * 4),
                  let data = f.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return f }
            let count = min(CFDataGetLength(data), ctx.bytesPerRow * f.height)
            for i in stride(from: 0, to: count, by: 4) {
                for c in 0..<3 { out[i + c] = UInt8(min(255, Float(bytes[i + c]) * gain)) }
                out[i + 3] = UInt8(min(255, Float(bytes[i + 3]) * gain))
            }
            return ctx.makeImage() ?? f
        }
    }

    /// The same shapes, within a few percent: two sets that only differ in color.
    private static func shapesMatch(_ a: [CGImage], _ b: [CGImage]) -> Bool {
        guard a.count == b.count else { return false }
        var diff = 0.0, total = 0.0
        for (x, y) in zip(a, b) {
            guard let dx = x.dataProvider?.data, let dy = y.dataProvider?.data,
                  let px = CFDataGetBytePtr(dx), let py = CFDataGetBytePtr(dy) else { return false }
            let n = min(CFDataGetLength(dx), CFDataGetLength(dy))
            for i in stride(from: 3, to: n, by: 4) {
                diff += abs(Double(px[i]) - Double(py[i]))
                total += 255
            }
        }
        return total > 0 && diff / total < 0.04
    }
}

// MARK: - Pace

/// How fast a module's character moves, in frames per second; 0 holds the first frame. The
/// fastest is the pace the built-in runs were filmed at; below about 8 a run turns into a
/// slide show.
enum RunnerPace {
    static let slowest = 8.0
    static let fastest = 24.0

    static func fps(_ m: Module, _ s: Snapshot) -> Double {
        switch m {
        case .cpu:
            return slowest + (fastest - slowest) * min(1, max(0, s.cpu.total))
        case .memory:
            // Pressure, not usage: macOS keeps most memory busy as cache.
            switch s.memory.pressure {
            case .normal: return slowest
            case .warning: return 15
            case .critical: return fastest
            }
        case .network:
            // By order of magnitude, against fixed steps: still below 2 KB/s, slow at
            // 10 KB/s, fastest from 10 MB/s.
            let total = s.network.down + s.network.up
            guard s.network.connected, total >= 2_000 else { return 0 }
            let t = (log10(total) - 4) / 3
            return slowest + (fastest - slowest) * min(1, max(0, t))
        default:
            return slowest
        }
    }
}
