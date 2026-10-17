//
//  AudioTrackWriter.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/15/26.
//

import AVFoundation
import Foundation

/// Writes one AAC audio file that stays locked to the recording clock.
///
/// AVAssetWriter butts audio buffers together and ignores gaps in their timestamps, so a stretch where a device
/// or the screen delivers no audio (or a buffer is dropped) pulls everything after it earlier, and the sound drifts
/// ahead of the picture. This writer compares each buffer's timestamp with how much audio it has written: gaps are
/// filled with silence and overlaps are dropped, so audio never strays more than `tolerance` from the video.
public final class AudioTrackWriter {
    private let writer: AVAssetWriter
    private let channels: Int
    private var input: AVAssetWriterInput?
    private var start: CMTime = .invalid
    private var written: Double = 0
    public let tolerance = 0.02
    public private(set) var insertedSilence: Double = 0
    public private(set) var droppedAudio: Double = 0
    /// Sees every buffer that goes into the file, inserted silence included, in order.
    public var onWrite: ((CMSampleBuffer) -> Void)?

    public init(url: URL, channels: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        writer.movieFragmentInterval = ProjectBundle.fragmentInterval
        self.channels = channels
    }

    public func append(_ sample: CMSampleBuffer, start sessionStart: CMTime) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        guard pts.isValid, CMSampleBufferGetNumSamples(sample) > 0,
              let desc = CMSampleBufferGetFormatDescription(sample),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) else { return }
        let rate = asbd.pointee.mSampleRate
        let duration = Double(CMSampleBufferGetNumSamples(sample)) / rate
        guard (pts + CMTime(seconds: duration, preferredTimescale: 48000)) > sessionStart else { return }

        if input == nil {
            let i = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: channels == 1 ? 160_000 : 256_000,
            ])
            i.expectsMediaDataInRealTime = true
            writer.add(i)
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: sessionStart)
            input = i
            start = sessionStart
        }
        guard let input else { return }

        let expected = written
        let actual = (pts - start).seconds
        if actual - expected > tolerance {
            if let silence = Self.silence(like: desc, seconds: actual - expected, at: start + CMTime(seconds: expected, preferredTimescale: 48000)),
               append(silence, to: input) {
                written += actual - expected
                insertedSilence += actual - expected
                onWrite?(silence)
            }
        } else if expected - actual > tolerance + duration * 0.5 {
            droppedAudio += duration
            return
        }
        if append(sample, to: input) {
            written += duration
            onWrite?(sample)
        }
    }

    private func append(_ sample: CMSampleBuffer, to input: AVAssetWriterInput) -> Bool {
        var waits = 0
        while !input.isReadyForMoreMediaData && waits < 50 {
            usleep(1000)
            waits += 1
        }
        return input.isReadyForMoreMediaData && input.append(sample)
    }

    public func cancel() { writer.cancelWriting() }

    public func finish(at stop: CMTime) async -> Bool {
        guard writer.status == .writing, let input else {
            writer.cancelWriting()
            return false
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: stop)
        await writer.finishWriting()
        return writer.status == .completed
    }

    static func silence(like desc: CMAudioFormatDescription, seconds: Double, at pts: CMTime) -> CMSampleBuffer? {
        let format = AVAudioFormat(cmAudioFormatDescription: desc)
        let frames = AVAudioFrameCount((seconds * format.sampleRate).rounded())
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buf.frameLength = frames
        let abl = UnsafeMutableAudioBufferListPointer(buf.mutableAudioBufferList)
        for b in abl { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(format.sampleRate)),
                                        presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var out: CMSampleBuffer?
        guard CMSampleBufferCreate(allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
                                   formatDescription: desc, sampleCount: CMItemCount(frames), sampleTimingEntryCount: 1,
                                   sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil,
                                   sampleBufferOut: &out) == noErr, let out,
              CMSampleBufferSetDataBufferFromAudioBufferList(out, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
                                                             flags: 0, bufferList: buf.audioBufferList) == noErr
        else { return nil }
        return out
    }
}
