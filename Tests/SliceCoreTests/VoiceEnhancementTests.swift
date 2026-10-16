//
//  VoiceEnhancementTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/13/26.
//

import AVFoundation
@testable import SliceCore
import XCTest

final class VoiceEnhancementTests: XCTestCase {
    static let rate = 48000

    // MARK: - Signals

    static func syllables(seconds: Double, level: Float, seed: UInt64 = 7) -> [Float] {
        var rng = seed
        func random() -> Float {
            rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(rng >> 40) / Float(1 << 24)
        }
        let n = Int(seconds * Double(rate))
        var out = [Float](repeating: 0, count: n)
        var i = rate / 4
        while i < n {
            let length = Int((0.12 + 0.25 * Double(random())) * Double(rate))
            let loud = level * (0.3 + 1.4 * random())
            let f0 = 110 + 60 * Double(random())
            for k in 0 ..< min(length, n - i) {
                let env = sin(Float.pi * Float(k) / Float(length))
                let t = Double(k) / Double(rate)
                var s = 0.0
                for h in 1 ... 12 { s += sin(2 * .pi * f0 * Double(h) * t * (1 + 0.1 * t)) / Double(h) }
                out[i + k] = loud * env * Float(s) * 0.5
            }
            i += length + Int((0.05 + 0.3 * Double(random())) * Double(rate))
        }
        return out
    }

    static func noise(_ n: Int, level: Float, seed: UInt64 = 3) -> [Float] {
        var rng = seed
        var b0: Float = 0, b1: Float = 0
        return (0 ..< n).map { i in
            rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let w = Float(rng >> 40) / Float(1 << 24) * 2 - 1
            b0 = 0.997 * b0 + 0.03 * w
            b1 = 0.6 * b1 + 0.4 * w
            return level * (b0 * 3 + b1 * 0.5 + 0.25 * sin(Float(i) * 2 * .pi * 120 / 48000))
        }
    }

    static func roomNoise(_ n: Int, level: Float) -> [Float] {
        var rng: UInt64 = 42
        var b0: Float = 0, b1: Float = 0, b2: Float = 0
        return (0 ..< n).map { i in
            rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let w = Float(rng >> 40) / Float(1 << 24) * 2 - 1
            b0 = 0.99765 * b0 + w * 0.0990460
            b1 = 0.96300 * b1 + w * 0.2965164
            b2 = 0.57000 * b2 + w * 1.0526913
            let t = Float(i) / 48000
            return level * ((b0 + b1 + b2 + w * 0.1848) * 0.25 + 0.3 * sin(2 * .pi * 60 * t) + 0.15 * sin(2 * .pi * 1200 * t))
        }
    }

