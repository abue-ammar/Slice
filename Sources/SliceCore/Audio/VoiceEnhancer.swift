//
//  VoiceEnhancer.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/3/26.
//

import Accelerate
import AVFoundation

/// Makes a take's enhanced voice from its microphone recording, in two cached steps:
///
/// 1. `denoise` runs DeepFilterNet3 over the whole recording. It's the slow part and doesn't depend on any setting,
///    so it's done once per take (`voice/denoised-dfn3.m4a`).
/// 2. `finish` blends a little of the original back in (the noise reduction limit), then applies the optional polish:
///    EQ, compression, loudness normalization and a limiter. It takes seconds, so settings can change freely.
///
/// Every file is 48 kHz mono on the recording's own timeline (sample i plays i / 48000 s into the take), so it lines
/// up with the picture exactly as the original did. Files are written beside their final name and moved into place
/// when complete, so a cancelled or failed run never leaves a partial file that would later be taken as done.
public enum VoiceEnhancer {
    public enum Failure: LocalizedError {
        case noAudio
        case unreadable(String)

        public var errorDescription: String? {
            switch self {
            case .noAudio: "The microphone recording has no audio."
            case let .unreadable(m): "The microphone recording couldn't be read: \(m)"
            }
        }
    }

    static let rate = 48000
    static let chunk = 60 * rate
    static let preroll = rate, postroll = rate / 2
    static let overlap = 960
    public static let targetLoudness = -19.0

    // MARK: - A take

    public static func denoiseIfNeeded(_ clip: Clip, bundle: ProjectBundle, progress: (Double) -> Void) async throws {
        guard let mic = clip.micFile, let denoised = bundle.denoisedVoiceFile(for: clip) else { return }
        guard !FileManager.default.fileExists(atPath: bundle.file(denoised).path) else { return progress(1) }
        guard VoiceModel.isInstalled else { throw VoiceModel.Failure.notInstalled }
        try await denoise(bundle.file(mic), to: bundle.file(denoised), progress: progress)
    }

    @discardableResult
    public static func prepare(_ clip: Clip, settings: VoiceSettings, bundle: ProjectBundle,
                               progress: (Double) -> Void) async throws -> String? {
        guard let mic = clip.micFile, let denoised = bundle.denoisedVoiceFile(for: clip),
              let out = bundle.enhancedVoiceFile(for: clip, settings: settings) else { return nil }
        guard !FileManager.default.fileExists(atPath: bundle.file(out).path) else {
            progress(1)
            return out
        }
        let split = FileManager.default.fileExists(atPath: bundle.file(denoised).path) ? 0 : 0.85
        try await denoiseIfNeeded(clip, bundle: bundle) { progress($0 * split) }
        try await finish(original: bundle.file(mic), denoised: bundle.file(denoised), settings: settings, to: bundle.file(out)) {
            progress(split + $0 * (1 - split))
        }
        return out
    }

    // MARK: - Step 1: DeepFilterNet3

