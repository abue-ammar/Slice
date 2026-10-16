//
//  DeviceStream.swift
//  Slice
//
//  Created by rit3zh CX on 10/1/26.
//

import AVFoundation
import CoreMediaIO
import SliceCore

/// The live screen (and sound) of one connected iOS device, through the same public route QuickTime Player uses:
/// once screen-capture devices are allowed (`DeviceStream.allowScreenCaptureDevices`), each USB-connected, trusted
/// device appears as an AVFoundation capture device. One session per device feeds every consumer (the device window's
/// preview, the setup preview, the recorder), so nothing competes for the device.
///
/// Frames stay in the IOSurface-backed pixel buffers the capture delivers, which Metal reads without a copy.
final class DeviceStream: NSObject, @unchecked Sendable {
    struct Frame {
        let buffer: CVPixelBuffer
        let time: CMTime
        let sequence: Int
    }

    let captureDevice: AVCaptureDevice
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "device.stream", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "device.stream.audio", qos: .userInteractive)
    private let audioPreview = AVCaptureAudioPreviewOutput()
    private let lock = NSLock()
    private var latestFrame: Frame?
    private var sequence = 0
    private var arrivals: [CFTimeInterval] = []
    private var videoConsumers: [UUID: (CMSampleBuffer) -> Void] = [:]
    private var audioConsumers: [UUID: (CMSampleBuffer) -> Void] = [:]
    private(set) var maxFrameRate = 60

    var onFirstFrame: (() -> Void)?
    var onSizeChange: ((CGSize) -> Void)?
    var onFailure: ((String) -> Void)?
    private var lastSize: CGSize?

    init(device: AVCaptureDevice) {
        captureDevice = device
        super.init()
    }

    static func allowScreenCaptureDevices() {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &allow)
    }

    static func screenDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed, position: .unspecified)
            .devices.filter(isScreenDevice)
    }

    static func isScreenDevice(_ device: AVCaptureDevice) -> Bool {
        device.hasMediaType(.muxed) && device.modelID == "iOS Device"
    }

    var latest: Frame? { lock.withLock { latestFrame } }

    var measuredFrameRate: Int {
        let now = CACurrentMediaTime()
        return lock.withLock { arrivals.filter { now - $0 <= 1 }.count }
    }

    var clock: CMClock? { session.synchronizationClock }

    // MARK: - Lifecycle

    func start(playsSound: Bool) throws {
        session.beginConfiguration()
        let input = try AVCaptureDeviceInput(device: captureDevice)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw DeviceStreamError.cannotOpen
        }
        session.addInput(input)

        let video = AVCaptureVideoDataOutput()
        video.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        video.alwaysDiscardsLateVideoFrames = true
        video.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(video) { session.addOutput(video) }

        let audio = AVCaptureAudioDataOutput()
        audio.setSampleBufferDelegate(self, queue: audioQueue)
        if session.canAddOutput(audio) { session.addOutput(audio) }
        audioPreview.volume = playsSound ? 1 : 0
        if session.canAddOutput(audioPreview) { session.addOutput(audioPreview) }
        session.commitConfiguration()

        try useFastestFormat()
        NotificationCenter.default.addObserver(self, selector: #selector(runtimeError(_:)), name: AVCaptureSession.runtimeErrorNotification,
                                               object: session)
        session.startRunning()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        session.stopRunning()
        lock.withLock {
            videoConsumers = [:]
            audioConsumers = [:]
        }
    }

    var playsSound: Bool {
        get { audioPreview.volume > 0 }
        set { audioPreview.volume = newValue ? 1 : 0 }
    }

    private func useFastestFormat() throws {
        let best = captureDevice.formats.max { a, b in
            let ra = a.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            let rb = b.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            if ra != rb { return ra < rb }
            let da = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
            let db = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
            return Int(da.width) * Int(da.height) < Int(db.width) * Int(db.height)
        }
        guard let best, let range = best.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) else { return }
        try captureDevice.lockForConfiguration()
        captureDevice.activeFormat = best
        captureDevice.activeVideoMinFrameDuration = range.minFrameDuration
        captureDevice.unlockForConfiguration()
        maxFrameRate = max(Int(range.maxFrameRate.rounded()), 1)
    }

    @objc private func runtimeError(_ note: Notification) {
        let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
        onFailure?(error?.localizedDescription ?? "The screen stream stopped.")
    }

    // MARK: - Consumers

    func addVideoConsumer(_ handler: @escaping (CMSampleBuffer) -> Void) -> UUID {
        let id = UUID()
        lock.withLock { videoConsumers[id] = handler }
        return id
    }

    func addAudioConsumer(_ handler: @escaping (CMSampleBuffer) -> Void) -> UUID {
        let id = UUID()
        lock.withLock { audioConsumers[id] = handler }
        return id
    }

    func removeConsumer(_ id: UUID) {
        lock.withLock {
            videoConsumers[id] = nil
            audioConsumers[id] = nil
        }
    }
}

enum DeviceStreamError: LocalizedError {
    case cannotOpen

    var errorDescription: String? { "The iPhone's screen couldn't be opened. Unplug it and connect it again." }
}

extension DeviceStream: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output is AVCaptureAudioDataOutput {
            for consumer in lock.withLock({ Array(audioConsumers.values) }) { consumer(sample) }
            return
        }
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        let now = CACurrentMediaTime()
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let (first, resized, consumers) = lock.withLock {
            sequence += 1
            latestFrame = Frame(buffer: buffer, time: CMSampleBufferGetPresentationTimeStamp(sample), sequence: sequence)
            arrivals.append(now)
            if arrivals.count > 240 { arrivals.removeFirst(arrivals.count - 240) }
            let resized = lastSize != size
            lastSize = size
            return (sequence == 1, resized, Array(videoConsumers.values))
        }
        if first { onFirstFrame?() }
        if resized { onSizeChange?(size) }
        for consumer in consumers { consumer(sample) }
    }
}
