//
//  CameraOverdub.swift
//  Slice
//
//  Created by rit3zh CX on 10/24/26.
//

import AVFoundation
import SliceCore
import SwiftUI

/// Records the camera, and the mic if one's picked, over a take that's already in the project (an imported video,
/// or a take recorded without a camera). The take plays from its first kept moment while the camera films, both
/// started on the same host time, so the new camera file lines up with the take as a recorded one would.
@MainActor
final class CameraOverdub: ObservableObject, Identifiable {
    enum Phase: Equatable { case ready, countdown(Int), recording, saving }

    struct Result {
        var cameraFile: String
        var cameraEnd: Double?
        var micFile: String?
    }

    let id = UUID()
    let clip: Clip
    let index: Int
    let from: Double
    let player: AVPlayer
    @Published private(set) var phase = Phase.ready
    /// Seconds into the take.
    @Published private(set) var position: Double
    @Published private(set) var session: AVCaptureSession?
    @Published private(set) var micLevel: Float = -160
    @Published var problem: String?
    var hasMic: Bool { micID != nil }

    private let bundle: ProjectBundle
    private let capture = OverdubCapture()
    private let onFinish: (Result?) -> Void
    private var cameraID: String?
    private var micID: String?
    private var writer: OverdubWriter?
    private var files: (camera: String, mic: String?)?
    private var begin: CMTime?
    private var ticker: Timer?
    private var countdown: Task<Void, Never>?
    private var endWatch: NSObjectProtocol?
    private var configuring: Task<Void, Never>?
    private var closed = false

