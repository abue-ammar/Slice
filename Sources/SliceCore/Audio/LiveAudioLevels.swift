//
//  LiveAudioLevels.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/15/26.
//

import Accelerate
import AVFoundation

/// A take's audio measured as it's written: its peak, to spot a silent mic, and its loudness every 20 ms, to find
/// speech. The same numbers `AudioCheck` and `AudioAnalysis.speech(in:)` get by decoding the file afterwards.
public final class LiveAudioLevels: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Float = 0
    private var levels: [Double] = []
    private var energy = 0.0
    private var fill = 0
    private var size = 0
    private var measured = false

    static let frameDuration = 0.02

    public init() {}

    public func add(_ sample: CMSampleBuffer) {
        guard let read = Self.read(sample) else { return }
        lock.withLock {
            measured = true
            if size == 0 { size = max(Int(read.rate * Self.frameDuration), 1) }
            peak = max(peak, read.peak)
            read.mono.withUnsafeBufferPointer { mono in
                guard let base = mono.baseAddress else { return }
                var i = 0
                while i < mono.count {
                    let n = min(size - fill, mono.count - i)
                    var sum: Float = 0
                    vDSP_svesq(base + i, 1, &sum, vDSP_Length(n))
                    energy += Double(sum)
                    fill += n
                    i += n
                    if fill == size {
                        levels.append(10 * log10(max(energy / Double(size), 1e-12)))
                        energy = 0
                        fill = 0
                    }
                }
            }
        }
    }

    /// Nil until some audio has been written.
    public var isSilent: Bool? { lock.withLock { measured ? peak < 0.001 : nil } }

    public var speech: [TimeSpan] {
        let levels = lock.withLock { self.levels }
        return AudioAnalysis.speech(levels: levels, frameDuration: Self.frameDuration)
    }

    static func read(_ sample: CMSampleBuffer) -> (mono: [Float], peak: Float, rate: Double)? {
        guard let desc = CMSampleBufferGetFormatDescription(sample),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc),
              asbd.pointee.mFormatID == kAudioFormatLinearPCM else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: desc)
        let frames = Int(CMSampleBufferGetNumSamples(sample))
        let channels = Int(format.channelCount)
        guard frames > 0, channels > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
        else { return nil }
        buf.frameLength = AVAudioFrameCount(frames)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames),
                                                           into: buf.mutableAudioBufferList) == noErr else { return nil }
        let interleaved = format.isInterleaved
        let value: (Int, Int) -> Float
        if let f = buf.floatChannelData {
            value = { c, i in interleaved ? f[0][i * channels + c] : f[c][i] }
        } else if let s = buf.int16ChannelData {
            value = { c, i in Float(interleaved ? s[0][i * channels + c] : s[c][i]) / 32768 }
        } else if let s = buf.int32ChannelData {
            value = { c, i in Float(interleaved ? s[0][i * channels + c] : s[c][i]) / 2_147_483_648 }
        } else {
            return nil
        }
        var mono = [Float](repeating: 0, count: frames)
        var peak: Float = 0
        let scale = 1 / Float(channels)
        for i in 0 ..< frames {
            var sum: Float = 0
            for c in 0 ..< channels {
                let v = value(c, i)
                sum += v
                peak = max(peak, abs(v))
            }
            mono[i] = channels == 1 ? sum : sum * scale
        }
        return (mono, peak, format.sampleRate)
    }
}
