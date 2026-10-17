import CoreGraphics
import Foundation
import SwiftUI

/// Tiny SVG path-data parser (M L H V A Z, absolute and relative) so the line icons can be
/// taken verbatim from the design canvas.
enum SVGPath {
    private static var cache: [String: CGPath] = [:]
    private static let lock = NSLock()

    static func path(_ d: String) -> CGPath {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[d] { return cached }
        let p = parse(d)
        cache[d] = p
        return p
    }

    private static func tokenize(_ d: String) -> [Any] {
        var tokens: [Any] = []
        var number = ""
        var sawDot = false
        var sawExp = false
        func flush() {
            if !number.isEmpty, let v = Double(number) { tokens.append(CGFloat(v)) }
            number = ""; sawDot = false; sawExp = false
        }
        for ch in d {
            if ch.isLetter && ch != "e" && ch != "E" {
                flush(); tokens.append(ch)
            } else if ch == "-" || ch == "+" {
                if let last = number.last, last == "e" || last == "E" { number.append(ch) }
                else { flush(); number.append(ch) }
            } else if ch == "." {
                if sawDot && !sawExp { flush() }
                sawDot = true; number.append(ch)
            } else if ch == "e" || ch == "E" {
                sawExp = true; number.append(ch)
            } else if ch.isNumber {
                number.append(ch)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }

    private static func parse(_ d: String) -> CGPath {
        let path = CGMutablePath()
        let tokens = tokenize(d)
        var i = 0
        var cmd: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero

        func next() -> CGFloat? {
            guard i < tokens.count, let v = tokens[i] as? CGFloat else { return nil }
            i += 1
            return v
        }
        func nextFlag() -> Bool? {
            // Flags may be packed ("011"), but the tokenizer reads them as one number; handle both.
            guard let v = next() else { return nil }
            return v != 0
        }

        while i < tokens.count {
            if let c = tokens[i] as? Character { cmd = c; i += 1 }
            let rel = cmd.isLowercase
            let base = rel ? current : .zero
            switch cmd.uppercased().first! {
            case "M":
                guard let x = next(), let y = next() else { i += 1; continue }
                current = CGPoint(x: base.x + x, y: base.y + y)
                start = current
                path.move(to: current)
                cmd = rel ? "l" : "L"
            case "L":
                guard let x = next(), let y = next() else { i += 1; continue }
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addLine(to: current)
            case "H":
                guard let x = next() else { i += 1; continue }
                current.x = (rel ? current.x : 0) + x
                path.addLine(to: current)
            case "V":
                guard let y = next() else { i += 1; continue }
                current.y = (rel ? current.y : 0) + y
                path.addLine(to: current)
            case "A":
                guard let rx = next(), let ry = next(), let rot = next(),
                      let large = nextFlag(), let sweep = nextFlag(),
                      let x = next(), let y = next() else { i += 1; continue }
                let end = CGPoint(x: base.x + x, y: base.y + y)
                addArc(path, from: current, to: end, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
                current = end
            case "Z":
                path.closeSubpath()
                current = start
            default:
                i += 1
            }
        }
        return path
    }

    /// Endpoint-to-center arc conversion (SVG spec, appendix F.6), drawn as cubic segments.
    private static func addArc(_ path: CGMutablePath, from p1: CGPoint, to p2: CGPoint,
                               rx rxIn: CGFloat, ry ryIn: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        guard rx > 0, ry > 0, p1 != p2 else { path.addLine(to: p2); return }
        let phi = rotation * .pi / 180
        let cosP = cos(phi), sinP = sin(phi)
        let dx = (p1.x - p2.x) / 2, dy = (p1.y - p2.y) / 2
        let x1p = cosP * dx + sinP * dy
        let y1p = -sinP * dx + cosP * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = den == 0 ? 0 : sqrt(max(0, num / den))
        if large == sweep { coef = -coef }
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx
        let cx = cosP * cxp - sinP * cyp + (p1.x + p2.x) / 2
        let cy = sinP * cxp + cosP * cyp + (p1.y + p2.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        var t = theta1
        for _ in 0..<segments {
            let t2 = t + step
            let k = 4.0 / 3.0 * tan(step / 4)
            let c1 = CGPoint(x: cos(t) - k * sin(t), y: sin(t) + k * cos(t))
            let c2 = CGPoint(x: cos(t2) + k * sin(t2), y: sin(t2) - k * cos(t2))
            let e = CGPoint(x: cos(t2), y: sin(t2))
            func map(_ p: CGPoint) -> CGPoint {
                CGPoint(x: cx + rx * p.x * cosP - ry * p.y * sinP, y: cy + rx * p.x * sinP + ry * p.y * cosP)
            }
            path.addCurve(to: map(e), control1: map(c1), control2: map(c2))
            t = t2
        }
    }
}

/// A stroked line icon drawn from SVG path data in a square viewBox.
struct LineIcon: View {
    var d: String
    var size: CGFloat = 16
    var viewBox: CGFloat = 16
    var lineWidth: CGFloat = 1.4

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / viewBox
            var transform = CGAffineTransform(scaleX: scale, y: scale)
            guard let cg = SVGPath.path(d).copy(using: &transform) else { return }
            context.stroke(Path(cg), with: .foreground,
                           style: StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Filled shape from SVG path data.
struct SVGShape: Shape {
    var d: String
    var viewBox: CGSize

    func path(in rect: CGRect) -> Path {
        var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / viewBox.width, y: rect.height / viewBox.height)
        return Path(SVGPath.path(d).copy(using: &transform) ?? CGMutablePath())
    }
}
