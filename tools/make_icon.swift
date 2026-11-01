// Renders the app icon: Roman sunset, St. Peter's dome, Bernini's golden Gloria with the
// Holy Spirit dove, and interlocked wedding rings joined by a gold cross (the sign of Catholic matrimony).
// Usage: swift tools/make_icon.swift AirfareTrack/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let S = CGFloat(size)
let space = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: space,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255, a,
        ]
    )!
}

func gradient(_ stops: [(UInt32, CGFloat)], alpha: CGFloat = 1) -> CGGradient {
    CGGradient(
        colorsSpace: space, colors: stops.map { rgb($0.0, alpha) } as CFArray,
        locations: stops.map(\.1)
    )!
}

// Fill each subpath on its own so overlapping shapes never cancel into holes.
func fillPieces(_ path: CGPath) {
    var piece = CGMutablePath()
    path.applyWithBlock { element in
        let e = element.pointee
        let p = e.points
        switch e.type {
        case .moveToPoint:
            if !piece.isEmpty { ctx.addPath(piece); ctx.fillPath() }
            piece = CGMutablePath()
            piece.move(to: p[0])
        case .addLineToPoint: piece.addLine(to: p[0])
        case .addQuadCurveToPoint: piece.addQuadCurve(to: p[1], control: p[0])
        case .addCurveToPoint: piece.addCurve(to: p[2], control1: p[0], control2: p[1])
        case .closeSubpath: piece.closeSubpath()
        @unknown default: break
        }
    }
    if !piece.isEmpty { ctx.addPath(piece); ctx.fillPath() }
}

// MARK: Sky — midnight → wine → rose-gold horizon (CG origin is bottom-left)
ctx.drawLinearGradient(
    gradient([(0xF6B65C, 0), (0xE07A5F, 0.22), (0x9B2F55, 0.48), (0x3E1A4D, 0.75), (0x120C2B, 1)]),
    start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: S), options: []
)

// Warm sun glow behind the dome
ctx.drawRadialGradient(
    CGGradient(colorsSpace: space, colors: [rgb(0xFFD58A, 0.85), rgb(0xFF9E6B, 0.35), rgb(0xFF9E6B, 0)] as CFArray,
               locations: [0, 0.35, 1])!,
    startCenter: CGPoint(x: 512, y: 300), startRadius: 0,
    endCenter: CGPoint(x: 512, y: 300), endRadius: 520, options: []
)

// A few stars up high
let stars: [(CGFloat, CGFloat, CGFloat)] = [
    (150, 930, 4), (300, 870, 2.5), (820, 940, 3.5), (900, 820, 2.5), (690, 975, 2), (90, 790, 2),
    (420, 960, 2), (960, 960, 2),
]
for (x, y, r) in stars {
    ctx.setFillColor(rgb(0xFFF4DD, 0.85))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

// MARK: Bernini's Gloria — golden rays bursting from the cross, like the Cathedra Petri window
let gloriaCenter = CGPoint(x: 512, y: 758)
ctx.saveGState()
let rays = CGMutablePath()
let rayCount = 40
for i in 0..<rayCount {
    let a = CGFloat(i) / CGFloat(rayCount) * 2 * .pi
    let half = (i % 2 == 0 ? 0.013 : 0.008) * CGFloat.pi
    let length: CGFloat = i % 2 == 0 ? 620 : 430
    rays.move(to: gloriaCenter)
    rays.addLine(to: CGPoint(x: gloriaCenter.x + cos(a - half) * length, y: gloriaCenter.y + sin(a - half) * length))
    rays.addLine(to: CGPoint(x: gloriaCenter.x + cos(a + half) * length, y: gloriaCenter.y + sin(a + half) * length))
    rays.closeSubpath()
}
ctx.addPath(rays)
ctx.clip()
ctx.drawRadialGradient(
    CGGradient(colorsSpace: space, colors: [rgb(0xFFF1C2, 0.6), rgb(0xFFDB8A, 0.3), rgb(0xFFDB8A, 0.08), rgb(0xFFDB8A, 0)] as CFArray,
               locations: [0, 0.4, 0.75, 1])!,
    startCenter: gloriaCenter, startRadius: 0, endCenter: gloriaCenter, endRadius: 640, options: []
)
ctx.restoreGState()
// Bright halo at the heart of the Gloria
ctx.drawRadialGradient(
    CGGradient(colorsSpace: space, colors: [rgb(0xFFF7DC, 0.45), rgb(0xFFE3A0, 0.18), rgb(0xFFE3A0, 0)] as CFArray,
               locations: [0, 0.4, 1])!,
    startCenter: gloriaCenter, startRadius: 0, endCenter: gloriaCenter, endRadius: 230, options: []
)

// MARK: Interlocked gold rings
let ringRadius: CGFloat = 165
let ringWidth: CGFloat = 26
let ringY: CGFloat = 620
let leftCenter = CGPoint(x: 512 - 70, y: ringY)
let rightCenter = CGPoint(x: 512 + 70, y: ringY)
let gold = gradient([(0x8A5A12, 0), (0xF8E3A3, 0.35), (0xD4A23C, 0.6), (0xFFF3C4, 0.8), (0xA8741E, 1)])

func drawRing(_ center: CGPoint, clip: CGRect? = nil) {
    ctx.saveGState()
    if let clip { ctx.clip(to: clip) }
    let circle = CGPath(ellipseIn: CGRect(x: center.x - ringRadius, y: center.y - ringRadius,
                                          width: ringRadius * 2, height: ringRadius * 2), transform: nil)
    // soft shadow
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: rgb(0x1A0612, 0.55))
    ctx.addPath(circle)
    ctx.setLineWidth(ringWidth)
    ctx.setStrokeColor(rgb(0xC8962F))
    ctx.strokePath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    // metallic gradient fill of the stroke
    ctx.addPath(circle)
    ctx.setLineWidth(ringWidth)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(gold,
                           start: CGPoint(x: center.x - ringRadius, y: center.y + ringRadius),
                           end: CGPoint(x: center.x + ringRadius, y: center.y - ringRadius), options: [])
    ctx.restoreGState()
}

