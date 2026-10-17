//
//  RecordingController.swift
//  Slice
//
//  Created by rit3zh CX on 10/6/26.
//

import AVFoundation
import SliceCore
import SwiftUI

@MainActor
final class RecordingController: ObservableObject {
    enum Phase: Equatable {
        case preparing
        case countdown(Int)
        case recording
        case paused
        case finishing
    }

    @Published private(set) var phase: Phase = .preparing
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var micLevel: Float = -160
    private(set) var silenceWarning: String?
    private var interruption: String?
    private var deviceDropped = false
    var warning: String? {
        let parts = [
            interruption.map { "Recording stopped early: \($0) What was recorded up to then has been kept." },
            deviceDropped ? "The iPhone disconnected during the recording; its last picture is held until it came back." : nil,
            silenceWarning,
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
    var hasMic: Bool { settings.micID != nil }

    let settings: Recorder.Settings
    private var editor: EditorModel?
    private var bundle: ProjectBundle?
    private var project: Project?
    private var recorder: Recorder?
    private var takeStartedAt: Date?
    private var finishedSeconds = 0.0
    private var ticker: Timer?
    private var terminationDisabled = false
    private(set) var hidden: [NSWindow] = []
    private let onFinish: (Result<EditorModel?, Error>) -> Void

    var captureSession: AVCaptureSession? { recorder?.captureSession }
    var hasCamera: Bool { settings.cameraID != nil }

    init(settings: Recorder.Settings, editor: EditorModel?, onFinish: @escaping (Result<EditorModel?, Error>) -> Void) {
        self.settings = settings
        self.editor = editor
        self.onFinish = onFinish
    }

    func start() {
        Task {
            do {
                if let editor {
                    bundle = editor.bundle
                    project = editor.project
                } else {
                    let f = DateFormatter()
                    f.dateFormat = "yyyy-MM-dd HH.mm"
                    let (b, p) = try Wallpapers.newProject(name: "Recording \(f.string(from: Date()))")
                    bundle = b
                    project = p
                }
                let recorder = Recorder(settings: settings, bundle: bundle!)
                recorder.onInterrupted = { [weak self] reason in self?.interrupted(reason) }
                self.recorder = recorder
                try await recorder.prepare()
                // Keep macOS from quitting or suspending us while no app window is visible.
                ProcessInfo.processInfo.disableAutomaticTermination("Recording")
                ProcessInfo.processInfo.disableSuddenTermination()
                terminationDisabled = true
                hidden = NSApp.windows.filter { !($0 is NSPanel) && $0.isVisible && !DeviceWindowController.isDeviceWindow($0)
                    && $0 !== AppModel.captureBarWindow }
                let bar = CaptureBar.surface(for: phase)
                for window in hidden {
                    if let bar, window === AppModel.mainWindow {
                        WindowMorph.collapse(window, into: bar.rect, radius: bar.radius)
                    } else {
                        window.orderOut(nil)
                    }
                }
                for n in stride(from: 3, through: 1, by: -1) {
                    phase = .countdown(n)
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    if let interruption { throw CaptureError.interrupted(interruption) }
                }
                try beginTake()
            } catch {
                await recorder?.shutdown()
                cleanUpEmptyNewProject()
                finishSession()
                onFinish(.failure(error))
            }
        }
    }

    func togglePause() {
        switch phase {
        case .recording:
            phase = .finishing
            Task {
                await endTake()
                phase = .paused
            }
        case .paused:
            try? beginTake()
        default: break
        }
    }

    private func interrupted(_ reason: String) {
        guard interruption == nil else { return }
        interruption = reason
        stop()
    }

    func stop() {
        guard phase == .recording || phase == .paused else { return }
        let wasRecording = phase == .recording
        phase = .finishing
        Task {
            if wasRecording { await endTake() }
            deviceDropped = recorder?.deviceDropped ?? false
            await recorder?.shutdown()
            finishSession()
            guard let bundle, let project, !project.clips.isEmpty else {
                cleanUpEmptyNewProject()
                onFinish(.success(editor))
                return
            }
            // Only this session's takes, from what was measured while recording; a file is read only if that's missing.
            let earlier = Set(editor?.project.clips.map(\.id) ?? [])
            let measured = recorder?.micSilence ?? [:]
            let silent: [Int] = await Task.detached {
                project.clips.enumerated().compactMap { i, clip in
                    guard !earlier.contains(clip.id), let mic = clip.micFile else { return nil }
                    return measured[clip.id] ?? AudioCheck.isSilent(bundle.file(mic)) ? i + 1 : nil
                }
            }.value
            if !silent.isEmpty {
                let mic = settings.micID.flatMap { AVCaptureDevice(uniqueID: $0)?.localizedName } ?? "The microphone"
                silenceWarning = "\(mic) recorded silence in take \(silent.map(String.init).joined(separator: ", ")). "
                    + "Check it's switched on, unmuted and connected (watch the level meter on the setup screen), then record again."
            }
            do {
                try bundle.save(project)
                let before = Set(editor?.project.clips.map(\.id) ?? [])
                if let editor {
                    editor.appendRecordedClips(from: project)
                } else {
                    editor = EditorModel(bundle: bundle, project: project)
                }
                let fresh = Set(project.clips.map(\.id)).subtracting(before)
                editor?.smartZoomAfterRecording(clipIDs: fresh)
                editor?.open3DAfterRecording(clipIDs: fresh)
                await editor?.readyAfterRecording()
                onFinish(.success(editor))
            } catch {
                onFinish(.failure(error))
            }
        }
    }

    private func beginTake() throws {
        try recorder?.startTake()
        takeStartedAt = Date()
        phase = .recording
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        let v = recorder?.micLevel.load() ?? -160
        micLevel = v > micLevel ? v : max(v, micLevel - 3)
        guard let takeStartedAt else { return }
        elapsed = finishedSeconds + Date().timeIntervalSince(takeStartedAt)
    }

    private func endTake() async {
        ticker?.invalidate()
        takeStartedAt = nil
        guard let clip = await recorder?.endTake() else { return }
        project?.clips.append(clip)
        finishedSeconds += clip.duration
        elapsed = finishedSeconds
        guard let bundle, let project else { return }
        do {
            try bundle.save(project)
            bundle.clearRecordingNote(clip.id)
        } catch {
            // The note stays, so the take is put back from it next launch.
            log.error("Couldn't save the take: \(error.localizedDescription)")
        }
    }

    private func cleanUpEmptyNewProject() {
        guard editor == nil, let bundle, (project?.clips.isEmpty ?? true) else { return }
        try? FileManager.default.removeItem(at: bundle.url)
    }

    private func finishSession() {
        if terminationDisabled {
            ProcessInfo.processInfo.enableAutomaticTermination("Recording")
            ProcessInfo.processInfo.enableSuddenTermination()
            terminationDisabled = false
        }
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        // Setting mirroring on a connection that doesn't support it raises an exception.
        if let c = layer.connection, c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = true
        }
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
