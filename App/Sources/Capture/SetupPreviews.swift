//
//  SetupPreviews.swift
//  Slice
//
//  Created by rit3zh CX on 10/10/26.
//

import AVFoundation
import SwiftUI

@MainActor
final class CameraPreviewModel: ObservableObject {
    @Published private(set) var session: AVCaptureSession?
    private var deviceID: String?

    func show(cameraID: String?) {
        guard cameraID != deviceID || session == nil else { return }
        stop()
        deviceID = cameraID
        guard let cameraID, let device = AVCaptureDevice(uniqueID: cameraID) else { return }
        Task {
            guard await AVCaptureDevice.requestAccess(for: .video), deviceID == cameraID,
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            let s = AVCaptureSession()
            if s.canAddInput(input) { s.addInput(input) }
            // startRunning blocks; keep it off the main thread.
            await Task.detached { s.startRunning() }.value
            guard deviceID == cameraID else {
                s.stopRunning()
                return
            }
            session = s
        }
    }

    func stop() {
        if let s = session { Task.detached { s.stopRunning() } }
        session = nil
        deviceID = nil
    }
}

@MainActor
final class MicPreviewModel: NSObject, ObservableObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    @Published private(set) var level: Float = -160
    private var session: AVCaptureSession?
    private var deviceID: String?
    private var timer: Timer?
    private let queue = DispatchQueue(label: "mic.preview")
    private let latest = LevelBox()

    func show(micID: String?) {
        guard micID != deviceID || session == nil else { return }
        stop()
        deviceID = micID
        guard let micID, let device = AVCaptureDevice(uniqueID: micID) else { return }
        Task {
            guard await AVCaptureDevice.requestAccess(for: .audio), deviceID == micID,
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            let s = AVCaptureSession()
            let out = AVCaptureAudioDataOutput()
            out.setSampleBufferDelegate(self, queue: queue)
            if s.canAddInput(input) { s.addInput(input) }
            if s.canAddOutput(out) { s.addOutput(out) }
            await Task.detached { s.startRunning() }.value
            guard deviceID == micID else {
                s.stopRunning()
                return
            }
            session = s
            let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func poll() {
        let v = latest.load()
        let next = v > level ? v : max(v, level - 3)
        // @Published fires on every set; a silent mic would otherwise redraw the bar 20 times a second.
        if next != level { level = next }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let s = session { Task.detached { s.stopRunning() } }
        session = nil
        deviceID = nil
        level = -160
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        latest.store(MicLevel.rms(of: sampleBuffer))
    }
}

enum MicLevel {
    static func rms(of sample: CMSampleBuffer) -> Float {
        guard let desc = CMSampleBufferGetFormatDescription(sample),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc),
              let format = AVAudioFormat(streamDescription: asbd) else { return -160 }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return -160 }
        buf.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames),
                                                           into: buf.mutableAudioBufferList) == noErr else { return -160 }
        var sum: Double = 0
        var n = 0
        let channels = Int(format.channelCount)
        let stride = format.isInterleaved ? channels : 1
        let planes = format.isInterleaved ? 1 : channels
        for c in 0 ..< planes {
            for i in 0 ..< Int(frames) * stride {
                let v: Double
                if let f = buf.floatChannelData { v = Double(f[c][i]) }
                else if let s16 = buf.int16ChannelData { v = Double(s16[c][i]) / 32768 }
                else if let s32 = buf.int32ChannelData { v = Double(s32[c][i]) / 2_147_483_648 }
                else { return -160 }
                sum += v * v
                n += 1
            }
        }
        guard n > 0, sum > 0 else { return -160 }
        return Float(10 * log10(sum / Double(n)))
    }
}

struct MicMeter: View {
    let level: Float
    var showHint = true

    private var fraction: CGFloat { CGFloat(min(max((level + 60) / 60, 0), 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width)
                        .mask(alignment: .leading) { Capsule().frame(width: geo.size.width * fraction) }
                }
            }
            .frame(height: 6)
            .animation(.linear(duration: 0.1), value: fraction)
            if showHint {
                Text(level < -70 ? "No sound from this mic. Is it switched on, unmuted and connected?" : "Speak to check your level.")
                    .font(.caption)
                    .foregroundStyle(level < -70 ? Color.orange : Color.secondary)
            }
        }
    }
}
