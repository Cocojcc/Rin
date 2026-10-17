// Renders the app icon (accent tile with three bars) into the asset catalog.
// Usage: swift scripts/make-icon.swift Hum/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    // macOS icon grid: 824 pt tile centred in 1024, corner radius ~185.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 24 * s
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(srgbRed: 0xF7 / 255, green: 0x82 / 255, blue: 0x1B / 255, alpha: 1).setFill()
    NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s).fill()
    NSGraphicsContext.restoreGraphicsState()
    // Three bars (the Hum mark), white, round caps. Mark path in a 24 grid: x 7/12/17, heights 3/9/6 ending at y 16.5.
    let unit = 824 * s / 24
    let origin = NSPoint(x: tile.minX, y: tile.minY)
    NSColor.white.setStroke()
    for (x, top) in [(7.0, 13.5), (12.0, 7.5), (17.0, 10.5)] {
        let path = NSBezierPath()
        path.lineWidth = 2.4 * unit
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: origin.x + x * unit, y: origin.y + (24 - 16.5) * unit))
        path.line(to: NSPoint(x: origin.x + x * unit, y: origin.y + (24 - top) * unit))
        path.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try! render(size * scale).write(to: out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}
let json: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("Contents.json"))
print("ok")
