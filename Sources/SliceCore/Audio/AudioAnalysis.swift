//
//  AudioAnalysis.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/13/26.
//

import Accelerate
import AVFoundation
import Foundation

public struct AudioSummary: Sendable, Equatable {
    public var duration: Double
    public var levels: [Float]
    public var maxLevel: Float
    public var bucketsPerSecond: Double
    public var loudness: Double

    public func level(at t: Double) -> Float {
        guard !levels.isEmpty, t >= 0, maxLevel > 0 else { return 0 }
        return levels[min(Int(t * bucketsPerSecond), levels.count - 1)] / maxLevel
    }
}

public enum AudioAnalysis {
    public static func summarize(_ url: URL, bucketsPerSecond: Double = 40) -> AudioSummary? {
        var levels: [Float] = []
        var blocks: [Double] = []
        var bucketEnergy: Float = 0, bucketFill = 0
        var blockEnergy = 0.0, blockFill = 0
        var bucketSize = 0, blockSize = 0
        guard let duration = read(url, prepare: { rate in
            bucketSize = max(Int(rate / bucketsPerSecond), 1)
            blockSize = max(Int(rate * 0.4), 1)
        }, frames: { mono, count in
            var i = 0
            while i < count {
                let n = min(bucketSize - bucketFill, count - i)
                bucketEnergy += sumOfSquares(mono + i, n)
                bucketFill += n
                i += n
                if bucketFill == bucketSize {
                    levels.append(min(sqrt(bucketEnergy / Float(bucketSize)), 1))
                    bucketEnergy = 0
                    bucketFill = 0
                }
            }
            i = 0
            while i < count {
                let n = min(blockSize - blockFill, count - i)
                blockEnergy += Double(sumOfSquares(mono + i, n))
                blockFill += n
                i += n
                if blockFill == blockSize {
                    blocks.append(blockEnergy / Double(blockSize))
                    blockEnergy = 0
                    blockFill = 0
                }
            }
        }) else { return nil }
        if bucketFill > 0 { levels.append(min(sqrt(bucketEnergy / Float(bucketFill)), 1)) }
        let loud = blocks.filter { $0 > 1e-5 }
        let mean = loud.isEmpty ? 0 : loud.reduce(0, +) / Double(loud.count)
        return AudioSummary(duration: duration, levels: levels, maxLevel: levels.max() ?? 0, bucketsPerSecond: bucketsPerSecond,
                            loudness: mean > 0 ? 10 * log10(mean) : -100)
    }

    public static func duration(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0, file.length > 0 else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    private static func sumOfSquares(_ p: UnsafePointer<Float>, _ n: Int) -> Float {
        guard n > 0 else { return 0 }
        var sum: Float = 0
        vDSP_svesq(p, 1, &sum, vDSP_Length(n))
        return sum
    }

    public static func speech(in url: URL) -> [TimeSpan] {
        let frame = 0.02
        guard let levels = levels(in: url, frame: frame) else { return [] }
        return speech(levels: levels, frameDuration: frame)
    }

    /// Loudness in dB for each `frame` seconds of the file, mixed to mono.
    public static func levels(in url: URL, frame: Double) -> [Double]? {
        var levels: [Double] = []
        var energy = 0.0, fill = 0, size = 0
        guard read(url, prepare: { size = max(Int($0 * frame), 1) }, frames: { mono, count in
            var i = 0
            while i < count {
                let n = min(size - fill, count - i)
                energy += Double(sumOfSquares(mono + i, n))
                fill += n
                i += n
                if fill == size {
                    levels.append(10 * log10(max(energy / Double(size), 1e-12)))
                    energy = 0
                    fill = 0
                }
            }
        }) != nil else { return nil }
        return levels
    }

    /// The level above which a frame counts as speech, set between the room's noise floor and the loud parts;
    /// nil when the recording has no clear speech to tell apart.
    public static func speechThreshold(levels: [Double]) -> Double? {
        let audible = levels.filter { $0 > -90 }.sorted()
        guard audible.count >= 10 else { return nil }
        func percentile(_ p: Double) -> Double { audible[min(Int(Double(audible.count - 1) * p), audible.count - 1)] }
        let floor = percentile(0.15), loud = percentile(0.95)
        guard loud - floor > 10, loud > -50 else { return nil }
        return max(floor + max(8, (loud - floor) * 0.35), -55)
    }

    public static func speech(levels: [Double], frameDuration: Double) -> [TimeSpan] {
        guard let threshold = speechThreshold(levels: levels) else { return [] }

        var spans: [TimeSpan] = []
        var runStart: Int?
        for (i, l) in levels.enumerated() {
            if l > threshold {
                if runStart == nil { runStart = i }
            } else if let s = runStart {
                spans.append(TimeSpan(start: Double(s) * frameDuration, end: Double(i) * frameDuration))
                runStart = nil
            }
        }
        if let s = runStart { spans.append(TimeSpan(start: Double(s) * frameDuration, end: Double(levels.count) * frameDuration)) }
        var merged: [TimeSpan] = []
        for s in spans {
            if let last = merged.last, s.start - last.end < 0.3 { merged[merged.count - 1].end = s.end } else { merged.append(s) }
        }
        return merged.filter { $0.end - $0.start >= 0.15 }
    }

    private static func read(_ url: URL, prepare: (Double) -> Void,
                             frames: (UnsafePointer<Float>, Int) -> Void) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let channels = Int(format.channelCount)
        let chunk: AVAudioFrameCount = 65536
        guard channels > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk),
              let data = buf.floatChannelData else { return nil }
        prepare(format.sampleRate)
        var mono = [Float](repeating: 0, count: Int(chunk))
        var scale = 1 / Float(channels)
        while file.framePosition < file.length {
            guard (try? file.read(into: buf, frameCount: chunk)) != nil, buf.frameLength > 0 else { break }
            let n = Int(buf.frameLength)
            mono.withUnsafeMutableBufferPointer { out in
                let m = out.baseAddress!, len = vDSP_Length(n)
                if channels == 1 {
                    m.update(from: data[0], count: n)
                } else {
                    vDSP_vadd(data[0], 1, data[1], 1, m, 1, len)
                    for c in 2 ..< channels { vDSP_vadd(m, 1, data[c], 1, m, 1, len) }
                    vDSP_vsmul(m, 1, &scale, m, 1, len)
                }
            }
            mono.withUnsafeBufferPointer { frames($0.baseAddress!, n) }
        }
        return Double(file.length) / format.sampleRate
    }
}

public struct PeakLimiter {
    public let ceiling: Float
    private let recovery: Float
    private var gain: Float = 1

    public init(sampleRate: Double = 48000, ceiling: Float = 0.89, release: Double = 0.12) {
        self.ceiling = ceiling
        recovery = Float(1 - exp(-1 / (release * sampleRate)))
    }

    public mutating func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channels: Int) {
        guard channels > 0 else { return }
        for f in 0 ..< frames {
            let base = f * channels
            var peak: Float = 0
            for c in 0 ..< channels { peak = max(peak, abs(samples[base + c])) }
            let target: Float = peak > ceiling ? ceiling / peak : 1
            gain = target < gain ? target : gain + (target - gain) * recovery
            if gain < 0.99999 { for c in 0 ..< channels { samples[base + c] *= gain } }
        }
    }
}