    init(clip: Clip, index: Int, from: Double, bundle: ProjectBundle, onFinish: @escaping (Result?) -> Void) {
        self.clip = clip
        self.index = index
        self.from = from
        self.bundle = bundle
        self.onFinish = onFinish
        position = from
        player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = false
        Task { [player] in
            player.replaceCurrentItem(with: await Self.item(for: clip, in: bundle))
            await player.seek(to: CMTime(seconds: from, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    /// The take's picture with its own sound: what it recorded from apps and its mic, or an imported video's audio.
    private static func item(for clip: Clip, in bundle: ProjectBundle) async -> AVPlayerItem {
        let comp = AVMutableComposition()
        let length = CMTime(seconds: clip.duration, preferredTimescale: 600)
        func add(_ file: String, _ type: AVMediaType) async {
            let asset = AVURLAsset(url: bundle.file(file))
            guard let source = try? await asset.loadTracks(withMediaType: type).first,
                  let (range, transform) = try? await source.load(.timeRange, .preferredTransform),
                  let track = comp.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) else { return }
            try? track.insertTimeRange(CMTimeRange(start: range.start, duration: CMTimeMinimum(length, range.duration)),
                                       of: source, at: .zero)
            track.preferredTransform = transform
        }
        await add(clip.screenFile, .video)
        for file in [clip.screenAudioFile, clip.micFile].compactMap({ $0 }) { await add(file, .audio) }
        return AVPlayerItem(asset: comp)
    }

    // MARK: - Devices

    /// Sets up the camera and mic to film with, showing the camera straight away.
    func use(cameraID: String?, micID: String?) {
        guard phase == .ready, !closed, cameraID != self.cameraID || micID != self.micID || session == nil else { return }
        self.cameraID = cameraID
        self.micID = micID
        let old = session
        session = nil
        if let old { Task.detached { old.stopRunning() } }
        guard let cameraID, let camera = AVCaptureDevice(uniqueID: cameraID) else {
            problem = "Pick a camera to record with."
            return
        }
        problem = nil
        let mic = micID.flatMap(AVCaptureDevice.init(uniqueID:))
        let capture = capture
        configuring?.cancel()
        configuring = Task {
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                problem = "Camera access was denied. Enable it in System Settings > Privacy & Security > Camera."
                return
            }
            if mic != nil, !(await AVCaptureDevice.requestAccess(for: .audio)) {
                problem = "Microphone access was denied. Enable it in System Settings > Privacy & Security > Microphone."
                return
            }
            guard !Task.isCancelled, let s = try? capture.makeSession(camera: camera, mic: mic) else {
                if !Task.isCancelled { problem = "Couldn't start \(camera.localizedName)." }
                return
            }
            // startRunning blocks; keep it off the main thread.
            await Task.detached { s.startRunning() }.value
            guard !Task.isCancelled, self.cameraID == cameraID, self.micID == micID else {
                Task.detached { s.stopRunning() }
                return
            }
            session = s
        }
    }

    // MARK: - Recording

    func record() {
        guard phase == .ready, session != nil else { return }
        countdown = Task {
            for n in stride(from: 3, through: 1, by: -1) {
                phase = .countdown(n)
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }
            do {
                try await start()
            } catch is CancellationError {
            } catch {
                problem = "Couldn't start recording: \(error.localizedDescription)"
                phase = .ready
            }
        }
    }

    private func start() async throws {
        let at = CMTime(seconds: from, preferredTimescale: 600)
        for _ in 0 ..< 60 where player.currentItem?.status != .readyToPlay { try await Task.sleep(for: .milliseconds(50)) }
        await player.seek(to: at, toleranceBefore: .zero, toleranceAfter: .zero)
        try Task.checkCancellation()
        let folder = bundle.file(clip.screenFile).deletingLastPathComponent()
        let relative = (clip.screenFile as NSString).deletingLastPathComponent
        // A new name each time: the take's earlier camera stays on disk for undo.
        let tag = UUID().uuidString.prefix(8).lowercased()
        let cameraName = "camera-\(tag).mov", micName = hasMic ? "mic-\(tag).m4a" : nil
        // A moment ahead, so playback and filming both start exactly then.
        let begin = CMClockGetTime(CMClockGetHostTimeClock()) + CMTime(seconds: 0.15, preferredTimescale: 600)
        let writer = try OverdubWriter(cameraURL: folder.appendingPathComponent(cameraName),
                                       micURL: micName.map(folder.appendingPathComponent), begin: begin, from: from)
        capture.attach(writer)
        player.setRate(1, time: at, atHostTime: begin)
        self.writer = writer
        self.begin = begin
        files = ("\(relative)/\(cameraName)", micName.map { "\(relative)/\($0)" })
        endWatch = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                          object: player.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        phase = .recording
    }

    private func tick() {
        let level = capture.level.load()
        let next = level > micLevel ? level : max(level, micLevel - 3)
        if next != micLevel { micLevel = next }
        guard phase == .recording else { return }
        position = min(max(player.currentTime().seconds, from), clip.duration)
        if position >= clip.duration - 0.01 { stop() }
    }

    /// Ends the recording and keeps it.
    func stop() {
        guard phase == .recording, let writer, let begin, let files else { return }
        let stopTime = CMClockGetTime(CMClockGetHostTimeClock())
        phase = .saving
        player.pause()
        capture.attach(nil)
        Task {
            let done = await writer.finish(at: stopTime)
            self.writer = nil
            guard done.camera else {
                problem = "The camera recording couldn't be saved. Try again."
                phase = .ready
                await player.seek(to: CMTime(seconds: from, preferredTimescale: 600))
                position = from
                return
            }
            let reached = from + (stopTime - begin).seconds
            shutdown()
            onFinish(Result(cameraFile: files.camera, cameraEnd: reached < clip.duration - 0.05 ? reached : nil,
                            micFile: done.mic ? files.mic : nil))
        }
    }

    /// Closes without changing the take; anything being recorded is thrown away.
    func cancel() {
        guard phase != .saving, !closed else { return }
        countdown?.cancel()
        capture.attach(nil)
        writer?.discard()
        writer = nil
        shutdown()
        onFinish(nil)
    }

    private func shutdown() {
        closed = true
        configuring?.cancel()
        ticker?.invalidate()
        ticker = nil
        player.pause()
        if let endWatch { NotificationCenter.default.removeObserver(endWatch) }
        endWatch = nil
        if let s = session { Task.detached { s.stopRunning() } }
        session = nil
    }
}

/// The capture session's samples, on its own queue: put on the host clock and handed to the writer while recording.
final class OverdubCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate,
    @unchecked Sendable {
    let queue = DispatchQueue(label: "overdub.samples", qos: .userInteractive)
    let level = LevelBox()
    private let hostClock = CMClockGetHostTimeClock()
    private var writer: OverdubWriter?
    private var clock: CMClock?

    func makeSession(camera: AVCaptureDevice, mic: AVCaptureDevice?) throws -> AVCaptureSession {
        let session = AVCaptureSession()
        session.beginConfiguration()
        let input = try AVCaptureDeviceInput(device: camera)
        if session.canAddInput(input) { session.addInput(input) }
        let video = AVCaptureVideoDataOutput()
        video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        video.alwaysDiscardsLateVideoFrames = true
        video.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(video) { session.addOutput(video) }
        if let mic {
            let input = try AVCaptureDeviceInput(device: mic)
            if session.canAddInput(input) { session.addInput(input) }
            let audio = AVCaptureAudioDataOutput()
            audio.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(audio) { session.addOutput(audio) }
        }
        session.commitConfiguration()
        queue.sync { clock = session.synchronizationClock }
        return session
    }

    func attach(_ writer: OverdubWriter?) {
        queue.sync { self.writer = writer }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let isAudio = output is AVCaptureAudioDataOutput
        if isAudio { level.store(MicLevel.rms(of: sampleBuffer)) }
        guard let writer, let sample = hostTimed(sampleBuffer) else { return }
        if isAudio { writer.appendMic(sample) } else { writer.appendCamera(sample) }
    }

    private func hostTimed(_ sample: CMSampleBuffer) -> CMSampleBuffer? {
        guard let clock, !CFEqual(clock, hostClock) else { return sample }
        let pts = CMSyncConvertTime(CMSampleBufferGetPresentationTimeStamp(sample), from: clock, to: hostClock)
        var timing = CMSampleTimingInfo(duration: CMSampleBufferGetDuration(sample), presentationTimeStamp: pts,
                                        decodeTimeStamp: .invalid)
        var out: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: 1,
                                              sampleTimingArray: &timing, sampleBufferOut: &out)
        return out
    }
}
