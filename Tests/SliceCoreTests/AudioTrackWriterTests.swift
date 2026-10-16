//
//  AudioTrackWriterTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/11/26.
//

import AVFoundation
@testable import SliceCore
import XCTest

final class AudioTrackWriterTests: XCTestCase {
    static let fmt = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!

    static func tone(at t: Double, frames: Int = 1024) -> CMSampleBuffer {
        let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frames))!
        pcm.frameLength = AVAudioFrameCount(frames)
        for c in 0 ..< 2 { for i in 0 ..< frames { pcm.floatChannelData![c][i] = 0.3 * Float(sin(Double(i) * 0.1)) } }
        var desc: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: fmt.streamDescription, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &desc)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48000),
                                        presentationTimeStamp: CMTime(seconds: t, preferredTimescale: 48000), decodeTimeStamp: .invalid)
        var sb: CMSampleBuffer?
        CMSampleBufferCreate(allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil, formatDescription: desc,
                             sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0,
                             sampleSizeArray: nil, sampleBufferOut: &sb)
        CMSampleBufferSetDataBufferFromAudioBufferList(sb!, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0,
                                                       bufferList: pcm.audioBufferList)
        return sb!
    }

    func testGapsAreFilledNotClosed() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gap-\(UUID().uuidString).m4a")
        let w = try AudioTrackWriter(url: url, channels: 2)
        let start = CMTime(seconds: 10, preferredTimescale: 48000)
        var t = 10.5
        while t < 11.5 { w.append(Self.tone(at: t), start: start); t += 1024.0 / 48000 }
        t += 1.0
        while t < 13.5 { w.append(Self.tone(at: t), start: start); t += 1024.0 / 48000 }
        let ok = await w.finish(at: CMTime(seconds: 13.5, preferredTimescale: 48000))
        XCTAssertTrue(ok)
        let f = try AVAudioFile(forReading: url)
        let length = Double(f.length) / f.processingFormat.sampleRate
        XCTAssertEqual(length, 3.5, accuracy: 0.05, "audio keeps the recording's timing")
        XCTAssertEqual(w.insertedSilence, 1.5, accuracy: 0.05)
        let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
        try f.read(into: buf)
        let d = buf.floatChannelData![0]
        func loud(_ at: Double) -> Bool { let i = Int(at * 48000); return (i ..< i + 480).contains { abs(d[$0]) > 0.05 } }
        XCTAssertFalse(loud(0.2))
        XCTAssertTrue(loud(0.7))
        XCTAssertFalse(loud(2.0))
        XCTAssertTrue(loud(2.6))
        try? FileManager.default.removeItem(at: url)
    }
}