drawRing(leftCenter)
drawRing(rightCenter)
// Interlock: bring the left ring back over the right one at the upper crossing.
let dx: CGFloat = 70
let crossY = ringY + sqrt(ringRadius * ringRadius - dx * dx)
drawRing(leftCenter, clip: CGRect(x: 512 - 40, y: crossY - 40, width: 80, height: 80))

// MARK: St. Peter's silhouette
let ink = rgb(0x1C0B1E)
let silhouette = CGMutablePath()

// Bernini's colonnade sweeping across the bottom, then the facade
silhouette.addRect(CGRect(x: 0, y: 0, width: 1024, height: 92))
silhouette.addRect(CGRect(x: 0, y: 92, width: 1024, height: 8))      // colonnade cornice
for i in 0..<21 {                                                      // colonnade statues
    let x = 24 + CGFloat(i) * 48.8
    silhouette.addRect(CGRect(x: x - 3, y: 100, width: 6, height: 14))
    silhouette.addEllipse(in: CGRect(x: x - 4.5, y: 111, width: 9, height: 9))
}
silhouette.addRect(CGRect(x: 196, y: 100, width: 632, height: 92))    // facade
silhouette.addRect(CGRect(x: 186, y: 186, width: 652, height: 10))    // facade cornice
silhouette.addRect(CGRect(x: 214, y: 196, width: 596, height: 22))    // attic
for i in 0..<13 {                                                      // apostles on the attic
    let x = 226 + CGFloat(i) * 47.6
    silhouette.addRect(CGRect(x: x - 4, y: 218, width: 8, height: 18))
    silhouette.addEllipse(in: CGRect(x: x - 6, y: 233, width: 12, height: 12))
}

// Side cupolas
for cx in [CGFloat(262), 762] {
    silhouette.addRect(CGRect(x: cx - 41, y: 218, width: 82, height: 26))
    silhouette.move(to: CGPoint(x: cx - 40, y: 242))
    silhouette.addCurve(to: CGPoint(x: cx, y: 306), control1: CGPoint(x: cx - 40, y: 282), control2: CGPoint(x: cx - 16, y: 302))
    silhouette.addCurve(to: CGPoint(x: cx + 40, y: 242), control1: CGPoint(x: cx + 16, y: 302), control2: CGPoint(x: cx + 40, y: 282))
    silhouette.closeSubpath()
    silhouette.addRect(CGRect(x: cx - 5, y: 302, width: 10, height: 20))
    silhouette.addEllipse(in: CGRect(x: cx - 6, y: 318, width: 12, height: 12))
}

// Drum
silhouette.addRect(CGRect(x: 342, y: 218, width: 340, height: 98))
silhouette.addRect(CGRect(x: 330, y: 312, width: 364, height: 16))   // cornice

// Main dome (slightly ogival, like Michelangelo's)
silhouette.move(to: CGPoint(x: 336, y: 328))
silhouette.addCurve(to: CGPoint(x: 512, y: 560), control1: CGPoint(x: 336, y: 470), control2: CGPoint(x: 430, y: 548))
silhouette.addCurve(to: CGPoint(x: 688, y: 328), control1: CGPoint(x: 594, y: 548), control2: CGPoint(x: 688, y: 470))
silhouette.closeSubpath()

