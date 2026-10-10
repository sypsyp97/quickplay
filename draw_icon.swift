// Renders the QuickPlay app icon (1024 px PNG) to the path given as the first argument.
// Motif: a Quick Look lens whose glass holds a play triangle, on a deep blue squircle.
import AppKit

let side: CGFloat = 1024
let out = CommandLine.arguments[1]

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func linear(_ colors: [CGColor], _ from: CGPoint, _ to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

// Superellipse (n = 5) approximates the macOS continuous-corner squircle.
func squircle(_ rect: CGRect) -> CGPath {
    let p = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2, n: CGFloat = 5
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

// Standard macOS icon grid: 824 px body centred in the 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = squircle(body)

// Drop shadow under the body.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(shape); ctx.setFillColor(rgb(0x101626)); ctx.fillPath()
ctx.restoreGState()

// Body: deep blue gradient with a soft glow behind the lens.
ctx.saveGState()
ctx.addPath(shape); ctx.clip()
linear([rgb(0x2E3A66), rgb(0x0F1427)], CGPoint(x: 0, y: body.maxY), CGPoint(x: 0, y: body.minY))
let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                      colors: [rgb(0xFF7A59, 0.35), rgb(0xFF7A59, 0)] as CFArray, locations: nil)!
let lensCenter = CGPoint(x: 470, y: 560)
ctx.drawRadialGradient(glow, startCenter: lensCenter, startRadius: 0, endCenter: lensCenter, endRadius: 420, options: [])
// Top sheen.
linear([rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)], CGPoint(x: 0, y: body.maxY), CGPoint(x: 0, y: body.midY))
ctx.restoreGState()

// Inner hairline on the body edge.
ctx.addPath(shape); ctx.setStrokeColor(rgb(0xFFFFFF, 0.12)); ctx.setLineWidth(3); ctx.strokePath()

let lensRadius: CGFloat = 230
let ringWidth: CGFloat = 44

// Direction along the handle (down-right) and its normal, for cylinder shading.
let angle = -CGFloat.pi / 4
let dir = CGPoint(x: cos(angle), y: sin(angle))
let normal = CGPoint(x: -dir.y, y: dir.x)
func along(_ d: CGFloat) -> CGPoint { CGPoint(x: lensCenter.x + dir.x * d, y: lensCenter.y + dir.y * d) }

// One handle segment: a round-capped bar shaded across its width like a cylinder.
func bar(from a: CGFloat, to b: CGFloat, width: CGFloat, colors: [CGColor]) {
    ctx.saveGState()
    let path = CGMutablePath()
    path.move(to: along(a)); path.addLine(to: along(b))
    ctx.addPath(path)
    ctx.setLineWidth(width); ctx.setLineCap(.round)
    ctx.replacePathWithStrokedPath(); ctx.clip()
    let mid = along((a + b) / 2)
    let half = width / 2
    linear(colors, CGPoint(x: mid.x + normal.x * half, y: mid.y + normal.y * half),
           CGPoint(x: mid.x - normal.x * half, y: mid.y - normal.y * half))
    ctx.restoreGState()
}

// Handle shadow, then a silver neck and a darker graphite grip. Drawn before the ring,
// so the ring covers the neck's inner end.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: rgb(0x000000, 0.45))
let shadowPath = CGMutablePath()
shadowPath.move(to: along(lensRadius)); shadowPath.addLine(to: along(lensRadius + 190))
ctx.addPath(shadowPath)
ctx.setLineWidth(78); ctx.setLineCap(.round); ctx.setStrokeColor(rgb(0x1B2238)); ctx.strokePath()
ctx.restoreGState()
bar(from: lensRadius, to: lensRadius + 70, width: 50,
    colors: [rgb(0xF4F6FB), rgb(0xC4CBDC), rgb(0x8A93AC)])
bar(from: lensRadius + 64, to: lensRadius + 190, width: 78,
    colors: [rgb(0x8C96B4), rgb(0x5B6485), rgb(0x343B57)])
// Thin light edge so the grip separates from the dark body at small sizes.
ctx.saveGState()
let gripEdge = CGMutablePath()
gripEdge.move(to: along(lensRadius + 64)); gripEdge.addLine(to: along(lensRadius + 190))
ctx.addPath(gripEdge)
ctx.setLineWidth(78); ctx.setLineCap(.round)
ctx.replacePathWithStrokedPath()
ctx.setStrokeColor(rgb(0xFFFFFF, 0.22)); ctx.setLineWidth(3); ctx.strokePath()
ctx.restoreGState()
// Specular line along the grip.
ctx.saveGState()
let spec = CGMutablePath()
let off = CGPoint(x: normal.x * 18, y: normal.y * 18)
spec.move(to: CGPoint(x: along(lensRadius + 92).x + off.x, y: along(lensRadius + 92).y + off.y))
spec.addLine(to: CGPoint(x: along(lensRadius + 168).x + off.x, y: along(lensRadius + 168).y + off.y))
ctx.addPath(spec)
ctx.setLineWidth(8); ctx.setLineCap(.round); ctx.setStrokeColor(rgb(0xFFFFFF, 0.28)); ctx.strokePath()
ctx.restoreGState()

