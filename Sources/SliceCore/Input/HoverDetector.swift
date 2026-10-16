//
//  HoverDetector.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/11/26.
//

import AVFoundation
import Foundation

public enum HoverDetector {
    static let radius = 5.0
    static let threshold = 10
    static let coverage = 0.4
    static let globalLimit = 0.3

    public static func scan(video url: URL, log: CursorLog, pointSize: CGSize) async throws -> [Double] {
        let samples = log.samples.filter { $0.t.isFinite && $0.x.isFinite && $0.y.isFinite }.sorted { $0.t < $1.t }
        guard samples.count > 1, pointSize.width > 0, pointSize.height > 0 else { return [] }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        out.alwaysCopiesSampleData = false
        reader.add(out)
        guard reader.startReading() else { return [] }

        var moments: [Double] = []
        var previous: (t: Double, buffer: CVPixelBuffer, sample: CMSampleBuffer)?
        while let sb = out.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
            let t = CMSampleBufferGetPresentationTimeStamp(sb).seconds
            if let prev = previous, t.isFinite,
               isHover(from: prev.buffer, to: pb, pointer: (position(in: samples, at: prev.t), position(in: samples, at: t)),
                       pointSize: pointSize) {
                if t - (moments.last ?? -.infinity) > 1.0 / 30 { moments.append(t) }
            }
            // The buffer stays valid while its sample buffer is retained.
            previous = (t, pb, sb)
        }
        return moments
    }

    static func isHover(from a: CVPixelBuffer, to b: CVPixelBuffer, pointer: (CGPoint, CGPoint), pointSize: CGSize) -> Bool {
        let w = CVPixelBufferGetWidth(b), h = CVPixelBufferGetHeight(b)
        guard CVPixelBufferGetWidth(a) == w, CVPixelBufferGetHeight(a) == h, w > 0, h > 0 else { return false }
        guard moved(pointer, pointSize: pointSize) else { return false }
        CVPixelBufferLockBaseAddress(a, .readOnly)
        CVPixelBufferLockBaseAddress(b, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(a, .readOnly)
            CVPixelBufferUnlockBaseAddress(b, .readOnly)
        }
        guard let baseA = CVPixelBufferGetBaseAddress(a), let baseB = CVPixelBufferGetBaseAddress(b) else { return false }
        let pa = baseA.assumingMemoryBound(to: UInt8.self), pb = baseB.assumingMemoryBound(to: UInt8.self)
        let rowA = CVPixelBufferGetBytesPerRow(a), rowB = CVPixelBufferGetBytesPerRow(b)
        func changed(_ x: Int, _ y: Int) -> Bool {
            let i = y * rowA + x * 4, j = y * rowB + x * 4
            let la = 29 * Int(pa[i]) + 150 * Int(pa[i + 1]) + 77 * Int(pa[i + 2])
            let lb = 29 * Int(pb[j]) + 150 * Int(pb[j + 1]) + 77 * Int(pb[j + 2])
            return abs(la - lb) > threshold << 8
        }
        return isHover(width: w, height: h, pointer: pointer, pointSize: pointSize, changed: changed,
                       global: { gx, gy in changed((2 * gx + 1) * w / 64, (2 * gy + 1) * h / 36) })
    }

    static func moved(_ pointer: (CGPoint, CGPoint), pointSize: CGSize) -> Bool {
        hypot(Double(pointer.1.x - pointer.0.x) * pointSize.width, Double(pointer.1.y - pointer.0.y) * pointSize.height) > 0.5
    }

    /// The test itself, reading pixels through `changed` (nil where a pixel isn't known) and the 32×18 overview through
    /// `global`, so whole frames from a file and the patches kept while recording go through the same rules.
    static func isHover(width w: Int, height h: Int, pointer: (CGPoint, CGPoint), pointSize: CGSize,
                        changed: (Int, Int) -> Bool?, global: (Int, Int) -> Bool) -> Bool {
        guard moved(pointer, pointSize: pointSize) else { return false }
        let r = circleRadius(width: w, pointSize: pointSize)
        let step = max(r / 5, 1)
        var hit = false
        for p in [pointer.0, pointer.1] {
            let cx = Double(p.x) * Double(w), cy = Double(p.y) * Double(h)
            guard cx >= 0, cy >= 0, cx < Double(w), cy < Double(h) else { continue }
            var total = 0, diff = 0
            var dy = -r
            while dy <= r {
                var dx = -r
                while dx <= r {
                    if dx * dx + dy * dy <= r * r {
                        let x = Int(cx + dx), y = Int(cy + dy)
                        if x >= 0, y >= 0, x < w, y < h, let c = changed(x, y) {
                            total += 1
                            if c { diff += 1 }
                        }
                    }
                    dx += step
                }
                dy += step
            }
            if total > 0, Double(diff) >= coverage * Double(total) { hit = true }
        }
        guard hit else { return false }

        var count = 0
        for gy in 0 ..< 18 {
            for gx in 0 ..< 32 where global(gx, gy) { count += 1 }
        }
        return Double(count) < globalLimit * 32 * 18
    }

    static func circleRadius(width w: Int, pointSize: CGSize) -> Double {
        max(radius * Double(w) / pointSize.width, 2)
    }

    static func position(in samples: [CursorLog.Sample], at t: Double) -> CGPoint {
        var lo = 0, hi = samples.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if samples[mid].t <= t { lo = mid } else { hi = mid - 1 }
        }
        let a = samples[lo]
        guard lo + 1 < samples.count, a.t <= t else { return CGPoint(x: a.x, y: a.y) }
        let b = samples[lo + 1]
        let f = (t - a.t) / max(b.t - a.t, 1e-6)
        return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }
}
