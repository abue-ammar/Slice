#!/usr/bin/env swift
//
//  make-cursors.swift
//  Scripts
//
//  Created by rit3zh CX on 10/2/26.
//

// Rasterises the macOS cursor artwork (SVG, some with masks and filters, so it goes through WebKit) into the trimmed
// PNGs and hotspot manifests SliceCore draws the native cursor styles from: Big Sur in Cursors/, Tahoe (macOS 26)
// in Cursors/Tahoe/, macOS 27 in Cursors/MacOS27/. Run again after changing the artwork:
//   swift scripts/make-cursors.swift
// Source names end in `__<x>-<y>`: the hotspot as a percentage of the canvas. A Big Sur canvas is 32 points across;
// the Tahoe artwork is cropped to each cursor, so each one is sized to cover as much as its Big Sur counterpart. The
// macOS 27 SVGs (made from a cape by scripts/cape-to-svg.swift) are sized in points, so they keep their own size.
import AppKit
import WebKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let bigSurSource = root.appendingPathComponent("inspo/assets/webadderallorg Recordly main src-assets_cursors_macos")
let tahoeSource = root.appendingPathComponent("inspo/assets/macos-26-cursor/webadderallorg Recordly main src-assets_cursors_tahoe")
let macOS27Source = root.appendingPathComponent("inspo/assets/macos-27-cursor")
let output = root.appendingPathComponent("Sources/SliceCore/Resources/Cursors")

let mapping: [String: String] = [
    "arrow": "pointer",
    "pointingHand": "pointinghand",
    "iBeam": "ibeamstroke",
    "iBeamVertical": "ibeamverticalstroke",
    "crosshair": "crosshair",
    "openHand": "openhand",
    "closedHand": "closedhand",
    "resizeLeftRight": "resizeleftright",
    "resizeLeft": "resizeleft",
    "resizeRight": "resizeright",
    "resizeUpDown": "resizeupdown",
    "resizeUp": "resizeup",
    "resizeDown": "resizedown",
    "resizeEastWest": "resizeeastwest",
    "resizeNorthSouth": "resizenorthsouth",
    "resizeNorth": "resizenorth",
    "resizeSouth": "resizesouth",
    "resizeEast": "resizeeast",
    "resizeWest": "resizewest",
    "resizeNorthEast": "resizenortheast",
    "resizeNorthWest": "resizenorthwest",
    "resizeSouthEast": "resizesoutheast",
    "resizeSouthWest": "resizesouthwest",
    "resizeNorthEastSouthWest": "resizenortheastsouthwest",
    "resizeNorthWestSouthEast": "resizenorthwestsoutheast",
    "operationNotAllowed": "notallowed",
    "dragCopy": "copy",
    "contextualMenu": "contextualmenu",
    "zoomIn": "zoomin",
    "zoomOut": "zoomout",
]

let macOS27Stems: [String: String] = ["iBeam": "ibeam", "iBeamVertical": "ibeamvertical"]

let canvasPoints: CGFloat = 32
let maxPixelsPerPoint: CGFloat = 32
let tahoeScaledLike: [String: (type: String, scale: CGFloat)] = ["contextualMenu": ("arrow", 0.6105)]

@MainActor
final class Rasteriser: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 800))
    let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 800, height: 800),
                          styleMask: .borderless, backing: .buffered, defer: false)
    private var loaded: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = self
        window.contentView = web
        window.orderBack(nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume()
        loaded = nil
    }

    func render(_ svg: Data, size: CGSize) async throws -> CGImage {
        let html = """
        <html><body style="margin:0;background:transparent">
        <img src="data:image/svg+xml;base64,\(svg.base64EncodedString())" style="display:block;width:\(size.width)px;height:\(size.height)px">
        </body></html>
        """
        let frame = NSRect(x: 0, y: 0, width: max(size.width, 800), height: max(size.height, 800))
        window.setContentSize(frame.size)
        web.frame = frame
        await withCheckedContinuation { c in
            loaded = c
            web.loadHTMLString(html, baseURL: nil)
        }
        try await Task.sleep(for: .milliseconds(150))
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: size)
        config.snapshotWidth = NSNumber(value: Double(size.width) / Double(window.backingScaleFactor))
        let image = try await web.takeSnapshot(configuration: config)
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }
}

