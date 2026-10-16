//
//  ScreenChange.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/10/26.
//

import AVFoundation
import CoreGraphics
import Foundation

/// How the screen changed around a click: the whole page, or one area near the pointer (a menu, a field).
public enum ScreenChange {
    public struct Result: Codable, Equatable, Sendable {
        public var fraction: Double
        public var local: CGRect?
    }

    /// One click's measurement, kept beside a take while it records so smart zoom needn't decode the video again.
    public struct Entry: Codable, Equatable, Sendable {
        public var t: Double
        public var x: Double
        public var y: Double
        public var result: Result
    }

    static let columns = 96, rows = 60
    static let threshold = 14
    static let before = 0.12, after = 0.7

    // MARK: - From a finished video

    static func measure(video: URL, clicks: [(t: Double, point: CGPoint)], duration: Double,
                        progress: @escaping @Sendable (Double) -> Void) async -> [Result?] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.maximumSize = CGSize(width: 384, height: 384)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 20)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 20)
        let last = max(duration - 0.02, 0)
        var times: [Double] = []
        for c in clicks { times += [max(c.t - before, 0), min(c.t + after, last)] }
        func key(_ t: Double) -> Int { Int((t * 1000).rounded()) }
        var grids: [Int: [UInt8]] = [:]
        var done = 0
        for await result in generator.images(for: times.map { CMTime(seconds: $0, preferredTimescale: 600) }) {
            if Task.isCancelled { break }
            if let image = try? result.image, let grid = luma(image) { grids[key(result.requestedTime.seconds)] = grid }
            done += 1
            progress(Double(done) / Double(max(times.count, 1)))
        }
        return clicks.enumerated().map { i, c in
            guard let a = grids[key(times[2 * i])], let b = grids[key(times[2 * i + 1])] else { return nil }
            return compare(a, b, at: c.point)
        }
    }

    static func luma(_ image: CGImage) -> [UInt8]? {
        var data = [UInt8](repeating: 0, count: columns * rows)
        let drawn = data.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: columns, height: rows, bitsPerComponent: 8,
                                      bytesPerRow: columns, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            return true
        }
        return drawn ? data : nil
    }

    // MARK: - From live frames

    /// The same grid as `luma(_:)`, straight from a BGRA capture frame: each cell averages a 4×4 spread of pixels, so
    /// it costs a few thousand reads however large the screen is.
    static func luma(_ buffer: CVPixelBuffer) -> [UInt8]? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer), row = CVPixelBufferGetBytesPerRow(buffer)
        guard w >= columns, h >= rows, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let p = UnsafePointer(base.assumingMemoryBound(to: UInt8.self))
        let spread = 4
        let xs = (0 ..< columns * spread).map { min(($0 * 2 + 1) * w / (columns * spread * 2), w - 1) * 4 }
        let ys = (0 ..< rows * spread).map { min(($0 * 2 + 1) * h / (rows * spread * 2), h - 1) * row }
        var sums = [Int](repeating: 0, count: columns * rows)
        sums.withUnsafeMutableBufferPointer { sums in
            xs.withUnsafeBufferPointer { xs in
                for (j, y) in ys.enumerated() {
                    let line = p + y, cells = (j / spread) * columns
                    for (i, x) in xs.enumerated() {
                        let px = line + x
                        sums[cells + i / spread] += 29 * Int(px[0]) + 150 * Int(px[1]) + 77 * Int(px[2])
                    }
                }
            }
        }
        return sums.map { UInt8(min($0 / (spread * spread * 256), 255)) }
    }

    // MARK: - Cache

    static func cached(at url: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    static func lookup(_ entries: [Entry], t: Double, point: CGPoint) -> Result? {
        entries.first { abs($0.t - t) < 0.002 && abs($0.x - point.x) < 1e-4 && abs($0.y - point.y) < 1e-4 }?.result
    }

    // MARK: - Comparing

    static func compare(_ a: [UInt8], _ b: [UInt8], at point: CGPoint) -> Result {
        let changed = zip(a, b).map { abs(Int($0) - Int($1)) > threshold }
        let total = changed.filter { $0 }.count
        let fraction = Double(total) / Double(changed.count)
        guard total > 0, fraction <= 0.4 else { return Result(fraction: fraction, local: nil) }
        var seen = [Bool](repeating: false, count: changed.count)
        var regions: [(box: CGRect, cells: Int)] = []
        for start in changed.indices where changed[start] && !seen[start] {
            var stack = [start]
            seen[start] = true
            var minX = columns, minY = rows, maxX = 0, maxY = 0, cells = 0
            while let i = stack.popLast() {
                let x = i % columns, y = i / columns
                cells += 1
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where nx >= 0 && ny >= 0 && nx < columns && ny < rows {
                    let j = ny * columns + nx
                    if changed[j] && !seen[j] {
                        seen[j] = true
                        stack.append(j)
                    }
                }
            }
            let box = CGRect(x: Double(minX) / Double(columns), y: Double(minY) / Double(rows),
                             width: Double(maxX - minX + 1) / Double(columns), height: Double(maxY - minY + 1) / Double(rows))
            regions.append((box, cells))
        }
        func distance(_ r: CGRect) -> Double {
            hypot(max(r.minX - point.x, 0, point.x - r.maxX), max(r.minY - point.y, 0, point.y - r.maxY))
        }
        guard let nearest = regions.filter({ $0.cells > 2 || distance($0.box) == 0 }).min(by: { distance($0.box) < distance($1.box) }),
              distance(nearest.box) < 0.3 else { return Result(fraction: fraction, local: nil) }
        var area = nearest.box
        for r in regions where r.box.intersects(area.insetBy(dx: -0.03, dy: -0.03)) { area = area.union(r.box) }
        return Result(fraction: fraction, local: area.width * area.height <= 0.25 ? area : nil)
    }
}
