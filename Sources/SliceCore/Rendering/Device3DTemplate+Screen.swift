//
//  Device3DTemplate+Screen.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/21/26.
//

import AppKit
import ImageIO
import SceneKit
import simd

extension Device3DTemplate {
    /// Where the screen lies on a display mesh that also carries its bezel (a laptop's lid), found from the model's own
    /// picture: the display's texture shows the screen as bright among black (bezel, notch, rounded corners), and its
    /// texture coordinates say where each part of the picture falls on the mesh. Returns the screen's rectangle on
    /// the mesh (fractions of it, top-left origin, as `mapDisplay` lays it) and a mask of exactly where it shows.
    static func screenRegion(of display: SCNNode, in root: SCNNode) -> (rect: CGRect, mask: CGImage)? {
        guard let geometry = display.geometry, let points = points(of: display, in: root), let uv = texcoords(of: geometry),
              uv.count == points.count, points.count >= 3,
              let atlas = picture(geometry.firstMaterial?.diffuse.contents) ?? picture(geometry.firstMaterial?.emission.contents),
              let pixels = rgba(atlas) else { return nil }
        let lo = points.reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude)) { simd_min($0, $1) }
        let hi = points.reduce(SIMD3<Float>(repeating: -.greatestFiniteMagnitude)) { simd_max($0, $1) }
        let w = Double(hi.x - lo.x), h = Double(hi.y - lo.y)
        guard w > 1e-6, h > 1e-6 else { return nil }
        // Only the face of the display: a slab's back and edges are mapped to other parts of the picture.
        let onFace = points.map { $0.z >= hi.z - max((hi.z - lo.z) * 0.3, 1e-6) }
        let triangles = triangleIndices(of: geometry).filter { t in t.allSatisfy { $0 < points.count && onFace[$0] } }
        guard !triangles.isEmpty else { return nil }

        let columns = 640, rows = max(Int((640 * h / w).rounded()), 16)
        // Each triangle of the face drawn into a raster laid like the display, sampling the picture through the
        // triangle's own texture coordinates (a face can be mapped in several pieces, each its own way round).
        func raster(flipped: Bool) -> [Bool] {
            var lit = [Bool](repeating: false, count: columns * rows)
            for t in triangles {
                let p = t.map { SIMD2<Double>((Double(points[$0].x) - Double(lo.x)) / w * Double(columns),
                                              (Double(hi.y) - Double(points[$0].y)) / h * Double(rows)) }
                let q = t.map { SIMD2<Double>(Double(uv[$0].x), flipped ? 1 - Double(uv[$0].y) : Double(uv[$0].y)) }
                let area = (p[1].x - p[0].x) * (p[2].y - p[0].y) - (p[2].x - p[0].x) * (p[1].y - p[0].y)
                guard abs(area) > 1e-9 else { continue }
                let x0 = max(Int(min(p[0].x, p[1].x, p[2].x)), 0), x1 = min(Int(max(p[0].x, p[1].x, p[2].x)) + 1, columns - 1)
                let y0 = max(Int(min(p[0].y, p[1].y, p[2].y)), 0), y1 = min(Int(max(p[0].y, p[1].y, p[2].y)) + 1, rows - 1)
                guard x0 <= x1, y0 <= y1 else { continue }
                for row in y0 ... y1 {
                    for column in x0 ... x1 {
                        let c = SIMD2<Double>(Double(column) + 0.5, Double(row) + 0.5)
                        let b1 = ((c.x - p[0].x) * (p[2].y - p[0].y) - (p[2].x - p[0].x) * (c.y - p[0].y)) / area
                        let b2 = ((p[1].x - p[0].x) * (c.y - p[0].y) - (c.x - p[0].x) * (p[1].y - p[0].y)) / area
                        let b0 = 1 - b1 - b2
                        guard b0 >= -1e-6, b1 >= -1e-6, b2 >= -1e-6 else { continue }
                        let at = q[0] * b0 + q[1] * b1 + q[2] * b2
                        let px = min(max(Int(at.x * Double(pixels.width)), 0), pixels.width - 1)
                        let py = min(max(Int(at.y * Double(pixels.height)), 0), pixels.height - 1)
                        let o = (py * pixels.width + px) * 4
                        let level = (Int(pixels.data[o]) + Int(pixels.data[o + 1]) + Int(pixels.data[o + 2])) / 3
                        lit[row * columns + column] = level > 16
                    }
                }
            }
            return lit
        }
        // A notch hangs from the top of the screen; if it shows at the bottom the picture's rows run the other way.
        var mask = screen(raster(flipped: false), columns: columns, rows: rows)
        if let found = mask, found.notch < 0 { mask = screen(raster(flipped: true), columns: columns, rows: rows) }
        guard let (shown, box, _) = mask else { return nil }

        var bytes = shown.map { $0 ? UInt8(255) : 0 }
        guard let provider = CGDataProvider(data: Data(bytes: &bytes, count: bytes.count) as CFData),
              let image = CGImage(width: columns, height: rows, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: columns,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                                  decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        let rect = CGRect(x: CGFloat(box.minX) / CGFloat(columns), y: CGFloat(box.minY) / CGFloat(rows),
                          width: CGFloat(box.width) / CGFloat(columns), height: CGFloat(box.height) / CGFloat(rows))
        return (rect, image)
    }

    /// The screen in a raster of lit pixels: everything within the lit area's bounds except the dark that reaches in
    /// from its edges (corners, a notch), so dark parts of the picture itself don't punch holes in it. Also says
    /// where a notch is: positive at the top, negative at the bottom.
    private static func screen(_ lit: [Bool], columns: Int, rows: Int) -> (mask: [Bool], box: CGRect, notch: Int)? {
        var minX = columns, minY = rows, maxX = -1, maxY = -1
        for row in 0 ..< rows { for column in 0 ..< columns where lit[row * columns + column] {
            minX = min(minX, column); maxX = max(maxX, column); minY = min(minY, row); maxY = max(maxY, row)
        } }
        guard maxX > minX, maxY > minY else { return nil }
        let bw = maxX - minX + 1, bh = maxY - minY + 1
        // Too small or the whole mesh: not a screen set in a bezel.
        guard Double(bw * bh) > Double(columns * rows) * 0.3, Double(bw * bh) < Double(columns * rows) * 0.985 else { return nil }
        var outside = [Bool](repeating: false, count: columns * rows)
        var stack: [(Int, Int)] = []
        for column in minX ... maxX { stack += [(column, minY), (column, maxY)] }
        for row in minY ... maxY { stack += [(minX, row), (maxX, row)] }
        while let (column, row) = stack.popLast() {
            guard (minX ... maxX).contains(column), (minY ... maxY).contains(row) else { continue }
            let i = row * columns + column
            guard !lit[i], !outside[i] else { continue }
            outside[i] = true
            stack += [(column + 1, row), (column - 1, row), (column, row + 1), (column, row - 1)]
        }
        var mask = [Bool](repeating: false, count: columns * rows)
        var top = 0, bottom = 0
        let middle = (minX + bw * 2 / 5) ... (minX + bw * 3 / 5), band = max(bh / 12, 1)
        for row in minY ... maxY {
            for column in minX ... maxX {
                let i = row * columns + column
                mask[i] = !outside[i]
                if outside[i], middle.contains(column) {
                    if row < minY + band { top += 1 } else if row > maxY - band { bottom += 1 }
                }
            }
        }
        guard Double(mask.filter { $0 }.count) > Double(bw * bh) * 0.85 else { return nil }
        return (mask, CGRect(x: minX, y: minY, width: bw, height: bh), top - bottom)
    }

    /// The geometry's triangles, as vertex indices.
    private static func triangleIndices(of geometry: SCNGeometry) -> [[Int]] {
        geometry.elements.filter { $0.primitiveType == .triangles }.flatMap { triangles(of: $0) }
    }

    /// A triangle element's triangles, as vertex indices.
    static func triangles(of element: SCNGeometryElement) -> [[Int]] {
        var out: [[Int]] = []
        let size = element.bytesPerIndex
        element.data.withUnsafeBytes { raw in
            func index(_ i: Int) -> Int {
                switch size {
                case 1: Int(raw.load(fromByteOffset: i, as: UInt8.self))
                case 2: Int(raw.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self))
                default: Int(raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self))
                }
            }
            for t in 0 ..< element.primitiveCount where (t * 3 + 2) * size < raw.count {
                out.append([index(t * 3), index(t * 3 + 1), index(t * 3 + 2)])
            }
        }
        return out
    }

    private static func texcoords(of geometry: SCNGeometry) -> [SIMD2<Float>]? {
        guard let source = geometry.sources(for: .texcoord).first, source.usesFloatComponents, source.bytesPerComponent == 4,
              source.componentsPerVector >= 2 else { return nil }
        var out: [SIMD2<Float>] = []
        out.reserveCapacity(source.vectorCount)
        source.data.withUnsafeBytes { raw in
            for i in 0 ..< source.vectorCount {
                let o = source.dataOffset + i * source.dataStride
                guard o + 8 <= raw.count else { break }
                out.append(SIMD2(raw.loadUnaligned(fromByteOffset: o, as: Float.self), raw.loadUnaligned(fromByteOffset: o + 4, as: Float.self)))
            }
        }
        return out
    }

    /// A material's picture: an image, or a file (inside a USDZ, a URL naming the byte range it occupies).
    private static func picture(_ contents: Any?) -> CGImage? {
        if let image = contents as? NSImage { return image.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        guard let url = contents as? URL else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let source: CGImageSource?
        if let offset = items.first(where: { $0.name == "offset" })?.value.flatMap(UInt64.init),
           let size = items.first(where: { $0.name == "size" })?.value.flatMap(Int.init),
           let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: url.path)) {
            defer { try? handle.close() }
            try? handle.seek(toOffset: offset)
            guard let data = try? handle.read(upToCount: size) else { return nil }
            source = CGImageSourceCreateWithData(data as CFData, nil)
        } else {
            source = CGImageSourceCreateWithURL(url as CFURL, nil)
        }
        return source.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    private static func rgba(_ image: CGImage) -> (data: [UInt8], width: Int, height: Int)? {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? (data, w, h) : nil
    }
}
