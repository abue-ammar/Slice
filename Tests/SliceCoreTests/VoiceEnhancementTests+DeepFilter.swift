//
//  VoiceEnhancementTests+DeepFilter.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/13/26.
//

import AVFoundation
@testable import SliceCore
import XCTest

extension VoiceEnhancementTests {
    /// Downloads the model and runtime (36 MB) into a scratch folder, so it only runs when asked for:
    /// `SLICE_VOICE_E2E=1 SLICE_VOICE_MODEL_DIR=<folder> swift test --filter VoiceEnhancementTests`.
    func testDeepFilterNet3EndToEnd() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SLICE_VOICE_E2E"] == "1", env["SLICE_VOICE_MODEL_DIR"] != nil else {
            throw XCTSkip("Set SLICE_VOICE_E2E=1 and SLICE_VOICE_MODEL_DIR to download and run the real model.")
        }

        try? VoiceModel.remove()
        let cancelled = Task { try await VoiceModel.install { _, _ in } }
        try await Task.sleep(nanoseconds: 300_000_000)
        cancelled.cancel()
        do {
            try await cancelled.value
            XCTFail("a cancelled download shouldn't install")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertFalse(VoiceModel.isInstalled)
        let parent = VoiceModel.directory.deletingLastPathComponent()
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: parent.path).contains { $0.hasPrefix(".") },
                       "the staging folder is cleaned up")

        let progress = ProgressLog()
        try await VoiceModel.install { progress.add($0, $1) }
        XCTAssertTrue(VoiceModel.isInstalled)
        XCTAssertEqual(VoiceModel.installedBytes, VoiceModel.downloadBytes)
        XCTAssertEqual(progress.values.last?.0, VoiceModel.downloadBytes)
        XCTAssertEqual(progress.values.map(\.0), progress.values.map(\.0).sorted())
        XCTAssertEqual(try VoiceModel.sha256(of: VoiceModel.modelURL), VoiceModel.model.sha256)

        let dir = try tempDir()
        let (bundle, empty) = try ProjectBundle.create(name: "Voice", in: dir)
        var project = empty
        let id = UUID()
        let (clipDir, rel) = try bundle.makeClipFolder(id: id)
        let speech = try Self.spokenSentence()
        let lead = 2 * Self.rate
        let length = lead + speech.count + Self.rate
        var clean = [Float](repeating: 0, count: length)
        for (i, s) in speech.enumerated() { clean[lead + i] = s }
        let noise = Self.roomNoise(length, level: 0.03)
        let mic = zip(clean, noise).map { $0 + $1 }
        try await Self.writeAAC(mic, to: clipDir.appendingPathComponent("mic.m4a"))
        let tone = (0 ..< length).map { i -> Float in
            let t = Double(i) / 48000
            return (0.25 ..< 1.75).contains(t) ? Float(0.1 * sin(2 * .pi * 440 * t)) : 0
        }
        try await Self.writeAAC(tone, to: clipDir.appendingPathComponent("screen-audio.m4a"))
        let seconds = Double(length) / 48000
        try await ExportTests.makeMovie(url: clipDir.appendingPathComponent("screen.mov"),
                                        image: RenderTests.fakeScreen(size: CGSize(width: 640, height: 400)), duration: seconds)
        var clip = Clip(id: id, screenFile: "\(rel)/screen.mov", micFile: "\(rel)/mic.m4a", duration: seconds,
                        screenPixelSize: CGSize(width: 640, height: 400), captureRect: .zero)
        clip.screenAudioFile = "\(rel)/screen-audio.m4a"
        project.clips = [clip]
        project.export.resolution = .p1080
        project.export.fps = 30
        let micHash = try VoiceModel.sha256(of: bundle.file(clip.micFile!))

        let started = Date()
        let made = try await VoiceEnhancer.prepare(clip, settings: VoiceSettings(), bundle: bundle) { _ in }
        let elapsed = Date().timeIntervalSince(started)
        print("Voice for \(String(format: "%.1f", seconds)) s of audio made in \(String(format: "%.2f", elapsed)) s")
        XCTAssertNotNil(made)
        let original = try await Self.read(bundle.file(clip.micFile!))
        let denoised = try await Self.read(bundle.file(bundle.denoisedVoiceFile(for: clip)!))
        XCTAssertEqual(denoised.count, original.count)
        let roomBefore = Self.rmsDB(original[Self.rate / 2 ..< lead - Self.rate / 4])
        let roomAfter = Self.rmsDB(denoised[Self.rate / 2 ..< lead - Self.rate / 4])
        print("Room noise \(String(format: "%.1f", roomBefore)) dB → \(String(format: "%.1f", roomAfter)) dB")
        XCTAssertLessThan(roomAfter, roomBefore - 20, "DeepFilterNet3 removes the room noise")
        let speechPart = lead ..< lead + speech.count
        XCTAssertGreaterThan(Self.rmsDB(denoised[speechPart]), Self.rmsDB(clean[speechPart]) - 4, "and keeps the voice")
        XCTAssertEqual(Self.lag(clean, denoised), 0, "the voice stays where it was")
        func snr(_ y: [Float]) -> Double {
            let g = zip(clean, y).reduce(0.0) { $0 + Double($1.0 * $1.1) } / clean.reduce(0.0) { $0 + Double($1 * $1) }
            var err = 0.0, sig = 0.0
            for i in speechPart { let r = g * Double(clean[i]); sig += r * r; err += pow(Double(y[i]) - r, 2) }
            return 10 * log10(sig / err)
        }
        print("Speech SNR \(String(format: "%.1f", snr(original))) dB → \(String(format: "%.1f", snr(denoised))) dB")
        XCTAssertGreaterThan(snr(denoised), snr(original) + 3)
        XCTAssertEqual(try VoiceModel.sha256(of: bundle.file(clip.micFile!)), micHash, "the recording is never changed")

        let cursor = CursorTrack(project: project, logs: [:])
        let plainURL = dir.appendingPathComponent("plain.mp4"), enhancedURL = dir.appendingPathComponent("enhanced.mp4")
        try await Exporter.export(project: project, bundle: bundle, cursor: cursor, to: plainURL) { _ in }
        project.voice.enhance = true
        try await Exporter.export(project: project, bundle: bundle, cursor: cursor, to: enhancedURL) { _ in }
        let plain = try await Self.readMovieAudio(plainURL), enhanced = try await Self.readMovieAudio(enhancedURL)
        let toneWindow = Self.rate / 2 ..< Self.rate * 3 / 2
        let toneLoss = Self.toneDB(plain[toneWindow], hz: 440) - Self.toneDB(enhanced[toneWindow], hz: 440)
        print("Screen audio tone change: \(String(format: "%.2f", toneLoss)) dB")
        XCTAssertEqual(toneLoss, 0, accuracy: 1, "the screen audio is left alone")
        let quiet = lead - Self.rate / 4 ..< lead
        print("Exported room noise \(String(format: "%.1f", Self.rmsDB(plain[quiet]))) dB → \(String(format: "%.1f", Self.rmsDB(enhanced[quiet]))) dB")
        XCTAssertLessThan(Self.rmsDB(enhanced[quiet]), Self.rmsDB(plain[quiet]) - 20, "the exported room noise is gone")
        let drift = Self.lag(plain, enhanced, range: 480)
        print("Enhanced vs original export offset: \(drift) samples")
        XCTAssertLessThanOrEqual(abs(drift), 48, "enhanced audio is in sync with the original")
        XCTAssertLessThanOrEqual(abs(Self.lag(clean, enhanced, range: 480) - Self.lag(clean, plain, range: 480)), 48)
        for url in [plainURL, enhancedURL] {
            let asset = AVURLAsset(url: url)
            let video = try await asset.loadTracks(withMediaType: .video).first!.load(.timeRange).duration.seconds
            let audio = try await asset.loadTracks(withMediaType: .audio).first!.load(.timeRange).duration.seconds
            XCTAssertEqual(audio, video, accuracy: 0.05)
        }
        try VoiceModel.remove()
        XCTAssertFalse(VoiceModel.isInstalled)
        XCTAssertNotEqual(bundle.voiceFile(for: clip, settings: project.voice), clip.micFile)
    }

    func testLongRecordingIsSeamless() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SLICE_VOICE_E2E"] == "1", env["SLICE_VOICE_MODEL_DIR"] != nil else {
            throw XCTSkip("Set SLICE_VOICE_E2E=1 and SLICE_VOICE_MODEL_DIR to run the real model.")
        }
        if !VoiceModel.isInstalled { try await VoiceModel.install { _, _ in } }
        let dir = try tempDir()
        let sentence = try Self.spokenSentence()
        let length = 185 * Self.rate
        var noisy = Self.roomNoise(length, level: 0.03)
        var at = Self.rate / 2
        while at + sentence.count < length {
            for (i, s) in sentence.enumerated() { noisy[at + i] += s }
            at += sentence.count + Self.rate / 3
        }
        let source = dir.appendingPathComponent("mic.m4a")
        try await Self.writeAAC(noisy, to: source)
        let decoded = try await Self.read(source)

        let started = Date()
        let chunked = dir.appendingPathComponent("denoised.m4a")
        var steps = 0
        try await VoiceEnhancer.denoise(source, to: chunked) { _ in steps += 1 }
        print("185 s denoised in \(String(format: "%.1f", Date().timeIntervalSince(started))) s, \(steps - 1) chunks")
        let result = try await Self.read(chunked)
        XCTAssertEqual(result.count, decoded.count)
        XCTAssertEqual(steps - 1, 3, "a minute (or a little more) at a time")

        let wav = dir.appendingPathComponent("whole.wav")
        try WAV.write(decoded, to: wav)
        let whole = try WAV.readMono(try await DeepFilter.run(runtime: VoiceModel.runtimeURL, model: VoiceModel.modelURL, input: wav,
                                                              outputDirectory: dir.appendingPathComponent("whole")))
        let seams = (1 ..< 3).map { decoded.count * $0 / 3 }
        for seam in seams {
            let span = seam - Self.rate / 2 ..< seam + Self.rate / 2
            let signal = Self.rmsDB(whole[span])
            let error = Self.rmsDB(ArraySlice(span.map { result[$0] - whole[$0] }))
            print("Seam at \(seam / Self.rate) s: difference \(String(format: "%.1f", error - signal)) dB below the voice")
            XCTAssertLessThan(error - signal, -25)
            let jumps = (seam - 960 ..< seam + 960).map { abs(result[$0] - result[$0 - 1]) }.max()!
            let typical = (seam - 48000 ..< seam - 960).map { abs(result[$0] - result[$0 - 1]) }.max()!
            XCTAssertLessThan(jumps, typical * 1.5 + 0.01, "no click at the seam")
        }
        XCTAssertEqual(Self.lag(whole, result), 0)
    }

    static func spokenSentence() throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("say-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", url.path, "--data-format=LEF32@48000",
                         "Hi everyone, welcome back. Today I'll show you how to record your screen and make your voice sound clean and clear."]
        try say.run()
        say.waitUntilExit()
        let samples = try WAV.readMono(url)
        guard samples.count > 48000 else { throw XCTSkip("The system voice isn't available.") }
        let peak = samples.map(abs).max() ?? 1
        return samples.map { $0 / peak * 0.5 }
    }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [(Int64, Int64)] = []
    func add(_ a: Int64, _ b: Int64) { lock.withLock { log.append((a, b)) } }
    var values: [(Int64, Int64)] { lock.withLock { log } }
}
