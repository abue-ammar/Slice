#!/usr/bin/env swift
//
//  cape-to-svg.swift
//  Scripts
//
//  Created by rit3zh CX on 10/6/26.
//

// Converts a Mousecape .cape (a plist of HEIC cursor images) into SVGs named like the Recordly cursor sets, which
// scripts/make-cursors.swift reads: `<name>-<frame>__<x>-<y>.svg`, the hotspot as a percentage of the canvas.
//   swift scripts/cape-to-svg.swift [cape] [output folder]
// Each SVG is sized in points (the cape's canvas) and holds the cape's densest artwork for that cursor as a lossless
// PNG; animated cursors (frames stacked top to bottom) give one SVG per frame.
import Foundation
import ImageIO

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let args = CommandLine.arguments
let cape = args.count > 1 ? URL(fileURLWithPath: args[1]) : root.appendingPathComponent("inspo/assets/macos-27-cape-cursor/MacOS 27.cape")
let output = args.count > 2 ? URL(fileURLWithPath: args[2]) : root.appendingPathComponent("inspo/assets/macos-27-cursor")

let names: [String: String] = [
    "com.apple.coregraphics.Arrow": "pointer",
    "com.apple.coregraphics.ArrowCtx": "contextualarrow",
    "com.apple.coregraphics.IBeam": "ibeam",
    "com.apple.coregraphics.IBeamXOR": "ibeamxor",
    "com.apple.coregraphics.Move": "legacymove",
    "com.apple.coregraphics.Wait": "beachball",
    "com.apple.cursor.2": "makealias",
    "com.apple.cursor.3": "notallowed",
    "com.apple.cursor.4": "busybutclickable",
    "com.apple.cursor.5": "copy",
    "com.apple.cursor.7": "crosshair",
    "com.apple.cursor.8": "crosshair2",
    "com.apple.cursor.9": "camera2",
    "com.apple.cursor.10": "camera",
    "com.apple.cursor.11": "closedhand",
    "com.apple.cursor.12": "openhand",
    "com.apple.cursor.13": "pointinghand",
    "com.apple.cursor.14": "countingup",
    "com.apple.cursor.15": "countingdown",
    "com.apple.cursor.16": "countingupdown",
    "com.apple.cursor.17": "resizeleft",
    "com.apple.cursor.18": "resizeright",
    "com.apple.cursor.19": "resizeleftright",
    "com.apple.cursor.20": "cross",
    "com.apple.cursor.21": "resizeup",
    "com.apple.cursor.22": "resizedown",
    "com.apple.cursor.23": "resizeupdown",
    "com.apple.cursor.24": "contextualmenu",
    "com.apple.cursor.25": "poof",
    "com.apple.cursor.26": "ibeamvertical",
    "com.apple.cursor.27": "resizeeast",
    "com.apple.cursor.28": "resizeeastwest",
    "com.apple.cursor.29": "resizenortheast",
    "com.apple.cursor.30": "resizenortheastsouthwest",
    "com.apple.cursor.31": "resizenorth",
    "com.apple.cursor.32": "resizenorthsouth",
    "com.apple.cursor.33": "resizenorthwest",
    "com.apple.cursor.34": "resizenorthwestsoutheast",
    "com.apple.cursor.35": "resizesoutheast",
    "com.apple.cursor.36": "resizesouth",
    "com.apple.cursor.37": "resizesouthwest",
    "com.apple.cursor.38": "resizewest",
    "com.apple.cursor.39": "move",
    "com.apple.cursor.40": "help",
    "com.apple.cursor.41": "cell",
    "com.apple.cursor.42": "zoomin",
    "com.apple.cursor.43": "zoomout",
]

func format(_ value: Double) -> String {
    var s = String(format: "%.2f", value)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}

func png(_ image: CGImage) -> Data {
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}

let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: cape), format: nil) as! [String: Any]
let cursors = plist["Cursors"] as! [String: [String: Any]]
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for (id, cursor) in cursors.sorted(by: { $0.key < $1.key }) {
    guard let name = names[id] else { print("skipped \(id)"); continue }
    let width = (cursor["PointsWide"] as! NSNumber).doubleValue, height = (cursor["PointsHigh"] as! NSNumber).doubleValue
    let hotX = (cursor["HotSpotX"] as! NSNumber).doubleValue, hotY = (cursor["HotSpotY"] as! NSNumber).doubleValue
    let frames = max((cursor["FrameCount"] as! NSNumber).intValue, 1)
    let strip = (cursor["Representations"] as! [Data])
        .compactMap { CGImageSourceCreateWithData($0 as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) } }
        .max { $0.width < $1.width }
    guard let strip else { print("unreadable \(id)"); continue }
    let frameHeight = strip.height / frames
    let suffix = "__\(format(hotX / width * 100))-\(format(hotY / height * 100))"
    for frame in 0 ..< frames {
        guard let image = strip.cropping(to: CGRect(x: 0, y: frame * frameHeight, width: strip.width, height: frameHeight)) else { continue }
        let svg = """
        <svg width="\(format(width))" height="\(format(height))" viewBox="0 0 \(image.width) \(image.height)" xmlns="http://www.w3.org/2000/svg">
        <image width="\(image.width)" height="\(image.height)" href="data:image/png;base64,\(png(image).base64EncodedString())"/>
        </svg>

        """
        try svg.write(to: output.appendingPathComponent("\(name)-\(frame + 1)\(suffix).svg"), atomically: true, encoding: .utf8)
    }
    print("\(name) ← \(id)  \(strip.width)×\(frameHeight)\(frames > 1 ? " × \(frames) frames" : "")")
}
