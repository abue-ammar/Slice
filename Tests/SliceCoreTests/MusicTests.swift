//
//  MusicTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/11/26.
//

import AVFoundation
@testable import SliceCore
import XCTest

final class MusicTests: XCTestCase {
    private func clip(start: Double = 0, end: Double = 10, toEnd: Bool = false, offset: Double = 0,
                      source: Double = 4, loops: Bool = false) -> MusicClip {
        MusicClip(source: .file("audio/a.wav"), name: "A", start: start, end: end, toEnd: toEnd, offset: offset,
                  sourceDuration: source, loops: loops)
    }

    private func project(duration: Double) -> Project {
        var p = Project(name: "Music")
        p.clips = [Clip(screenFile: "s.mov", micFile: "m.m4a", duration: duration, screenPixelSize: CGSize(width: 100, height: 100),
                        captureRect: .zero)]
        return p
    }

    // MARK: Placement

    func testNonLoopingClipStopsAtTheEndOfItsSource() {
        let c = clip(start: 1, end: 10, offset: 1, source: 4)
        XCTAssertEqual(c.timelineRange(duration: 20), 1 ... 4)
        XCTAssertEqual(c.pieces(duration: 20), [MusicPiece(lane: 0, at: 1, from: 1, length: 3)])
        XCTAssertEqual(c.timelineRange(duration: 2.5), 1 ... 2.5)
    }

    func testLoopRepeatsAcrossTwoLanesWithOverlaps() {
        let c = clip(start: 0, end: 10, toEnd: true, offset: 1, source: 4, loops: true)
        let pieces = c.pieces(duration: 12)
        XCTAssertEqual(pieces.first, MusicPiece(lane: 0, at: 0, from: 1, length: 3))
        XCTAssertEqual(pieces.last?.end ?? 0, 12, accuracy: 1e-9, "fills to the end of the video")
        for (a, b) in zip(pieces, pieces.dropFirst()) {
            XCTAssertNotEqual(a.lane, b.lane)
            XCTAssertGreaterThan(a.end, b.at, "each repeat overlaps the next to crossfade")
            XCTAssertEqual(b.from, 0)
        }
        XCTAssertEqual(c.sourceTime(at: 0.5, duration: 12)!, 1.5, accuracy: 1e-9)
    }

    func testMoveAndTrimStayInFreeSpace() {
        var p = project(duration: 30)
        let a = clip(start: 0, end: 5, source: 20), b = clip(start: 10, end: 15, source: 20)
        p.music = [a, b]
        p.moveMusic(a.id, to: 8)
        XCTAssertEqual(p.music[0].start, 5, "stops against the next clip")
        XCTAssertEqual(p.music[0].end, 10)

        p.trimMusic(b.id, start: 12)
        XCTAssertEqual(p.music[1].start, 12)
        XCTAssertEqual(p.music[1].offset, 2, accuracy: 1e-9)
        p.trimMusic(b.id, start: 0)
        XCTAssertEqual(p.music[1].start, 10, accuracy: 1e-9)
        XCTAssertEqual(p.music[1].offset, 0, accuracy: 1e-9)
        p.music[1].sourceDuration = 100
        p.trimMusic(b.id, end: 40)
        XCTAssertTrue(p.music[1].toEnd)
        XCTAssertEqual(p.music[1].timelineRange(duration: p.duration)?.upperBound, 30)
    }

    // MARK: Envelopes