// Lantern (with a collar that blends it into the dome's crown)
silhouette.addEllipse(in: CGRect(x: 456, y: 522, width: 112, height: 50))
silhouette.addRect(CGRect(x: 478, y: 548, width: 68, height: 66))
silhouette.addRect(CGRect(x: 470, y: 610, width: 84, height: 10))
silhouette.move(to: CGPoint(x: 482, y: 620))
silhouette.addQuadCurve(to: CGPoint(x: 542, y: 620), control: CGPoint(x: 512, y: 668))
silhouette.closeSubpath()
silhouette.addEllipse(in: CGRect(x: 501, y: 650, width: 22, height: 22))

ctx.setFillColor(ink)
fillPieces(silhouette)

// Lit windows in the drum: thin warm slits
ctx.setFillColor(rgb(0xF2A65A, 0.55))
for i in 0..<8 {
    let x = 362 + CGFloat(i) * 42
    ctx.fill(CGRect(x: x, y: 240, width: 10, height: 52))
}

// Glimmer between the colonnade columns
ctx.setFillColor(rgb(0xF6B65C, 0.22))
for i in 0..<42 {
    let x = 8 + CGFloat(i) * 24.4
    if x > 190 && x < 834 { continue }
    ctx.fill(CGRect(x: x, y: 14, width: 7, height: 64))
}
ctx.setFillColor(rgb(0xF6B65C, 0.18))
for i in 0..<12 {
    let x = 222 + CGFloat(i) * 50
    ctx.fill(CGRect(x: x, y: 118, width: 12, height: 52))
}


// MARK: Gold cross rising from the lantern through the rings
let cross = CGMutablePath()
cross.addLines(between: [
    CGPoint(x: 500, y: 664), CGPoint(x: 524, y: 664), CGPoint(x: 524, y: 752), CGPoint(x: 564, y: 752),
    CGPoint(x: 564, y: 776), CGPoint(x: 524, y: 776), CGPoint(x: 524, y: 832), CGPoint(x: 500, y: 832),
    CGPoint(x: 500, y: 776), CGPoint(x: 460, y: 776), CGPoint(x: 460, y: 752), CGPoint(x: 500, y: 752),
])
cross.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 30, color: rgb(0xFFE2A0, 0.9))
ctx.addPath(cross)
ctx.setFillColor(rgb(0xF4D27E))
ctx.fillPath()
ctx.restoreGState()
ctx.addPath(cross)
ctx.setLineWidth(7)
ctx.setLineJoin(.miter)
ctx.setStrokeColor(rgb(0x2A0F22, 0.85))
ctx.strokePath()
ctx.saveGState()
ctx.addPath(cross)
ctx.clip()
ctx.drawLinearGradient(gold, start: CGPoint(x: 460, y: 832), end: CGPoint(x: 564, y: 664), options: [])
ctx.restoreGState()

// MARK: The dove of the Holy Spirit, descending above the cross
func dove(at c: CGPoint, scale k: CGFloat) -> CGPath {
    var t = CGAffineTransform(translationX: c.x, y: c.y).scaledBy(x: k, y: k)
    let p = CGMutablePath()
    // body and head (head points down: descending)
    p.addEllipse(in: CGRect(x: -13, y: -30, width: 26, height: 62), transform: t)
    p.addEllipse(in: CGRect(x: -12, y: -50, width: 24, height: 24), transform: t)
    // tail fan
    p.move(to: CGPoint(x: -9, y: 22), transform: t)
    p.addLine(to: CGPoint(x: -20, y: 66), transform: t)
    p.addQuadCurve(to: CGPoint(x: 20, y: 66), control: CGPoint(x: 0, y: 76), transform: t)
    p.addLine(to: CGPoint(x: 9, y: 22), transform: t)
    p.closeSubpath()
    // wings, raised and spread, with feathered trailing edges
    for side in [CGFloat(-1), 1] {
        t = CGAffineTransform(translationX: c.x, y: c.y).scaledBy(x: k * side, y: k)
        p.move(to: CGPoint(x: 6, y: 16), transform: t)
        p.addCurve(to: CGPoint(x: 118, y: 74), control1: CGPoint(x: 40, y: 50), control2: CGPoint(x: 80, y: 80), transform: t)
        p.addQuadCurve(to: CGPoint(x: 98, y: 50), control: CGPoint(x: 116, y: 56), transform: t)
        p.addQuadCurve(to: CGPoint(x: 82, y: 30), control: CGPoint(x: 96, y: 34), transform: t)
        p.addQuadCurve(to: CGPoint(x: 62, y: 12), control: CGPoint(x: 78, y: 14), transform: t)
        p.addQuadCurve(to: CGPoint(x: 8, y: -12), control: CGPoint(x: 40, y: -6), transform: t)
        p.closeSubpath()
    }
    return p
}
let dovePath = dove(at: CGPoint(x: 512, y: 902), scale: 0.95)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 26, color: rgb(0xFFE7B0, 0.95))
ctx.setFillColor(rgb(0xFFFBF2))
fillPieces(dovePath)
ctx.restoreGState()

// MARK: Write PNG
let image = ctx.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png")
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("Wrote \(url.path)")