    public static func denoise(_ source: URL, to destination: URL, runtime: URL = VoiceModel.runtimeURL,
                               model: URL = VoiceModel.modelURL, progress: (Double) -> Void) async throws {
        let reader = try await MonoReader(url: source)
        let total = reader.length
        guard total > 0 else { throw Failure.noAudio }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("slice-voice-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let partial = partialURL(for: destination)
        defer { try? fm.removeItem(at: partial) }
        let writer = try MonoWriter(url: partial)

        let count = max(1, total / chunk)
        let bounds = (0 ... count).map { total * $0 / count }
        let half = overlap / 2
        var window: [Float] = [], windowStart = 0
        var tail: [Float] = []
        var scratch = [Float](repeating: 0, count: 1 << 16)
        progress(0)
        for i in 0 ..< count {
            try Task.checkCancellation()
            let keepStart = max(0, bounds[i] - half), keepEnd = min(total, bounds[i + 1] + half)
            let inStart = max(0, keepStart - preroll), inEnd = keepEnd + postroll
            if inStart > windowStart {
                window.removeFirst(min(inStart - windowStart, window.count))
                windowStart = inStart
            }
            while windowStart + window.count < min(inEnd, total) {
                let want = min(scratch.count, min(inEnd, total) - windowStart - window.count)
                let got = reader.read(&scratch, count: want)
                guard got > 0 else { break }
                window.append(contentsOf: scratch[0 ..< got])
            }
            var segment = Array(window.prefix(inEnd - windowStart))
            if segment.count < inEnd - inStart { segment += [Float](repeating: 0, count: inEnd - inStart - segment.count) }

            var peak: Float = 0
            vDSP_maxmgv(segment, 1, &peak, vDSP_Length(segment.count))
            let headroom: Float = peak > 0.95 ? 0.95 / peak : 1
            if headroom != 1 { vDSP.multiply(headroom, segment, result: &segment) }

            let input = work.appendingPathComponent("chunk-\(i).wav")
            try WAV.write(segment, to: input)
            let output = try await DeepFilter.run(runtime: runtime, model: model, input: input,
                                                  outputDirectory: work.appendingPathComponent("out"))
            var enhanced = try WAV.readMono(output)
            try? fm.removeItem(at: input)
            try? fm.removeItem(at: output)
            if headroom != 1 { vDSP.multiply(1 / headroom, enhanced, result: &enhanced) }

            let from = keepStart - inStart
            var kept = (from ..< from + (keepEnd - keepStart)).map { $0 < enhanced.count ? enhanced[$0] : 0 }
            if i > 0 {
                for k in 0 ..< min(overlap, kept.count, tail.count) {
                    let w = (Float(k) + 0.5) / Float(overlap)
                    kept[k] = tail[k] * (1 - w) + kept[k] * w
                }
            }
            if i < count - 1 {
                try kept.withUnsafeBufferPointer { try writer.write($0.baseAddress!, count: kept.count - overlap) }
                tail = Array(kept.suffix(overlap))
            } else {
                try kept.withUnsafeBufferPointer { try writer.write($0.baseAddress!, count: kept.count) }
            }
            progress(Double(i + 1) / Double(count))
        }
        writer.close()
        try replace(destination, with: partial)
    }

    // MARK: - Step 2: blend and polish

    public static func finish(original: URL, denoised: URL, settings: VoiceSettings, to destination: URL,
                              progress: (Double) -> Void) async throws {
        let blend: Float = settings.noiseReduction >= VoiceSettings.fullReduction - 0.5
            ? 0 : Float(pow(10, -max(settings.noiseReduction, 0) / 20))
        let partial = partialURL(for: destination)
        defer { try? FileManager.default.removeItem(at: partial) }

        let passes = settings.polish ? (settings.compress ? 3 : 2) : 1
        var passIndex = 0
        func pass(_ body: (UnsafeMutablePointer<Float>, Int) throws -> Void) async throws {
            let voice = try await MonoReader(url: denoised)
            let room = blend > 0 ? try await MonoReader(url: original) : nil
            let total = voice.length
            let block = 1 << 15
            var a = [Float](repeating: 0, count: block), b = [Float](repeating: 0, count: block)
            var done = 0
            while done < total {
                try Task.checkCancellation()
                let n = min(block, total - done)
                let got = voice.read(&a, count: n)
                for k in got ..< n { a[k] = 0 }
                if let room {
                    let got = room.read(&b, count: n)
                    for k in got ..< n { b[k] = 0 }
                    for k in 0 ..< n { a[k] = a[k] * (1 - blend) + b[k] * blend }
                }
                try a.withUnsafeMutableBufferPointer { try body($0.baseAddress!, n) }
                done += n
                progress((Double(passIndex) + Double(done) / Double(max(total, 1))) / Double(passes))
            }
            passIndex += 1
        }

        let writer = try MonoWriter(url: partial)
        guard settings.polish else {
            try await pass { try writer.write($0, count: $1) }
            writer.close()
            return try replace(destination, with: partial)
        }

        let eq = settings.eq ? VoiceChain.equalizer() : []
        var meter = LoudnessMeter()
        var chain = VoiceChain(filters: eq)
        try await pass { chain.process($0, $1); meter.add($0, $1) }
        var pregain = 0.0, gain = 0.0
        if let measured = meter.integrated {
            var after = measured
            if settings.compress {
                pregain = min(max(-20 - measured, -20), 24)
                var meter = LoudnessMeter()
                var chain = VoiceChain(filters: eq, pregain: pregain, compressor: Compressor())
                try await pass { chain.process($0, $1); meter.add($0, $1) }
                after = meter.integrated ?? measured + pregain
            }
            gain = min(max((settings.normalize ? targetLoudness : measured) - after, -24), 24)
        } else if passes == 3 {
            passIndex += 1
        }

        var final = VoiceChain(filters: eq, pregain: pregain, compressor: settings.compress ? Compressor() : nil, gain: gain)
        var limiter = LookaheadLimiter()
        var skip = limiter.latency
        func emit(_ p: UnsafeMutablePointer<Float>, _ n: Int) throws {
            let s = min(skip, n)
            skip -= s
            try writer.write(p + s, count: n - s)
        }
        try await pass { p, n in
            final.process(p, n)
            limiter.process(p, n)
            try emit(p, n)
        }
        var flush = [Float](repeating: 0, count: limiter.latency)
        try flush.withUnsafeMutableBufferPointer { b in
            limiter.process(b.baseAddress!, b.count)
            try emit(b.baseAddress!, b.count)
        }
        writer.close()
        try replace(destination, with: partial)
    }

    static func partialURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".partial-\(UUID().uuidString)-\(url.lastPathComponent)")
    }

    static func replace(_ destination: URL, with file: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: file)
        } else {
            try fm.moveItem(at: file, to: destination)
        }
    }
}
