//
//  RecoveryTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/17/26.
//

import AVFoundation
@testable import SliceCore
import XCTest

/// Takes cut off mid-recording: their files are left unfinished, as a crash leaves them.
final class RecoveryTests: XCTestCase {
    private var dir: URL!
    private let start = CMTime(seconds: 5000, preferredTimescale: 600)
    /// Writers kept unfinished until the test ends, like a process that stopped mid-take.
    private var unfinished: [AnyObject] = []

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("slice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        unfinished = []
        try? FileManager.default.removeItem(at: dir)
    }

    private func writeScreen(_ url: URL, seconds: Double) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.movieFragmentInterval = ProjectBundle.fragmentInterval
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: 320, AVVideoHeightKey: 200,
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: start)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 320, 200, kCVPixelFormatType_32BGRA, nil, &buffer)
        for i in 0 ..< Int(seconds * 60) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            adaptor.append(try XCTUnwrap(buffer), withPresentationTime: start + CMTime(value: CMTimeValue(i * 10), timescale: 600))
        }
        unfinished.append(writer)
    }

    private func writeMic(_ url: URL, seconds: Double) throws {
        let writer = try AudioTrackWriter(url: url, channels: 1)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        for i in 0 ..< Int(seconds * 48000 / 1024) {
            let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
            pcm.frameLength = 1024
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48000),
                                            presentationTimeStamp: start + CMTime(value: CMTimeValue(i * 1024), timescale: 48000),
                                            decodeTimeStamp: .invalid)
            var sample: CMSampleBuffer?
            CMSampleBufferCreate(allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
                                 formatDescription: format.formatDescription, sampleCount: 1024, sampleTimingEntryCount: 1,
                                 sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample)
            let s = try XCTUnwrap(sample)
            CMSampleBufferSetDataBufferFromAudioBufferList(s, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0,
                                                           bufferList: pcm.audioBufferList)
            writer.append(s, start: start)
        }
        unfinished.append(writer)
    }

    /// A take as the recorder starts it: its folder, the clip it's to become, and a note left by `process`.
    private func take(in bundle: ProjectBundle, process: Int32) throws -> (Clip, URL) {
        let id = UUID()
        let (folder, rel) = try bundle.makeClipFolder(id: id)
        let clip = Clip(id: id, screenFile: "\(rel)/screen.mov", micFile: "\(rel)/mic.m4a", cursorFile: "\(rel)/cursor.json",
                        duration: 0, screenPixelSize: CGSize(width: 320, height: 200),
                        captureRect: CGRect(x: 0, y: 0, width: 160, height: 100), cursorInVideo: false)
        let note = ProjectBundle.RecordingNote(clip: clip, process: process)
        try JSONEncoder().encode(note).write(to: bundle.recordingNote(id))
        return (clip, folder)
    }

    private let gone: Int32 = 999_999

    func testCutOffTakeComesBackAsFarAsItPlays() async throws {
        let (bundle, _) = try ProjectBundle.create(name: "Demo", in: dir)
        let (planned, folder) = try take(in: bundle, process: gone)
        try await writeScreen(folder.appendingPathComponent("screen.mov"), seconds: 5)
        try writeMic(folder.appendingPathComponent("mic.m4a"), seconds: 5)
        let log = CursorLog(samples: [.init(t: 0, x: 0.2, y: 0.3), .init(t: 3, x: 0.6, y: 0.4)], clicks: [.init(t: 2, x: 0.6, y: 0.4)])
        try JSONEncoder().encode(log).write(to: folder.appendingPathComponent("cursor.json"))
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(bundle.hasInterruptedTakes)
        let found = await ProjectBundle.recoverInterruptedTakes(in: dir)
        XCTAssertEqual(found.map(\.url.lastPathComponent), ["Demo.slice"])

        let project = try bundle.load()
        let clip = try XCTUnwrap(project.clips.first)
        XCTAssertEqual(clip.id, planned.id)
        // Up to the last whole fragment: at most one fragment short of the five seconds written.
        XCTAssertGreaterThanOrEqual(clip.duration, 5 - ProjectBundle.fragmentInterval.seconds - 0.1)
        XCTAssertLessThanOrEqual(clip.duration, 5.01)
        XCTAssertEqual(clip.micFile, planned.micFile)
        XCTAssertEqual(clip.cursorFile, planned.cursorFile)
        XCTAssertEqual(bundle.loadCursorLogs(for: project)[clip.id], log)
        XCTAssertFalse(bundle.hasInterruptedTakes, "the note goes once the take is saved")

        let asset = AVURLAsset(url: bundle.file(clip.screenFile))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        _ = try await generator.image(at: CMTime(seconds: clip.duration - 0.1, preferredTimescale: 600))
    }

    func testTakeStillRecordingIsLeftAlone() async throws {
        let (bundle, _) = try ProjectBundle.create(name: "Demo", in: dir)
        let (_, folder) = try take(in: bundle, process: ProcessInfo.processInfo.processIdentifier)
        try await writeScreen(folder.appendingPathComponent("screen.mov"), seconds: 3)

        XCTAssertFalse(bundle.hasInterruptedTakes)
        let found = await ProjectBundle.recoverInterruptedTakes(in: dir)
        XCTAssertTrue(found.isEmpty)
        XCTAssertTrue(try bundle.load().clips.isEmpty)

        // Closing an editor on this project mustn't clear the take out from under the recorder.
        bundle.removeOrphanedClips(keeping: try bundle.load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("screen.mov").path))
    }

    func testTakeWithNothingPlayableIsGivenUp() async throws {
        let (bundle, _) = try ProjectBundle.create(name: "Demo", in: dir)
        let (_, folder) = try take(in: bundle, process: gone)
        try Data().write(to: folder.appendingPathComponent("screen.mov"))

        let found = await ProjectBundle.recoverInterruptedTakes(in: dir)
        XCTAssertTrue(found.isEmpty)
        XCTAssertTrue(try bundle.load().clips.isEmpty)
        XCTAssertFalse(bundle.hasInterruptedTakes)
        bundle.removeOrphanedClips(keeping: try bundle.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "an unusable take is cleared with the other leftovers")
    }

    func testNoteOfASavedTakeIsJustCleared() async throws {
        let (bundle, empty) = try ProjectBundle.create(name: "Demo", in: dir)
        let (planned, folder) = try take(in: bundle, process: gone)
        try await writeScreen(folder.appendingPathComponent("screen.mov"), seconds: 3)
        var project = empty
        var saved = planned
        saved.duration = 3
        project.clips = [saved]
        try bundle.save(project)

        let recovered = try await bundle.recoverInterruptedTakes()
        XCTAssertEqual(recovered, 0)
        XCTAssertEqual(try bundle.load().clips, [saved])
        XCTAssertFalse(bundle.hasInterruptedTakes)
    }
}
