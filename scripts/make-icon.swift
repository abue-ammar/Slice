//
//  make-icon.swift
//  Scripts
//
//  Created by rit3zh CX on 10/6/26.
//

// Renders the app icon (1024px master) and the asset-catalog sizes. Run: swift scripts/make-icon.swift
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "App/Resources/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill()
    bodyPath.fill()
    ctx.restoreGState()
    ctx.saveGState()
    bodyPath.addClip()
    NSGradient(colors: [NSColor(red: 0.33, green: 0.27, blue: 0.86, alpha: 1), NSColor(red: 0.93, green: 0.44, blue: 0.62, alpha: 1)])!
        .draw(in: body, angle: -55)
    ctx.restoreGState()

    let screen = CGRect(x: 190, y: 330, width: 560, height: 400)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    NSColor(white: 0.98, alpha: 1).setFill()
    NSBezierPath(roundedRect: screen, xRadius: 34, yRadius: 34).fill()
    ctx.restoreGState()
    ctx.saveGState()
    NSBezierPath(roundedRect: screen, xRadius: 34, yRadius: 34).addClip()
    NSColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1).setFill()
    CGRect(x: screen.minX, y: screen.maxY - 58, width: screen.width, height: 58).fill()
    for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
        c.setFill()
        NSBezierPath(ovalIn: CGRect(x: screen.minX + 30 + CGFloat(i) * 34, y: screen.maxY - 40, width: 20, height: 20)).fill()
    }
    NSColor(white: 0.84, alpha: 1).setFill()
    for i in 0 ..< 4 {
        let w: CGFloat = [300, 360, 250, 320][i]
        NSBezierPath(roundedRect: CGRect(x: screen.minX + 44, y: screen.maxY - 120 - CGFloat(i) * 56, width: w, height: 22),
                     xRadius: 11, yRadius: 11).fill()
    }
    ctx.restoreGState()

    let cam = CGRect(x: 560, y: 190, width: 290, height: 290)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: cam, xRadius: 78, yRadius: 78).fill()
    ctx.restoreGState()
    let inner = cam.insetBy(dx: 14, dy: 14)
    ctx.saveGState()
    NSBezierPath(roundedRect: inner, xRadius: 66, yRadius: 66).addClip()
    NSGradient(colors: [NSColor(red: 0.20, green: 0.22, blue: 0.45, alpha: 1), NSColor(red: 0.12, green: 0.13, blue: 0.28, alpha: 1)])!
        .draw(in: inner, angle: -90)
    NSColor(red: 1, green: 0.84, blue: 0.68, alpha: 1).setFill()
    NSBezierPath(ovalIn: CGRect(x: inner.midX - 48, y: inner.midY - 8, width: 96, height: 104)).fill()
    NSBezierPath(ovalIn: CGRect(x: inner.midX - 95, y: inner.minY - 70, width: 190, height: 150)).fill()
    ctx.restoreGState()

    let dot = CGRect(x: 205, y: 175, width: 120, height: 120)
    NSColor.white.setFill()
    NSBezierPath(ovalIn: dot.insetBy(dx: -12, dy: -12)).fill()
    NSColor(red: 0.95, green: 0.22, blue: 0.25, alpha: 1).setFill()
    NSBezierPath(ovalIn: dot).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

var images: [[String: String]] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        try! render(pt * scale).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: out.appendingPathComponent("Contents.json"))
let catalog = out.deletingLastPathComponent().appendingPathComponent("Contents.json")
try! #"{"info":{"author":"xcode","version":1}}"#.write(to: catalog, atomically: true, encoding: .utf8)
print("Icon written to \(out.path)")
