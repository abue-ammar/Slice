//
//  AudioFiles.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/3/26.
//

import AVFoundation

final class MonoReader {
    let length: Int
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let origin: CMTime
    private var pending: [Float] = []
    private var pendingStart = 0
    private var pendingOffset = 0
    private var position = 0
    private var finished = false
    private var started = false

    init(url: URL) async throws {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw VoiceEnhancer.Failure.noAudio }
        let range = try await track.load(.timeRange)
        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: VoiceEnhancer.rate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        origin = range.start
        length = max(Int((range.duration.seconds * Double(VoiceEnhancer.rate)).rounded()), 0)
        guard reader.startReading() else {
            throw VoiceEnhancer.Failure.unreadable(reader.error?.localizedDescription ?? url.lastPathComponent)
        }
    }

    deinit { reader.cancelReading() }

    func read(_ out: UnsafeMutablePointer<Float>, count: Int) -> Int {
        var filled = 0
        while filled < count, position < length {
            if pendingOffset >= pending.count {
                guard nextBuffer() else { break }
                continue
            }
            let next = pendingStart + pendingOffset
            if next > position {
                let n = min(next - position, count - filled, length - position)
                (out + filled).initialize(repeating: 0, count: n)
                filled += n
                position += n
            } else if next < position {
                pendingOffset += min(position - next, pending.count - pendingOffset)
            } else {
                let n = min(pending.count - pendingOffset, count - filled, length - position)
                pending.withUnsafeBufferPointer { (out + filled).update(from: $0.baseAddress! + pendingOffset, count: n) }
                pendingOffset += n
                filled += n
                position += n
            }
        }
        return filled
    }

    private func nextBuffer() -> Bool {
        guard !finished, let sample = output.copyNextSampleBuffer() else {
            finished = true
            return false
        }
        let frames = CMSampleBufferGetNumSamples(sample)
        guard frames > 0, let block = CMSampleBufferGetDataBuffer(sample) else { return true }
        let pendingCount = pending.count
        pending = [Float](repeating: 0, count: frames)
        pending.withUnsafeMutableBytes { dst in
            _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: min(dst.count, CMBlockBufferGetDataLength(block)),
                                           destination: dst.baseAddress!)
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        var start = Int(((pts - origin).seconds * Double(VoiceEnhancer.rate)).rounded())
        if started, abs(start - pendingStart - pendingCount) <= 2 { start = pendingStart + pendingCount }
        started = true
        pendingStart = start
        pendingOffset = 0
        return true
    }
}

final class MonoWriter {
    private var file: AVAudioFile?
    private let buffer: AVAudioPCMBuffer

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(VoiceEnhancer.rate), channels: 1,
                                   interleaved: false)!
        file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: VoiceEnhancer.rate, AVNumberOfChannelsKey: 1,
            AVEncoderBitDepthHintKey: 24,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1 << 15)!
    }

    func write(_ samples: UnsafePointer<Float>, count: Int) throws {
        guard let file else { return }
        var done = 0
        while done < count {
            let n = min(Int(buffer.frameCapacity), count - done)
            buffer.floatChannelData![0].update(from: samples + done, count: n)
            buffer.frameLength = AVAudioFrameCount(n)
            try file.write(from: buffer)
            done += n
        }
    }

    func close() {
        file?.close()
        file = nil
    }
}

enum WAV {
    static func write(_ samples: [Float], sampleRate: Int = VoiceEnhancer.rate, to url: URL) throws {
        var data = Data(capacity: 44 + samples.count * 4)
        func tag(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 4)
        tag("RIFF"); u32(36 + bytes); tag("WAVE")
        tag("fmt "); u32(16); u16(3); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 4)); u16(4); u16(32)
        tag("data"); u32(bytes)
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        try data.write(to: url)
    }

    static func readMono(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { return [] }
        try file.read(into: buffer)
        guard let data = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
    }
}
