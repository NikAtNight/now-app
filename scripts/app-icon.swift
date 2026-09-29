// Draws the Podium app icon. Run from the repo root:
//   swiftc -O scripts/app-icon.swift -o /tmp/app-icon && /tmp/app-icon Resources/Assets.xcassets/AppIcon.appiconset
//
// A white swallowtail pennant on a gold pole (first place), on a midnight tile.

import AppKit
import CoreGraphics

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

let tileColors = [rgb(0.16, 0.20, 0.42), rgb(0.07, 0.08, 0.20)]
let gold = rgb(1, 0.78, 0.30)

/// Draws in a 1024 design space with y pointing down.
func drawIcon(_ ctx: CGContext, size s: CGFloat, mac: Bool) {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: s / 1024, y: -s / 1024)

    // Mac icons use Apple's grid: an 824pt tile centered in 1024 with a soft shadow. iOS is full bleed; the system masks it.
    let inset: CGFloat = mac ? 100 : 0
    let tile = CGRect(x: inset, y: inset, width: 1024 - 2 * inset, height: 1024 - 2 * inset)
    let tilePath = mac ? CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil) : CGPath(rect: tile, transform: nil)

    if mac {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 30, color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(tilePath); ctx.setFillColor(tileColors[0]); ctx.fillPath()
        ctx.restoreGState()
    }

    // Midnight tile with a soft sheen from the top left.
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    ctx.drawLinearGradient(CGGradient(colorsSpace: cs, colors: tileColors as CFArray, locations: nil)!,
                           start: CGPoint(x: tile.minX, y: tile.minY), end: CGPoint(x: tile.maxX, y: tile.maxY), options: [])
    let sheen = CGGradient(colorsSpace: cs, colors: [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    let sheenCenter = CGPoint(x: tile.minX + tile.width * 0.3, y: tile.minY)
    ctx.drawRadialGradient(sheen, startCenter: sheenCenter, startRadius: 0, endCenter: sheenCenter, endRadius: tile.width * 0.75, options: [])
    ctx.restoreGState()

    // Gold pole with a ball finial, tilted like a planted flag.
    let poleTop = CGPoint(x: 330, y: 232), poleBottom = CGPoint(x: 272, y: 858)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 28, color: CGColor(gray: 0, alpha: 0.28))
    ctx.setStrokeColor(gold); ctx.setLineWidth(44); ctx.setLineCap(.round)
    ctx.move(to: poleTop); ctx.addLine(to: poleBottom); ctx.strokePath()
    ctx.setFillColor(gold)
    ctx.fillEllipse(in: CGRect(x: poleTop.x - 42, y: poleTop.y - 70, width: 84, height: 84))
    ctx.restoreGState()

    // Waving pennant with a swallowtail.
    let flag = CGMutablePath()
    flag.move(to: CGPoint(x: 332, y: 262))
    flag.addCurve(to: CGPoint(x: 828, y: 300), control1: CGPoint(x: 480, y: 200), control2: CGPoint(x: 660, y: 360))
    flag.addLine(to: CGPoint(x: 700, y: 452))
    flag.addLine(to: CGPoint(x: 846, y: 628))
    flag.addCurve(to: CGPoint(x: 302, y: 600), control1: CGPoint(x: 660, y: 700), control2: CGPoint(x: 470, y: 540))
    flag.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 36, color: CGColor(gray: 0, alpha: 0.30))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(flag); ctx.clip()
    let cloth = CGGradient(colorsSpace: cs, colors: [CGColor(gray: 1, alpha: 1), rgb(0.88, 0.91, 1)] as CFArray, locations: nil)!
    ctx.drawLinearGradient(cloth, start: CGPoint(x: 330, y: 250), end: CGPoint(x: 840, y: 640), options: [])
    // A soft fold shadow where the cloth dips.
    let fold = CGGradient(colorsSpace: cs, colors: [rgb(0.1, 0.12, 0.3, 0), rgb(0.1, 0.12, 0.3, 0.16), rgb(0.1, 0.12, 0.3, 0)] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(fold, start: CGPoint(x: 560, y: 0), end: CGPoint(x: 760, y: 0), options: [])

    ctx.endTransparencyLayer()
    ctx.restoreGState()

    ctx.restoreGState()
}

func render(size: Int, mac: Bool, to file: String) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: mac ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!
    drawIcon(ctx, size: CGFloat(size), mac: mac)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: file))
}

let out = CommandLine.arguments[1]
render(size: 1024, mac: false, to: "\(out)/icon-ios-1024.png")
for size in [16, 32, 64, 128, 256, 512, 1024] {
    render(size: size, mac: true, to: "\(out)/icon-mac-\(size).png")
}
