//
//  CameraGlitches.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/2/26.
//

import AVFoundation
import Foundation

public struct TimeSpan: Codable, Equatable, Sendable {
    public var start: Double
    public var end: Double
    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    public func contains(_ t: Double) -> Bool { t >= start && t < end }
}

public enum CameraGlitchDetector {
    public static func scan(_ url: URL) async throws -> [TimeSpan] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        out.alwaysCopiesSampleData = false
        reader.add(out)
        reader.startReading()
        // Only the last three frames are kept: every thumbnail of an hours-long take would be most of a gigabyte.
        var window: [(t: Double, thumb: [Float])] = []
        var spans: [TimeSpan] = []
        while let sb = out.copyNextSampleBuffer() {
            guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
            window.append((CMSampleBufferGetPresentationTimeStamp(sb).seconds, thumbnail(pb)))
            if window.count > 3 { window.removeFirst() }
            if window.count == 3, isGlitch(previous: window[0].thumb, frame: window[1].thumb, next: window[2].thumb) {
                spans.append(TimeSpan(start: window[1].t, end: window[2].t))
            }
        }
        return spans
    }

    public static func thumbnail(_ pb: CVPixelBuffer) -> [Float] {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), bpr = CVPixelBufferGetBytesPerRow(pb)
        let p = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        var out = [Float](repeating: 0, count: 32 * 18)
        for gy in 0 ..< 18 {
            for gx in 0 ..< 32 {
                let x = min(w - 1, (gx * w + w / 64) / 32), y = min(h - 1, (gy * h + h / 36) / 18)
                let i = y * bpr + x * 4
                out[gy * 32 + gx] = 0.11 * Float(p[i]) + 0.59 * Float(p[i + 1]) + 0.3 * Float(p[i + 2])
            }
        }
        return out
    }

    static func difference(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) } / Float(a.count)
    }

    static func glitches(in frames: [(t: Double, thumb: [Float])]) -> [TimeSpan] {
        guard frames.count >= 3 else { return [] }
        var out: [TimeSpan] = []
        for i in 1 ..< frames.count - 1 where isGlitch(previous: frames[i - 1].thumb, frame: frames[i].thumb, next: frames[i + 1].thumb) {
            out.append(TimeSpan(start: frames[i].t, end: frames[i + 1].t))
        }
        return out
    }

    public static func isGlitch(previous: [Float], frame: [Float], next: [Float]) -> Bool {
        let before = difference(previous, frame), after = difference(frame, next), across = difference(previous, next)
        return before > 10 && after > 10 && min(before, after) > 3 * max(across, 2)
    }
}