    func testEnvelopeInterpolatesAndMultiplies() {
        let a = GainEnvelope([.init(t: 0, gain: 0), .init(t: 2, gain: 1)])
        XCTAssertEqual(a.value(at: -1), 0)
        XCTAssertEqual(a.value(at: 1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(a.value(at: 5), 1)
        let b = GainEnvelope([.init(t: 1, gain: 1), .init(t: 3, gain: 0)])
        let m = a * b
        for t in [0.0, 1, 2, 3] { XCTAssertEqual(m.value(at: t), a.value(at: t) * b.value(at: t), accuracy: 1e-9) }
        XCTAssertEqual((a * .constant(0.5)).value(at: 2), 0.5, accuracy: 1e-9)
    }

    func testDuckingDipsUnderSpeechAndMergesCloseWords() {
        let env = GainEnvelope.ducking(spans: [TimeSpan(start: 5, end: 6), TimeSpan(start: 6.4, end: 7)], level: 0.3,
                                       attack: 0.3, release: 0.8)
        XCTAssertEqual(env.value(at: 0), 1)
        XCTAssertEqual(env.value(at: 4.7), 1, accuracy: 1e-9, "starts dropping one attack ahead")
        XCTAssertEqual(env.value(at: 5), 0.3, accuracy: 1e-9, "fully down by the first word")
        XCTAssertEqual(env.value(at: 6.2), 0.3, accuracy: 1e-9, "a short pause between words doesn't pump")
        XCTAssertEqual(env.value(at: 7.1), 0.3, accuracy: 1e-9, "holds briefly after speech")
        XCTAssertEqual(env.value(at: 8), 1, accuracy: 1e-9)
        XCTAssertEqual(GainEnvelope.ducking(spans: [], level: 0.3, attack: 0.3, release: 0.8).value(at: 3), 1)
    }

    func testMusicLevelsFadeInDuckAndEvenOut() {
        var p = project(duration: 20)
        p.clips[0].speech = [TimeSpan(start: 8, end: 10)]
        var c = clip(start: 0, end: 20, toEnd: true, source: 6, loops: true)
        c.sourceLoudness = -30
        p.music = [c]
        p.audio.musicVolume = 0.4
        let lanes = p.musicLanes()
        XCTAssertEqual(Set(lanes.map(\.lane)), [0, 1])
        XCTAssertEqual(lanes.first { $0.lane == 0 }!.envelope.value(at: 3), 0.8, accuracy: 1e-6)
        p.audio.normalizeMusic = false
        XCTAssertEqual(p.musicLanes().first { $0.lane == 0 }!.envelope.value(at: 3), 0.4, accuracy: 1e-6)
        p.audio.normalizeMusic = true
        let lane0 = lanes.first { $0.lane == 0 }!.envelope
        XCTAssertEqual(lane0.value(at: 0), 0, accuracy: 1e-9, "fades in from silence")
        XCTAssertEqual(lanes.reduce(0) { $0 + $1.envelope.value(at: 20) }, 0, accuracy: 1e-9, "fades out by the end")

        p.audio.musicVolume = 0.2
        c.volume = 1
        p.music = [c]
        let ducked = p.musicShape(for: c).value(at: 9)
        XCTAssertEqual(ducked, 1 - p.audio.duckAmount, accuracy: 1e-6)
        p.micVolume = 0
        XCTAssertEqual(p.musicShape(for: c).value(at: 9), 1, accuracy: 1e-6)
        p.micVolume = 1
        p.audio.ducking = false
        XCTAssertEqual(p.musicShape(for: c).value(at: 9), 1, accuracy: 1e-6)
    }

    func testLoopCrossfadeKeepsPowerSteady() {
        var p = project(duration: 20)
        p.music = [clip(start: 0, end: 20, toEnd: true, source: 6, loops: true)]
        p.audio.ducking = false
        p.audio.musicVolume = 1
        let lanes = p.musicLanes()
        let seam = p.music[0].pieces(duration: 20)[1].at
        for t in stride(from: seam, through: seam + 1.2, by: 0.1) {
            let power = lanes.reduce(0) { $0 + pow($1.envelope.value(at: t), 2) }
            XCTAssertEqual(power, 1, accuracy: 0.05, "at \(t)")
        }
    }

    func testSpeechSpansFollowTheEdit() {
        var p = project(duration: 20)
        p.clips[0].speech = [TimeSpan(start: 2, end: 4), TimeSpan(start: 12, end: 14)]
        p.removeTime(from: 5, to: 10)
        XCTAssertEqual(p.speechSpans, [TimeSpan(start: 2, end: 4), TimeSpan(start: 7, end: 9)])
    }

    // MARK: Analysis

    func testSpeechDetectionAdaptsToTheNoiseFloor() {
        var levels = [Double](repeating: -45, count: 200)
        for i in 50 ..< 100 { levels[i] = i % 7 == 0 ? -40 : -20 }
        let spans = AudioAnalysis.speech(levels: levels, frameDuration: 0.02)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].start, 1, accuracy: 0.03)
        XCTAssertEqual(spans[0].end, 2, accuracy: 0.03)
        XCTAssertEqual(AudioAnalysis.speech(levels: [Double](repeating: -35, count: 200), frameDuration: 0.02), [])
        XCTAssertEqual(AudioAnalysis.speech(levels: [Double](repeating: -120, count: 200), frameDuration: 0.02), [])
    }

    func testLimiterKeepsPeaksUnderTheCeiling() {
        var limiter = PeakLimiter(sampleRate: 1000, ceiling: 0.9, release: 0.05)
        var samples: [Float] = (0 ..< 800).flatMap { i -> [Float] in
            let v = Float(sin(Double(i) * 0.3)) * (i < 200 ? 1.6 : 0.5)
            return [v, -v]
        }
        let original = samples
        samples.withUnsafeMutableBufferPointer { limiter.process($0.baseAddress!, frames: 800, channels: 2) }
        XCTAssertLessThanOrEqual(samples.map(abs).max()!, 0.9 + 1e-6)
        for i in 1200 ..< 1600 { XCTAssertEqual(samples[i], original[i], accuracy: 1e-3) }
    }

