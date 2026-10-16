//
//  Recorder+Device.swift
//  Slice
//
//  Created by rit3zh CX on 10/12/26.
//

import AppKit
import AVFoundation
import SliceCore
import ScreenCaptureKit
import VideoToolbox

struct DeviceCapture {
    let id: String
    var stream: DeviceStream
    let source: PhonePreviewSource
    let renderer: DeviceSurfaceRenderer
    let recorded: RecordedDevice
    let globalRect: CGRect
    let mapping: CursorLogger.Mapping
    var consumers: [UUID] = []
}

extension Recorder {
    func prepareDevice(_ id: String) async throws {
        let found = await MainActor.run { () -> (DeviceConnection, DeviceStream, DeviceLayout)? in
            guard let c = DeviceManager.shared.connection(for: id), c.info.state == .streaming, let stream = c.stream,
                  let layout = c.preview.snapshot().layout else { return nil }
            return (c, stream, layout)
        }
        guard let (connection, stream, layout) = found,
              let compositor = DeviceCompositor.shared,
              let renderer = DeviceSurfaceRenderer(compositor: compositor, size: layout.canvas) else {
            let name = await MainActor.run { DeviceManager.shared.connection(for: id)?.info.name ?? "The iPhone" }
            throw CaptureError.deviceNotStreaming(name)
        }
        let (recorded, scale, mapping) = await MainActor.run {
            (connection.recordedDevice, connection.info.model?.pointScale ?? 3, connection.pointerMapping())
        }
        let rect = CGRect(x: 0, y: 0, width: layout.canvas.width / scale, height: layout.canvas.height / scale)
        let best = max(stream.maxFrameRate, 30)
        fps = settings.fps == Settings.best ? best : min(settings.fps, best)
        var capture = DeviceCapture(id: id, stream: stream, source: connection.preview, renderer: renderer, recorded: recorded,
                                    globalRect: rect, mapping: mapping)
        capture.consumers = subscribe(to: stream, for: capture)
        device = capture
        if let latest = stream.latest { composite(latest.buffer, at: latest.time, from: stream, for: capture) }
        let observer = NotificationCenter.default.addObserver(forName: DeviceConnection.streamDidChange, object: nil,
                                                              queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let connection = note.object as? DeviceConnection, connection.id == id else { return }
                self?.deviceStreamChanged(connection.stream)
            }
        }
        await MainActor.run { observers.append(observer) }
    }

    func subscribe(to stream: DeviceStream, for capture: DeviceCapture) -> [UUID] {
        var ids = [stream.addVideoConsumer { [weak self] sample in
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
            self?.composite(buffer, at: CMSampleBufferGetPresentationTimeStamp(sample), from: stream, for: capture)
        }]
        if settings.screenAudio {
            ids.append(stream.addAudioConsumer { [weak self] sample in
                guard let self, let timed = self.hostTimed(sample, clock: stream.clock) else { return }
                // Sample buffers are immutable once made; handing one to the recorder's queue is safe.
                nonisolated(unsafe) let audio = timed
                self.queue.async { self.take?.appendScreenAudio(audio) }
            })
        }
        return ids
    }

    var deviceStreamMissing: Bool {
        guard let device else { return false }
        return MainActor.assumeIsolated { DeviceManager.shared.connection(for: device.id)?.stream !== device.stream }
    }

    func deviceStreamChanged(_ new: DeviceStream?) {
        guard var capture = device else { return }
        let recording = queue.sync { take != nil }
        guard let new else {
            if recording, deviceLostAt == nil { deviceLostAt = Date() }
            return
        }
        guard new !== capture.stream else { return }
        capture.consumers.forEach(capture.stream.removeConsumer)
        capture.stream = new
        capture.consumers = subscribe(to: new, for: capture)
        device = capture
        if let lost = deviceLostAt, Date().timeIntervalSince(lost) > 2 { deviceDropped = true }
        deviceLostAt = nil
        if let latest = new.latest { composite(latest.buffer, at: latest.time, from: new, for: capture) }
    }

    func composite(_ buffer: CVPixelBuffer, at time: CMTime, from stream: DeviceStream, for device: DeviceCapture) {
        guard let frame = device.source.snapshot().frame else { return }
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let layout = DeviceLayout(frame: frame.definition, streamSize: size)
        let clock = stream.clock
        let pts = clock.map { CFEqual($0, hostClock) ? time : CMSyncConvertTime(time, from: $0, to: hostClock) } ?? time
        device.renderer.render(screen: buffer, frame: frame, layout: layout) { [weak self] out in
            guard let self, let out, let sample = Self.sample(out, at: pts) else { return }
            self.queue.async {
                self.latestScreen = sample
                self.take?.appendScreen(sample)
            }
        }
    }

    static func sample(_ buffer: CVPixelBuffer, at time: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        guard let format else { return nil }
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: format,
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        return sample
    }
}

extension Recorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let reason: String
        switch (error as? SCStreamError)?.code {
        case .userDeclined?: reason = "Screen Recording permission was turned off."
        case .noDisplayList?, .noCaptureSource?: reason = "the display being recorded was disconnected."
        case .userStopped?: reason = "the recording was stopped from the menu bar."
        default: reason = error.localizedDescription
        }
        log.error("Screen capture stopped: \(error, privacy: .public)")
        DispatchQueue.main.async { [weak self] in self?.onInterrupted?(reason.prefix(1).uppercased() + reason.dropFirst()) }
    }
}

extension Recorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sample.isValid else { return }
        if type == .audio {
            take?.appendScreenAudio(sample)
            return
        }
        guard type == .screen else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        latestScreen = sample
        take?.appendScreen(sample)
    }
}

extension Recorder: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let take, let sample = hostTimed(sample) else { return }
        if output is AVCaptureVideoDataOutput {
            take.appendCamera(sample)
        } else {
            micLevel.store(MicLevel.rms(of: sample))
            take.appendMic(sample)
        }
    }
}
