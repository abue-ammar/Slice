//
//  LiveAnalysisTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/15/26.
//

import AVFoundation
import CoreImage
@testable import SliceCore
import XCTest

/// What a take measures while it records has to match what the file scans find afterwards.
final class LiveAnalysisTests: XCTestCase {
    func buffer(width: Int = 600, height: Int = 400, _ gray: (Int, Int) -> UInt8) throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
        let buffer = try XCTUnwrap(pb)
        CVPixelBufferLockBaseAddress(buffer, [])
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let p = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let v = gray(x, y), i = y * row + x * 4
                p[i] = v; p[i + 1] = v; p[i + 2] = v; p[i + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    // MARK: - Screen changes

    func testLiveGridMatchesTheVideoGrid() throws {
        let frame = try buffer { x, y in UInt8((x * 255 / 600 + (y / 40 % 2) * 60) % 256) }
        let image = try XCTUnwrap(CIContext().createCGImage(CIImage(cvPixelBuffer: frame), from: CGRect(x: 0, y: 0, width: 600, height: 400)))
        let live = try XCTUnwrap(ScreenChange.luma(frame)), video = try XCTUnwrap(ScreenChange.luma(image))
        let difference = zip(live, video).map { abs(Int($0) - Int($1)) }
        XCTAssertLessThan(Double(difference.reduce(0, +)) / Double(difference.count), 4)
    }

    func testClicksAreMeasuredAndSavedWhileRecording() async throws {
        let dir = try tempDir()
        let plain = try buffer { _, _ in 200 }
        let menu = try buffer { x, y in (170 ..< 270).contains(x) && (80 ..< 200).contains(y) ? 90 : 200 }
        let click = CGPoint(x: 0.3, y: 0.2)
        let analyzer = LiveTakeAnalyzer(folder: dir, pointSize: CGSize(width: 300, height: 200), inFlightLimit: .max)
        analyzer.start(at: 100)
        for t in [100, 100.5, 100.9] { analyzer.screenFrame(plain, at: t) }
        analyzer.click(at: 101, click)
        for t in [101.2, 101.6, 101.8] { analyzer.screenFrame(menu, at: t) }

        // Settled 0.7 s after the click and on disk within a second, before the take ends.
        let cache = dir.appendingPathComponent(LiveTakeAnalyzer.cacheName)
        for _ in 0 ..< 40 where ScreenChange.cached(at: cache).isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        let saved = ScreenChange.cached(at: cache)
        XCTAssertEqual(saved.count, 1)

        let results = await analyzer.finish(duration: 2)
        let entry = try XCTUnwrap(results.screenChanges.first)
        XCTAssertEqual(entry.t, 1, accuracy: 1e-9)
        let expected = ScreenChange.compare(try XCTUnwrap(ScreenChange.luma(plain)), try XCTUnwrap(ScreenChange.luma(menu)), at: click)
        XCTAssertEqual(entry.result, expected)
        XCTAssertNotNil(entry.result.local, "the menu that opened")
        XCTAssertEqual(ScreenChange.cached(at: cache), results.screenChanges)
    }

    func testAClickNearTheEndIsSettledWhenTheTakeStops() async throws {
        let dir = try tempDir()
        let plain = try buffer { _, _ in 200 }, page = try buffer { _, _ in 30 }
        let analyzer = LiveTakeAnalyzer(folder: dir, pointSize: CGSize(width: 300, height: 200), inFlightLimit: .max)
        analyzer.start(at: 0)
        analyzer.screenFrame(plain, at: 0)
        analyzer.click(at: 1, CGPoint(x: 0.5, y: 0.5))
        analyzer.screenFrame(page, at: 1.2)
        let results = await analyzer.finish(duration: 1.4)
        XCTAssertGreaterThan(try XCTUnwrap(results.screenChanges.first).result.fraction, 0.9, "a new page")
    }

    func testSmartZoomUsesWhatWasMeasuredInsteadOfTheVideo() async throws {
        let dir = try tempDir()
        let (bundle, empty) = try ProjectBundle.create(name: "Live", in: dir)
        let id = UUID()
        let (clipDir, rel) = try bundle.makeClipFolder(id: id)
        var project = empty
        // No screen.mov at all: the only way to see the menu is the measurement saved while recording.
        project.clips = [Clip(id: id, screenFile: "\(rel)/screen.mov", cursorFile: "c.json", duration: 4,
                              screenPixelSize: CGSize(width: 1512, height: 982),
                              captureRect: CGRect(origin: .zero, size: SmartZoomTests.points), cursorInVideo: false)]
        let target = CGPoint(x: 0.5, y: 0.5)
        let menu = CGRect(x: 0.45, y: 0.5, width: 0.15, height: 0.2)
        let saved = [ScreenChange.Entry(t: 2.5, x: target.x, y: target.y, result: ScreenChange.Result(fraction: 0.03, local: menu))]
        try JSONEncoder().encode(saved).write(to: clipDir.appendingPathComponent(LiveTakeAnalyzer.cacheName))
        let log = SmartZoomTests.log(duration: 4, clicks: [(2.5, target)]) { t in
            SmartZoomTests.move(t, CGPoint(x: 0.1, y: 0.1), target, 1, 1.8)
        }
        let found = await SmartZoom.detect(project: project, logs: [id: log], bundle: bundle)
        let click = try XCTUnwrap(found[id]?.moments.first { $0.kind == .click })
        XCTAssertEqual(click.response, menu)
    }

    func testReadingAFrameKeepsUpWithTheCapture() throws {
        let frame = try buffer(width: 3840, height: 2160) { x, y in UInt8((x ^ y) & 255) }
        let size = CGSize(width: 1920, height: 1080)
        let runs = 30
        let start = CFAbsoluteTimeGetCurrent()
        for i in 0 ..< runs {
            _ = LiveTakeAnalyzer.Frame(frame, t: Double(i), pointer: CGPoint(x: 0.4, y: 0.6), pointSize: size, grid: true)
        }
        let each = (CFAbsoluteTimeGetCurrent() - start) / Double(runs)
        print("Keeping a 4K frame (with its overview grid): \(String(format: "%.2f", each * 1000)) ms")
        // Read off the capture queue; it only has to keep up with the frame rate.
        XCTAssertLessThan(each, 1.0 / 60)
    }

    // MARK: - Hover

    func testHoverMatchesTheFileScan() async throws {
        let size = CGSize(width: 300, height: 200)
        let button = CGRect(x: 0.35, y: 0.42, width: 0.12, height: 0.16)
        func pointer(_ t: Double) -> CGPoint { CGPoint(x: 0.2 + 0.3 * min(t, 1), y: 0.5) }
        func frame(_ t: Double) throws -> CVPixelBuffer {
            let lit = button.contains(pointer(t))
            return try buffer { x, y in
                button.contains(CGPoint(x: Double(x) / 600, y: Double(y) / 400)) ? (lit ? 80 : 210) : 230
            }
        }
        let analyzer = LiveTakeAnalyzer(folder: try tempDir(), pointSize: size, inFlightLimit: .max)
        analyzer.start(at: 0)
        var samples: [CursorLog.Sample] = []
        var frames: [(t: Double, buffer: CVPixelBuffer)] = []
        var t = 0.0
        while t <= 1.4 {
            let p = pointer(t)
            samples.append(.init(t: t, x: p.x, y: p.y))
            analyzer.pointer(at: t, p)
            if Int((t * 60).rounded()) % 2 == 0 {
                let f = try frame(t)
                frames.append((t, f))
                analyzer.screenFrame(f, at: t)
            }
            t += 1.0 / 60
        }
        let live = await analyzer.finish(duration: 1.4).hoverMoments

        var expected: [Double] = []
        for (a, b) in zip(frames, frames.dropFirst()) where HoverDetector.isHover(
            from: a.buffer, to: b.buffer,
            pointer: (HoverDetector.position(in: samples, at: a.t), HoverDetector.position(in: samples, at: b.t)), pointSize: size) {
            if b.t - (expected.last ?? -.infinity) > 1.0 / 30 { expected.append(b.t) }
        }
        XCTAssertFalse(expected.isEmpty, "the button lights up under the pointer")
        XCTAssertEqual(live, expected)
    }

    // MARK: - Camera and audio

    func testCameraGlitchesAreFoundAsFramesAreWritten() async throws {
        let calm = [Float](repeating: 100, count: 576), flash = [Float](repeating: 220, count: 576)
        let thumbs = [calm, calm, flash, calm, calm, calm]
        let analyzer = LiveTakeAnalyzer(folder: try tempDir(), pointSize: .zero)
        analyzer.start(at: 10)
        for (i, thumb) in thumbs.enumerated() { analyzer.cameraFrame(thumb, at: 10 + Double(i) / 30) }
        let live = await analyzer.finish(duration: 1).cameraGlitches
        let expected = CameraGlitchDetector.glitches(in: thumbs.enumerated().map { (Double($0.offset) / 30, $0.element) })
        XCTAssertEqual(live.count, 1)
        for (a, b) in zip(live, expected) {
            XCTAssertEqual(a.start, b.start, accuracy: 1e-9)
            XCTAssertEqual(a.end, b.end, accuracy: 1e-9)
        }
    }

    func sampleBuffer(_ samples: ArraySlice<Float>, rate: Double) throws -> CMSampleBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        pcm.frameLength = AVAudioFrameCount(samples.count)
        for (i, v) in samples.enumerated() { pcm.floatChannelData![0][i] = v }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(rate)), presentationTimeStamp: .zero,
                                        decodeTimeStamp: .invalid)
        var out: CMSampleBuffer?
        CMSampleBufferCreate(allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
                             formatDescription: format.formatDescription, sampleCount: CMItemCount(samples.count),
                             sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil,
                             sampleBufferOut: &out)
        let buffer = try XCTUnwrap(out)
        XCTAssertEqual(CMSampleBufferSetDataBufferFromAudioBufferList(buffer, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
                                                                      flags: 0, bufferList: pcm.audioBufferList), noErr)
        return buffer
    }

    func testAudioLevelsMatchTheFileScan() throws {
        let rate = 48000.0
        let audio: [Float] = (0 ..< Int(rate * 4)).map { i in
            let t = Double(i) / rate
            let on = (0.5 ..< 1.5).contains(t) || (2.2 ..< 3.4).contains(t)
            return Float(on ? 0.3 * sin(2 * .pi * 220 * t) : 0.0005 * sin(2 * .pi * 50 * t))
        }
        let levels = LiveAudioLevels()
        for start in stride(from: 0, to: audio.count, by: 1024) {
            levels.add(try sampleBuffer(audio[start ..< min(start + 1024, audio.count)], rate: rate))
        }
        let wav = try tempDir().appendingPathComponent("mic.wav")
        try WAV.write(audio, sampleRate: Int(rate), to: wav)
        let expected = AudioAnalysis.speech(in: wav)
        XCTAssertEqual(expected.count, 2)
        XCTAssertEqual(levels.speech.count, expected.count)
        for (a, b) in zip(levels.speech, expected) {
            XCTAssertEqual(a.start, b.start, accuracy: 0.021)
            XCTAssertEqual(a.end, b.end, accuracy: 0.021)
        }
        XCTAssertEqual(levels.isSilent, false)

        let quiet = LiveAudioLevels()
        XCTAssertNil(quiet.isSilent, "nothing heard yet")
        quiet.add(try sampleBuffer(ArraySlice([Float](repeating: 0, count: 4800)), rate: rate))
        XCTAssertEqual(quiet.isSilent, true)
    }
}