func trimmed(_ image: CGImage, solid: Bool = false) -> CGRect? {
    let w = image.width, h = image.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0 ..< h {
        for x in 0 ..< w where p[y * w * 4 + x * 4 + 3] > (solid ? 160 : 0) {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= minX else { return nil }
    let box = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    return solid ? box : box.insetBy(dx: -4, dy: -4).intersection(CGRect(x: 0, y: 0, width: w, height: h))
}

func svgSize(_ text: String) -> CGSize? {
    func attribute(_ name: String) -> CGFloat? {
        guard let r = text.range(of: " \(name)=\"([0-9.]+)\"", options: .regularExpression) else { return nil }
        return Double(text[r].split(separator: "\"")[1]).map { CGFloat($0) }
    }
    guard let w = attribute("width"), let h = attribute("height") else { return nil }
    return CGSize(width: w, height: h)
}

struct Source {
    var file: String
    var data: Data
    var size: CGSize
    var hotspot: CGPoint
}

func source(_ stem: String, in dir: URL, files: [String]) -> Source? {
    guard let file = files.first(where: { $0.hasPrefix("\(stem)-") && $0.hasSuffix(".svg") }) else {
        print("missing \(stem) in \(dir.lastPathComponent)"); return nil
    }
    let suffix = file.dropLast(4).components(separatedBy: "__").last!.split(separator: "-").compactMap { Double($0) }
    guard suffix.count == 2, let data = try? Data(contentsOf: dir.appendingPathComponent(file)),
          let size = svgSize(String(decoding: data, as: UTF8.self)) else { print("unreadable \(file)"); return nil }
    return Source(file: file, data: data, size: size, hotspot: CGPoint(x: suffix[0] / 100, y: suffix[1] / 100))
}

enum Sizing {
    case pointsAcross(CGFloat)
    case bodyArea(CGFloat)
    case unitsPerPoint(CGFloat)
    case svgPoints
}

func svgDensity(_ s: Source) -> CGFloat {
    let text = String(decoding: s.data, as: UTF8.self)
    guard let r = text.range(of: "viewBox=\"[^\"]*\"", options: .regularExpression) else { return 1 }
    let numbers = text[r].dropFirst(9).dropLast().split(separator: " ").compactMap { Double($0) }
    return numbers.count == 4 ? CGFloat(numbers[2]) / s.size.width : 1
}

@MainActor
func write(_ type: String, from s: Source, to dir: URL, rasteriser: Rasteriser,
           sizing: Sizing) async throws -> (entry: [String: Double], bodyArea: CGFloat, unitsPerPoint: CGFloat)? {
    var cssSize = s.size
    if case .svgPoints = sizing {
        let density = min(svgDensity(s), maxPixelsPerPoint)
        cssSize = CGSize(width: (s.size.width * density).rounded(), height: (s.size.height * density).rounded())
    }
    var image = try await rasteriser.render(s.data, size: cssSize)
    func pixelsPerPoint(_ image: CGImage) -> CGFloat? {
        switch sizing {
        case let .pointsAcross(points): return CGFloat(image.width) / points
        case .svgPoints: return CGFloat(image.width) / s.size.width
        case let .unitsPerPoint(units): return CGFloat(image.width) / s.size.width * units
        case let .bodyArea(area):
            guard let body = trimmed(image, solid: true) else { return nil }
            return sqrt(body.width * body.height / area)
        }
    }
    guard var ppp = pixelsPerPoint(image) else { print("empty \(s.file)"); return nil }
    if case .pointsAcross = sizing {} else if ppp > maxPixelsPerPoint {
        cssSize = CGSize(width: (s.size.width * maxPixelsPerPoint / ppp).rounded(), height: (s.size.height * maxPixelsPerPoint / ppp).rounded())
        image = try await rasteriser.render(s.data, size: cssSize)
        guard let again = pixelsPerPoint(image) else { print("empty \(s.file)"); return nil }
        ppp = again
    }
    guard let box = trimmed(image), let body = trimmed(image, solid: true), let crop = image.cropping(to: box) else {
        print("empty \(s.file)"); return nil
    }
    let url = dir.appendingPathComponent("\(type).png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, crop, nil)
    CGImageDestinationFinalize(dest)
    let scale = CGFloat(image.width) / cssSize.width
    print("\(type) ← \(s.file)  \(crop.width)×\(crop.height) @ \(String(format: "%.1f", ppp))")
    return ([
        "hotspotX": (s.hotspot.x * cssSize.width * scale - box.minX).rounded(),
        "hotspotY": (s.hotspot.y * cssSize.height * scale - box.minY).rounded(),
        "pixelsPerPoint": Double(ppp),
    ], body.width * body.height / (ppp * ppp), ppp / (CGFloat(image.width) / s.size.width))
}

func writeManifest(_ manifest: [String: [String: Double]], to dir: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(to: dir.appendingPathComponent("cursors.json"))
}

@MainActor
func run() async throws {
    _ = NSApplication.shared
    let bigSurFiles = try FileManager.default.contentsOfDirectory(atPath: bigSurSource.path)
    let tahoeFiles = try FileManager.default.contentsOfDirectory(atPath: tahoeSource.path)
    let macOS27Files = try FileManager.default.contentsOfDirectory(atPath: macOS27Source.path)
    let tahoeOutput = output.appendingPathComponent("Tahoe")
    let macOS27Output = output.appendingPathComponent("MacOS27")
    try? FileManager.default.removeItem(at: output)
    try FileManager.default.createDirectory(at: tahoeOutput, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: macOS27Output, withIntermediateDirectories: true)
    let rasteriser = Rasteriser()
    var bigSur: [String: [String: Double]] = [:], tahoe: [String: [String: Double]] = [:], macOS27: [String: [String: Double]] = [:]
    var tahoeUnits: [String: CGFloat] = [:]
    for (type, stem) in mapping.sorted(by: { $0.key < $1.key }) {
        guard let s = source(stem, in: bigSurSource, files: bigSurFiles),
              let made = try await write(type, from: s, to: output, rasteriser: rasteriser, sizing: .pointsAcross(canvasPoints))
        else { continue }
        bigSur[type] = made.entry
        if let m = source(macOS27Stems[type] ?? stem, in: macOS27Source, files: macOS27Files),
           let sized = try await write(type, from: m, to: macOS27Output, rasteriser: rasteriser, sizing: .svgPoints) {
            macOS27[type] = sized.entry
        }
        var sizing = Sizing.bodyArea(made.bodyArea)
        if let like = tahoeScaledLike[type], let units = tahoeUnits[like.type] { sizing = .unitsPerPoint(units * like.scale) }
        guard let t = source(stem, in: tahoeSource, files: tahoeFiles),
              let sized = try await write(type, from: t, to: tahoeOutput, rasteriser: rasteriser, sizing: sizing)
        else { continue }
        tahoe[type] = sized.entry
        tahoeUnits[type] = sized.unitsPerPoint
    }
    try writeManifest(bigSur, to: output)
    try writeManifest(tahoe, to: tahoeOutput)
    try writeManifest(macOS27, to: macOS27Output)
}

Task { @MainActor in
    do { try await run() } catch { print("error: \(error)") }
    exit(0)
}
RunLoop.main.run()
