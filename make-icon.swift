//
//  make-icon.swift
//  XDRGamma
//
//  Draws AppIcon.icns. Every size is rendered from the vector description
//  rather than downscaled from one bitmap, so the 16pt version stays crisp.
//
//  Usage: swift make-icon.swift
//

import AppKit
import CoreGraphics

let canvas = 1024.0
/// Apple's icon grid: the body fills 824 of a 1024 canvas, the rest is the
/// breathing room the system expects around it.
let bodyInset = 100.0

func superellipse(in rect: CGRect, n: Double = 5.0, samples: Int = 720) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    for i in 0...samples {
        let t = Double(i) / Double(samples) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * pow(abs(ct), 2 / n) * (ct < 0 ? -1 : 1)
        let y = cy + b * pow(abs(st), 2 / n) * (st < 0 ? -1 : 1)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// SF Symbol filled with a gradient: draw the gradient, then keep only the
/// pixels the glyph covers.
func sunGlyph(pixels: Int, fill: CGGradient, in rect: CGRect,
              space: CGColorSpace) -> CGImage? {
    let cfg = NSImage.SymbolConfiguration(pointSize: 512, weight: .regular)
    guard let symbol = NSImage(systemSymbolName: "sun.max.fill",
                               accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) else { return nil }
    var box = CGRect(origin: .zero, size: symbol.size)
    guard let glyph = symbol.cgImage(forProposedRect: &box, context: nil, hints: nil),
          let ctx = CGContext(data: nil, width: pixels, height: pixels,
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    // Preserve the glyph's aspect ratio inside the requested box.
    let aspect = Double(glyph.width) / Double(glyph.height)
    var target = rect
    if aspect > 1 {
        target.size.height = rect.width / aspect
        target.origin.y = rect.midY - target.height / 2
    } else {
        target.size.width = rect.height * aspect
        target.origin.x = rect.midX - target.width / 2
    }

    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    // Glyph first, so the layer carries its alpha; then .sourceIn paints the
    // gradient only where the glyph already is.
    ctx.draw(glyph, in: target)
    ctx.setBlendMode(.sourceIn)
    ctx.drawRadialGradient(fill,
                           startCenter: CGPoint(x: target.midX - 60, y: target.midY + 70),
                           startRadius: 0,
                           endCenter: CGPoint(x: target.midX, y: target.midY),
                           endRadius: target.width * 0.62,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    return ctx.makeImage()
}

func draw(size: Int) -> CGImage {
    let s = Double(size) / canvas          // scale from the 1024 design grid
    let space = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let body = CGRect(x: bodyInset, y: bodyInset,
                      width: canvas - 2 * bodyInset, height: canvas - 2 * bodyInset)
    let shape = superellipse(in: body)

    // Panel body: near-black, lifting slightly toward the top edge.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let bg = CGGradient(colorsSpace: space,
                        colors: [rgb(0.16, 0.17, 0.20), rgb(0.05, 0.05, 0.07)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: body.maxY),
                           end: CGPoint(x: 0, y: body.minY), options: [])

    let cx = body.midX, cy = body.midY

    // The bloom is the point of the app: light spilling past the ceiling.
    // Drawn wide and soft, underneath the glyph.
    let bloom = CGGradient(colorsSpace: space, colors: [
        rgb(1.0, 0.90, 0.62, 0.60), rgb(1.0, 0.74, 0.33, 0.24),
        rgb(1.0, 0.62, 0.22, 0.06), rgb(1.0, 0.60, 0.20, 0.0)
    ] as CFArray, locations: [0, 0.38, 0.72, 1])!
    ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                           endCenter: CGPoint(x: cx, y: cy), endRadius: 430, options: [])

    // The sun itself is SF Symbol sun.max.fill — the same glyph the menu bar
    // shows, so the two read as one app. Apple's geometry beats anything hand
    // rolled here, especially at 16pt.
    let glyphBox = 672.0
    let glyphRect = CGRect(x: cx - glyphBox / 2, y: cy - glyphBox / 2,
                           width: glyphBox, height: glyphBox)
    let warm = CGGradient(colorsSpace: space, colors: [
        rgb(1.0, 1.0, 0.98), rgb(1.0, 0.93, 0.72), rgb(1.0, 0.74, 0.32)
    ] as CFArray, locations: [0, 0.5, 1])!
    if let glyph = sunGlyph(pixels: 1024, fill: warm, in: glyphRect, space: space) {
        ctx.draw(glyph, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
    }
    ctx.restoreGState()

    // Hairline rim so the body separates from a dark wallpaper.
    ctx.addPath(shape)
    ctx.setStrokeColor(rgb(1, 1, 1, 0.10))
    ctx.setLineWidth(3)
    ctx.strokePath()

    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                    (256, 1), (256, 2), (512, 1), (512, 2)] {
    let px = pt * scale
    let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
    write(draw(size: px), to: iconset.appendingPathComponent(name))
}
print("AppIcon.iconset is ready")