    static func writeAAC(_ samples: [Float], to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 160_000,
        ])
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        var desc: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: format.streamDescription, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &desc)
        var at = 0
        while at < samples.count {
            let frames = min(1024, samples.count - at)
            let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
            pcm.frameLength = AVAudioFrameCount(frames)
            for k in 0 ..< frames { pcm.floatChannelData![0][k] = samples[at + k] }
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48000),
                                            presentationTimeStamp: CMTime(value: CMTimeValue(at), timescale: 48000),
                                            decodeTimeStamp: .invalid)
            var sb: CMSampleBuffer?
            CMSampleBufferCreate(allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
                                 formatDescription: desc, sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                 sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sb)
            CMSampleBufferSetDataBufferFromAudioBufferList(sb!, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0,
                                                           bufferList: pcm.audioBufferList)
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            XCTAssertTrue(input.append(sb!))
            at += frames
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let e = writer.error { throw e }
    }

    static func writeLossless(_ samples: [Float], to url: URL) throws {
        let w = try MonoWriter(url: url)
        try samples.withUnsafeBufferPointer { try w.write($0.baseAddress!, count: $0.count) }
        w.close()
    }

    static func read(_ url: URL) async throws -> [Float] {
        let r = try await MonoReader(url: url)
        var out = [Float](repeating: 0, count: r.length)
        let n = r.read(&out, count: out.count)
        return Array(out.prefix(n))
    }

    static func readMovieAudio(_ url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        reader.startReading()
        var out: [Float] = []
        while let sb = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sb) {
            var data = [Float](repeating: 0, count: CMBlockBufferGetDataLength(block) / 4)
            data.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!) }
            for f in stride(from: 0, to: data.count - 1, by: 2) { out.append((data[f] + data[f + 1]) / 2) }
        }
        return out
    }

    static func rmsDB(_ x: ArraySlice<Float>) -> Double {
        10 * log10(x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(x.count, 1)) + 1e-20)
    }

    static func loudness(_ x: [Float]) -> Double? {
        var m = LoudnessMeter()
        x.withUnsafeBufferPointer { m.add($0.baseAddress!, $0.count) }
        return m.integrated
    }

    static func lag(_ x: [Float], _ y: [Float], range: Int = 2400) -> Int {
        let from = min(x.count, y.count) / 4, to = min(x.count, y.count) * 3 / 4
        var best = (lag: 0, score: -Double.infinity)
        for l in -range ... range {
            var s = 0.0
            var i = from
            while i < to {
                let j = i + l
                if j >= 0, j < y.count { s += Double(x[i]) * Double(y[j]) }
                i += 3
            }
            if s > best.score { best = (l, s) }
        }
        return best.lag
    }

    static func toneDB(_ x: ArraySlice<Float>, hz: Double) -> Double {
        let w = 2 * Double.pi * hz / 48000, c = 2 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for v in x { let s0 = Double(v) + c * s1 - s2; s2 = s1; s1 = s0 }
        let power = s1 * s1 + s2 * s2 - c * s1 * s2
        return 10 * log10(power / Double(x.count * x.count) + 1e-20)
    }

    func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("voice-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    // MARK: - Polish building blocks

    func testLoudnessMeterMatchesBS1770() {
        let sine = (0 ..< 5 * Self.rate).map { (i: Int) -> Float in Float(0.1 * sin(2 * Double.pi * 997 * Double(i) / 48000)) }
        XCTAssertEqual(Self.loudness(sine) ?? 0, -23.01, accuracy: 0.1)
        XCTAssertNil(Self.loudness([Float](repeating: 0, count: Self.rate)), "silence has no loudness")
    }

    func testLimiterHoldsCeilingAndKeepsTiming() {
        var signal = Self.syllables(seconds: 3, level: 0.3)
        for i in stride(from: 1000, to: signal.count, by: 9000) { signal[i] = 1.8; signal[i + 1] = -1.6 }
        var limiter = LookaheadLimiter()
        var out = signal + [Float](repeating: 0, count: limiter.latency)
        out.withUnsafeMutableBufferPointer { limiter.process($0.baseAddress!, $0.count) }
        out.removeFirst(limiter.latency)
        XCTAssertEqual(out.count, signal.count)
        XCTAssertLessThanOrEqual(out.map(abs).max()!, limiter.ceiling + 1e-5)
        let quiet = (40000 ..< 44000).filter { i in !(stride(from: 1000, to: signal.count, by: 9000)).contains { abs($0 - i) < 4000 } }
        for i in quiet { XCTAssertEqual(out[i], signal[i], accuracy: 1e-4) }
    }

    func testCompressorIsGentle() {
        let c = Compressor()
        XCTAssertEqual(c.curve(-40), 0)
        XCTAssertEqual(c.curve(-10), -6, accuracy: 0.01, "2:1 above the knee")
        XCTAssertLessThan(c.curve(-22), 0)
        XCTAssertGreaterThan(c.curve(-22), -1)
    }

    // MARK: - Finishing a voice

    func testPolishReachesPodcastLoudnessInSync() async throws {
        let dir = try tempDir()
        let voice = Self.syllables(seconds: 8, level: 0.04)
        let denoised = dir.appendingPathComponent("denoised.m4a"), original = dir.appendingPathComponent("mic.m4a")
        try Self.writeLossless(voice, to: denoised)
        try await Self.writeAAC(voice, to: original)
        let before = try XCTUnwrap(Self.loudness(voice))

        let out = dir.appendingPathComponent("enhanced.m4a")
        var reported: [Double] = []
        try await VoiceEnhancer.finish(original: original, denoised: denoised, settings: VoiceSettings(), to: out) { reported.append($0) }
        let polished = try await Self.read(out)
        XCTAssertEqual(polished.count, voice.count, "same length as the recording")
        XCTAssertEqual(Self.loudness(polished) ?? 0, VoiceEnhancer.targetLoudness, accuracy: 0.8)
        XCTAssertLessThan(before, -30)
        XCTAssertLessThanOrEqual(polished.map(abs).max()!, 0.8915)
        XCTAssertLessThanOrEqual(abs(Self.lag(voice, polished)), 48, "polish doesn't shift the voice")
        XCTAssertEqual(reported.last ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(reported, reported.sorted(), "progress only moves forward")

        var keep = VoiceSettings()
        keep.normalize = false
        let kept = dir.appendingPathComponent("kept.m4a")
        try await VoiceEnhancer.finish(original: original, denoised: denoised, settings: keep, to: kept) { _ in }
        let keptSamples = try await Self.read(kept)
        XCTAssertEqual(Self.loudness(keptSamples) ?? 0, before, accuracy: 1)

        var flat = VoiceSettings()
        flat.eq = false
        let flatURL = dir.appendingPathComponent("flat.m4a")
        try await VoiceEnhancer.finish(original: original, denoised: denoised, settings: flat, to: flatURL) { _ in }
        let flatSamples = try await Self.read(flatURL)
        XCTAssertEqual(Self.lag(voice, flatSamples), 0)

        var plain = VoiceSettings()
        plain.polish = false
        let raw = dir.appendingPathComponent("raw.m4a")
        try await VoiceEnhancer.finish(original: original, denoised: denoised, settings: plain, to: raw) { _ in }
        let rawSamples = try await Self.read(raw)
        XCTAssertEqual(rawSamples.count, voice.count)
        XCTAssertLessThan(zip(rawSamples, voice).map { abs($0 - $1) }.max()!, 1e-5)
    }

    func testReductionLimitBlendsOriginalBack() async throws {
        let dir = try tempDir()
        let n = 3 * Self.rate
        let noisy = Self.noise(n, level: 0.05)
        let denoised = dir.appendingPathComponent("d.m4a"), original = dir.appendingPathComponent("o.m4a")
        try Self.writeLossless([Float](repeating: 0, count: n), to: denoised)
        try await Self.writeAAC(noisy, to: original)
        var s = VoiceSettings()
        s.polish = false
        s.noiseReduction = 20
        let out = dir.appendingPathComponent("e.m4a")
        try await VoiceEnhancer.finish(original: original, denoised: denoised, settings: s, to: out) { _ in }
        let result = try await Self.read(out)
        XCTAssertEqual(Self.rmsDB(result[...]) - Self.rmsDB(noisy[...]), -20, accuracy: 0.5)
    }

    func testVoiceFilesLiveBesideTheRecording() throws {
        let dir = try tempDir()
        let bundle = ProjectBundle(url: dir)
        let clip = Clip(screenFile: "clips/A/screen.mov", micFile: "clips/A/mic.m4a", duration: 1, screenPixelSize: .zero, captureRect: .zero)
        var settings = VoiceSettings()
        XCTAssertEqual(bundle.voiceFile(for: clip, settings: settings), "clips/A/mic.m4a")
        settings.enhance = true
        XCTAssertEqual(bundle.voiceFile(for: clip, settings: settings), "clips/A/mic.m4a", "until it's made, the recording plays")
        let made = try XCTUnwrap(bundle.enhancedVoiceFile(for: clip, settings: settings))
        XCTAssertTrue(made.hasPrefix("clips/A/voice/enhanced-"))
        try FileManager.default.createDirectory(at: bundle.file("clips/A/voice"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: bundle.file(made).path, contents: Data([1]))
        XCTAssertEqual(bundle.voiceFile(for: clip, settings: settings), made)
        var other = settings
        other.eq = false
        XCTAssertNotEqual(other.cacheKey, settings.cacheKey)
        XCTAssertEqual(bundle.voiceFile(for: clip, settings: other), "clips/A/mic.m4a")
        settings.enhance = false
        XCTAssertEqual(bundle.voiceFile(for: clip, settings: settings), "clips/A/mic.m4a", "off plays the recording")
        let silent = Clip(screenFile: "clips/B/screen.mov", duration: 1, screenPixelSize: .zero, captureRect: .zero)
        XCTAssertTrue(bundle.hasVoice(for: silent, settings: other))
    }

    func testOldProjectsDecodeWithEnhancementOff() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Project(name: "Old"))) as! [String: Any]
        json.removeValue(forKey: "voice")
        let project = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(project.voice, VoiceSettings())
        XCTAssertFalse(project.voice.enhance)
    }
}
