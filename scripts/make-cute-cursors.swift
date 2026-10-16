#!/usr/bin/env swift
//
//  make-cute-cursors.swift
//  Scripts
//
//  Created by rit3zh CX on 10/15/26.
//

// Trims the cute cursor PNGs (inspo/assets/cute-cursors) into the sets SliceCore draws, one folder per set under
// Sources/SliceCore/Resources/Cursors/Cute, each with a hotspot manifest like the macOS sets'. Run again after changing them:
//   swift scripts/make-cute-cursors.swift
// An arrow's hotspot is its top-left-most opaque pixel (the tip); a hand's is the top of its finger.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("inspo/assets/cute-cursors")
let output = root.appendingPathComponent("Sources/SliceCore/Resources/Cursors/Cute")

let sets: [String: [String: String]] = [
    "Pompompurin": [
        "arrow": "Cute Sanrio Pompompurin Arrow & Hand Pointer Cursor--cursor--SweezyCursors.png",
        "pointingHand": "Cute Sanrio Pompompurin Arrow & Hand Pointer Cursor--pointer--SweezyCursors.png",
    ],
    "Pizza": [
        "arrow": "cute-pizza-slice-cursor-pack-arrow.png",
        "pointingHand": "cute-pizza-slice-cursor-pack-hand.png",
    ],
    "Watermelon": [
        "arrow": "Kawaii Watermelon Cursor--cursor--SweezyCursors.png",
    ],
]

/// Hotspots (pixels in the trimmed image) where finding them wouldn't work: Pompompurin wears a beret, so its
/// topmost pixels are the hat, not the tip of the arrow or the finger under it.
let hotspots: [String: CGPoint] = [
    "Pompompurin/arrow": CGPoint(x: 16, y: 21),
    "Pompompurin/pointingHand": CGPoint(x: 38, y: 21),
]

let targetPoints: CGFloat = 20

struct Entry: Encodable {
    var hotspotX: Int
    var hotspotY: Int
    var pixelsPerPoint: Double
}

func rgba(_ image: CGImage) -> (pixels: [UInt8], width: Int, height: Int) {
    let w = image.width, h = image.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (px, w, h)
}

for (set, files) in sets {
    let dir = output.appendingPathComponent(set)
    try? FileManager.default.removeItem(at: dir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var manifest: [String: Entry] = [:]
    for (type, file) in files {
        let url = source.appendingPathComponent(file)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("Can't read \(file)") }
        let (px, w, h) = rgba(image)
        func alpha(_ x: Int, _ y: Int) -> UInt8 { px[(y * w + x) * 4 + 3] }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0 ..< h { for x in 0 ..< w where alpha(x, y) > 8 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        let box = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        var hot = CGPoint.zero
        if type == "pointingHand" {
            let row = (minY ..< h).first { y in (0 ..< w).contains { alpha($0, y) > 128 } }!
            let xs = (0 ..< w).filter { alpha($0, row) > 128 }
            hot = CGPoint(x: (xs.first! + xs.last!) / 2, y: row)
        } else {
            var best = Int.max
            for y in 0 ..< h { for x in 0 ..< w where alpha(x, y) > 128 && x + y < best {
                best = x + y
                hot = CGPoint(x: x, y: y)
            } }
        }
        if let fixed = hotspots["\(set)/\(type)"] { hot = CGPoint(x: fixed.x + CGFloat(minX), y: fixed.y + CGFloat(minY)) }
        let cropped = image.cropping(to: box)!
        let out = dir.appendingPathComponent("\(type).png")
        let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cropped, nil)
        CGImageDestinationFinalize(dest)
        manifest[type] = Entry(hotspotX: Int(hot.x) - minX, hotspotY: Int(hot.y) - minY,
                               pixelsPerPoint: Double(max(box.width, box.height) / targetPoints))
        print("\(set)/\(type): \(Int(box.width))×\(Int(box.height)) hotspot \(Int(hot.x) - minX),\(Int(hot.y) - minY)")
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(to: dir.appendingPathComponent("cursors.json"))
}