    func testBundledLibraryIsListedAndPlayable() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../App/Music").standardized
        setenv("SCREENREC_MUSIC_DIR", dir.path, 1)
        defer { unsetenv("SCREENREC_MUSIC_DIR") }
        let tracks = MusicLibrary.tracks()
        XCTAssertFalse(tracks.isEmpty)
        XCTAssertFalse(tracks.contains { $0.category == "Other" }, "every bundled file is in catalog.json")
        XCTAssertEqual(Set(tracks.map(\.id)).count, tracks.count, "ids are unique")
        XCTAssertFalse(MusicLibrary.categories(of: tracks).isEmpty)
        for t in tracks {
            let url = try XCTUnwrap(MusicLibrary.url(for: t.id))
            let s = try XCTUnwrap(AudioAnalysis.summarize(url), t.file)
            XCTAssertGreaterThan(s.duration, 10, t.file)
            XCTAssertGreaterThan(s.loudness, -40, t.file)
        }
    }

    func testOldProjectsOpenWithoutMusic() throws {
        let json = #"{"name":"Old","clips":[],"cameraBlocks":[],"zoomBlocks":[]}"#
        let p = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        XCTAssertEqual(p.music, [])
        XCTAssertEqual(p.audio, AudioSettings())
    }

    // MARK: Export

    static func makeTone(url: URL, seconds: Double, amplitude: Float = 0.5, frequency: Double = 440) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * 48000)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        for i in 0 ..< Int(frames) {
            let v = amplitude * Float(sin(2 * .pi * frequency * Double(i) / 48000))
            buf.floatChannelData![0][i] = v
            buf.floatChannelData![1][i] = v
        }
        try file.write(from: buf)
    }

    func testLoopingMusicIsExportedUnderTheVideo() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("music-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (bundle, empty) = try ProjectBundle.create(name: "Music", in: dir)
        var project = empty
        let id = UUID()
        let (clipDir, rel) = try bundle.makeClipFolder(id: id)
        try await ExportTests.makeMovie(url: clipDir.appendingPathComponent("screen.mov"),
                                        image: RenderTests.fakeScreen(size: CGSize(width: 640, height: 400)), duration: 4)
        project.clips = [Clip(id: id, screenFile: "\(rel)/screen.mov", duration: 4,
                              screenPixelSize: CGSize(width: 640, height: 400), captureRect: .zero)]

        let tone = dir.appendingPathComponent("tone.wav")
        try Self.makeTone(url: tone, seconds: 1.5, amplitude: 0.99)
        let audio = try bundle.importAudio(from: tone)
        XCTAssertEqual(try bundle.importAudio(from: tone), audio, "the same file is stored once")
        let summary = try XCTUnwrap(AudioAnalysis.summarize(bundle.file(audio)))
        XCTAssertEqual(summary.duration, 1.5, accuracy: 0.01)
        var music = MusicClip(source: .file(audio), name: "Tone", start: 0, end: 4, toEnd: true,
                              sourceDuration: summary.duration, loops: true, sourceLoudness: summary.loudness)
        music.fadeIn = 0.2
        music.fadeOut = 0.2
        project.music = [music]
        project.audio.musicVolume = 1
        project.audio.normalizeMusic = false
        project.export.resolution = .p1080
        project.export.fps = 30
        try bundle.save(project)
        XCTAssertEqual(try bundle.load(), project)

        let out = dir.appendingPathComponent("out.mp4")
        try await Exporter.export(project: project, bundle: bundle, cursor: CursorTrack(project: project, logs: [:]),
                                  to: out, progress: { _ in })
        let asset = AVURLAsset(url: out)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 4, accuracy: 0.1, "music never makes the video longer")
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let exported = try XCTUnwrap(audioTracks.first)
        let range = try await exported.load(.timeRange)
        XCTAssertEqual(range.end.seconds, 4, accuracy: 0.1)

        let levels = try await Self.peaks(of: asset, every: 0.05)
        for (i, peak) in levels.enumerated() where Double(i) * 0.05 > 0.3 && Double(i) * 0.05 < 3.6 {
            XCTAssertGreaterThan(peak, 0.3, "audible at \(Double(i) * 0.05)s")
        }
        XCTAssertLessThan(levels.max() ?? 1, 0.95)
        XCTAssertLessThan(levels.first ?? 1, 0.4, "fades in")

        try FileManager.default.removeItem(at: bundle.file(audio))
        XCTAssertNil(bundle.musicURL(for: .file(audio)))
        try await Exporter.export(project: project, bundle: bundle, cursor: CursorTrack(project: project, logs: [:]),
                                  to: out, progress: { _ in })
        let silent = try await AVURLAsset(url: out).loadTracks(withMediaType: .audio)
        XCTAssertTrue(silent.isEmpty)
    }

    static func peaks(of asset: AVAsset, every window: Double) async throws -> [Float] {
        let track = try await asset.loadTracks(withMediaType: .audio).first!
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
        ])
        reader.add(out)
        reader.startReading()
        var peaks: [Float] = []
        var frame = 0
        let per = Int(window * 48000)
        while let sb = out.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sb) {
            let length = CMBlockBufferGetDataLength(block)
            var data = [Float](repeating: 0, count: length / 4)
            _ = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            for i in stride(from: 0, to: data.count, by: 2) {
                let w = frame / per
                if w >= peaks.count { peaks.append(0) }
                peaks[w] = max(peaks[w], abs(data[i]), abs(data[i + 1]))
                frame += 1
            }
        }
        return peaks
    }
}