// Glass: dark tinted disc with an inner shadow at the rim.
let glass = CGRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius, width: lensRadius * 2, height: lensRadius * 2)
ctx.saveGState()
ctx.addEllipse(in: glass); ctx.clip()
linear([rgb(0x1C2446), rgb(0x0A0E1C)], CGPoint(x: 0, y: glass.maxY), CGPoint(x: 0, y: glass.minY))
let rim = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                     colors: [rgb(0x000000, 0), rgb(0x000000, 0.55)] as CFArray,
                     locations: [0.78, 1])!
ctx.drawRadialGradient(rim, startCenter: lensCenter, startRadius: 0, endCenter: lensCenter, endRadius: lensRadius, options: [])
ctx.restoreGState()

// Play triangle with rounded corners, optically centred (slightly right of the lens centre).
let tri = CGMutablePath()
let h: CGFloat = 220, w: CGFloat = h * 0.9
let cx = lensCenter.x + w * 0.1
let pA = CGPoint(x: cx - w / 2, y: lensCenter.y + h / 2)
let pB = CGPoint(x: cx + w / 2, y: lensCenter.y)
let pC = CGPoint(x: cx - w / 2, y: lensCenter.y - h / 2)
let r: CGFloat = 36
tri.move(to: CGPoint(x: (pA.x + pC.x) / 2, y: (pA.y + pC.y) / 2))
tri.addArc(tangent1End: pA, tangent2End: pB, radius: r)
tri.addArc(tangent1End: pB, tangent2End: pC, radius: r)
tri.addArc(tangent1End: pC, tangent2End: pA, radius: r)
tri.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 46, color: rgb(0xFF6A5C, 0.6))
ctx.addPath(tri); ctx.setFillColor(rgb(0xFF7A59)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(tri); ctx.clip()
linear([rgb(0xFFC062), rgb(0xFF7A59), rgb(0xFF4F6E)], CGPoint(x: pA.x, y: pA.y), CGPoint(x: pB.x, y: pC.y))
// Top light on the upper half of the triangle.
linear([rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)], CGPoint(x: 0, y: pA.y), CGPoint(x: 0, y: lensCenter.y))
ctx.restoreGState()

// Lens ring: brushed silver with a bevel (bright outer top edge, dark inner edge).
let outer = glass.insetBy(dx: -ringWidth / 2, dy: -ringWidth / 2)
let inner = glass.insetBy(dx: ringWidth / 2, dy: ringWidth / 2)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: rgb(0x000000, 0.4))
ctx.addEllipse(in: outer); ctx.addEllipse(in: inner)
ctx.setFillColor(rgb(0x9AA3BC)); ctx.fillPath(using: .evenOdd)
ctx.restoreGState()
ctx.saveGState()
ctx.addEllipse(in: outer); ctx.addEllipse(in: inner)
ctx.clip(using: .evenOdd)
linear([rgb(0xFFFFFF), rgb(0xD5DAE6), rgb(0x9AA3BC), rgb(0x6E7791)],
       CGPoint(x: outer.minX, y: outer.maxY), CGPoint(x: outer.maxX, y: outer.minY))
ctx.restoreGState()
ctx.addEllipse(in: outer.insetBy(dx: 1.5, dy: 1.5))
ctx.setStrokeColor(rgb(0xFFFFFF, 0.5)); ctx.setLineWidth(3); ctx.strokePath()
ctx.addEllipse(in: inner.insetBy(dx: -1.5, dy: -1.5))
ctx.setStrokeColor(rgb(0x0B0F1E, 0.6)); ctx.setLineWidth(3); ctx.strokePath()

// Glass reflection: a soft crescent at the upper left.
ctx.saveGState()
ctx.addEllipse(in: glass.insetBy(dx: 26, dy: 26)); ctx.clip()
let crescent = CGMutablePath()
crescent.addEllipse(in: glass.insetBy(dx: 26, dy: 26))
crescent.addEllipse(in: glass.insetBy(dx: 26, dy: 26).offsetBy(dx: 34, dy: -34))
ctx.addPath(crescent); ctx.clip(using: .evenOdd)
linear([rgb(0xFFFFFF, 0.38), rgb(0xFFFFFF, 0)], CGPoint(x: glass.minX, y: glass.maxY), CGPoint(x: lensCenter.x, y: lensCenter.y))
ctx.restoreGState()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
