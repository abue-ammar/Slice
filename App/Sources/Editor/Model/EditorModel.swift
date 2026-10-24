//
//  EditorModel.swift
//  Slice
//
//  Created by rit3zh CX on 10/15/26.
//

import AVFoundation
import Combine
import SliceCore
import SwiftUI

@MainActor
final class PlaybackClock: ObservableObject {
    @Published var time: Double = 0
    @Published var isPlaying = false
}

/// Passes on progress from a background job only when it reaches a new whole percent. Progress is published on the
/// editor, so every report redraws the timeline and panels; jobs that report per frame would otherwise do that
/// hundreds of times a second.
final class ProgressThrottle: @unchecked Sendable {
    let lock = NSLock()
    var last = -1

    func shouldReport(_ p: Double) -> Bool {
        let percent = Int((min(max(p, 0), 1) * 100).rounded(.down))
        return lock.withLock {
            guard percent != last else { return false }
            last = percent
            return true
        }
    }
}

@MainActor
final class EditorModel: ObservableObject {
    enum Selection: Equatable {
        case camera(UUID)
        case zoom(UUID)
        case section(clipID: UUID, start: Double)
        case music(UUID)
        case transition(UUID)
        case keyframe(UUID)
        case redact(UUID)
        case spotlight(UUID)
        case annotation(UUID)
    }

    let bundle: ProjectBundle
    @Published var project: Project {
        // Picking what's already picked mustn't add an undo step, save, or rebuild anything.
        didSet { if project != oldValue { projectChanged(from: oldValue) } }
    }

    @Published var selection: Selection? {
        didSet {
            if selection != nil { wordSelection = nil }
            updateRenderOptions()
            if selection != oldValue {
                revealSelectedLens()
                revealSelectedRedaction()
                revealSelectedSpotlight()
                revealSelectedAnnotation()
            }
        }
    }

    let clock = PlaybackClock()
    var time: Double { clock.time }
    var isPlaying: Bool { clock.isPlaying }
    /// Preview speed, kept for next time.
    @Published var playbackRate: Float = UserDefaults.standard.object(forKey: "playback.rate") as? Float ?? 1 {
        didSet {
            UserDefaults.standard.set(playbackRate, forKey: "playback.rate")
            if isPlaying, player.rate != 0 { player.rate = playbackRate }
        }
    }
    @Published var exportJob: ExportJob?
    var exportTask: Task<Void, Never>?
    @Published var transcripts: [UUID: Transcript] = [:]
    @Published var captions: [Caption] = []
    @Published var wordSelection: ClosedRange<Int>?
    @Published var transcribeProgress: Double?
    @Published var transcribeError: String?
    /// What transcription is doing besides listening, like loading a model.
    @Published var transcribeNote: String?
    @Published var transcribeEngine: TranscriptionEngineKind?
    /// The last failure is fixed in Settings (pick the other engine, download the model).
    @Published var transcribeNeedsSettings = false
    var transcribeTask: Task<Void, Never>?
    @Published var audioError: String?
    @Published var importedAudio: [String] = []
    let audition = MusicAudition()
    @Published var smartZoomProgress: Double?
    @Published var smartZoomNote: String?
    @Published var noteSymbol = "sparkle.magnifyingglass"
    @Published var privacyScanProgress: Double?
    var privacyScanTask: Task<Void, Never>?
    @Published var quietScanRunning = false
    var smartZoomTask: Task<Void, Never>?
    var buildTask: Task<Void, Never>?
    var buildGeneration = 0
    var smartDetections: [UUID: SmartZoom.Detection] = [:]
    var smartReplan: Task<Void, Never>?
    @Published var silentMicTakes: [Int] = []
    @Published var words: [TranscriptWord] = []
    @Published var transcriptLines: [TranscriptLine] = []
    var spokenWords: [(start: Double, id: Int)] = []
    @Published var isEditingText = false
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var aimsOnCanvas = false
    @Published var isCutting = false
    @Published var cutFlash: CutFlash?
    var undoStack: [Project] = []
    var redoStack: [Project] = []
    var isRestoringHistory = false
    var lastChangeAt = Date.distantPast
    var glitchScan: Task<Void, Never>?
    var hoverScan: Task<Void, Never>?
    var speechScan: Task<Void, Never>?
    var audioLayout = CompositionBuilder.AudioLayout.empty
    var musicRebuild: Task<Void, Never>?
    @Published var voiceProgress: Double?
    @Published var voiceError: String?
    @Published var hearOriginalVoice = false {
        didSet { if hearOriginalVoice != oldValue { updateAudioMix() } }
    }
    @Published var showVoiceModelSheet = false
    /// Whether the 3D phone's model loaded, once it's been tried.
    @Published var device3DStatus: Device3DStatus?
    /// The camera being recorded over a take, while its sheet is open.
    @Published var overdub: CameraOverdub?
    var voiceTask: Task<Void, Error>?
    var denoiseJobs: [UUID: Task<Void, Error>] = [:]
    var voicePlan: [UUID: Double] = [:]
    var voiceParts: [UUID: Double] = [:]
    var exportVoiceProgress: ((Double) -> Void)?

    let player = AVPlayer()
    let renderState: RenderState
    var videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: EditorModel.outputAttributes)
    var packing: PreviewPacking?
    static let outputAttributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
    /// Scrubbing: one seek runs at a time, heading for the latest target, so seeks never queue up behind the mouse.
    var seekTarget: Double?
    var isSeeking = false
    /// Exact seeks under a running player stall the decoder, so a drag pauses playback and resumes it on release.
    var isScrubbing = false
    var resumeAfterScrub = false
    var volumeFade: Task<Void, Never>?
    let previewDriver: PreviewDriver
    var cursorLogs: [UUID: CursorLog] = [:]
    var cursorTrack: CursorTrack
    var resmoothTask: Task<Void, Never>?
    var timeObserver: Any?
    var saveTask: Task<Void, Never>?
    var endObserver: AnyCancellable?

    static let minBlock = 0.3

    init(bundle: ProjectBundle, project: Project, openAt: Double = 0) {
        self.bundle = bundle
        let logs = bundle.loadCursorLogs(for: project)
        let opened = Self.withImportedAnnotations(Self.withDeviceOpenings(project, catalog: DeviceManager.shared.catalog), logs: logs)
        self.project = opened
        if opened != project { try? bundle.save(opened) }
        let project = opened
        cursorLogs = logs
        cursorTrack = CursorTrack(project: project, logs: cursorLogs)
        renderState = RenderState(project: project, cursor: cursorTrack)
        previewDriver = PreviewDriver(renderState: renderState)
        Task.detached(priority: .utility) { FrameRenderer.warmUp() }
        renderState.update(backgroundImage: bundle.backgroundImage(for: project))
        transcripts = Self.loadTranscripts(bundle: bundle, project: project)
        refreshWordsAndCaptions()
        scanCameraGlitches()
        scanHoverMoments()
        scanSpeech()
        importedAudio = bundle.importedAudio()
        player.automaticallyWaitsToMinimizeStalling = false
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, self.player.rate != 0, !self.seekPending else { return }
                self.clock.time = t.seconds
            }
        }
        endObserver = NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                // Only the editor's own item: music previews and swapped-out items post this too.
                guard let self, let item = note.object as? AVPlayerItem, item === self.player.currentItem else { return }
                self.clock.time = self.duration
                self.clock.isPlaying = false
                self.invalidatePreview()
            }
        clock.time = min(max(openAt, 0), duration)
        buildTask = Task { await rebuild() }
        loadTransitionStills()
        if project.voice.enhance { scheduleVoice(rebuildIfReady: false) }
        warmUp3D()
    }

    var duration: Double { project.duration }
    var previewSize: CGSize { project.outputSize(shortSide: 720) }
}

struct ExportJob: Equatable {
    let id = UUID()

    enum Phase: Equatable {
        case preparing, rendering, finishing
        case done(bytes: Int64?)
        case failed(String)
    }

    var url: URL
    let format: ExportFormat
    var size: CGSize
    let fps: Int
    let hevc: Bool
    var bitRate: Int
    let duration: Double
    /// Every file this export writes: one, or one per shape in a batch.
    var outputs: [URL]
    var step = 0
    /// The shape being written, in a batch.
    var shape: OutputAspect?
    let byteLimit: Int64?
    var phase = Phase.preparing
    var note: String?
    var progress = 0.0
    let started = Date()
    var renderStarted: Date?

    var isRunning: Bool {
        switch phase {
        case .preparing, .rendering, .finishing: true
        case .done, .failed: false
        }
    }

    var remaining: Double? {
        guard phase == .rendering, let renderStarted, progress >= 0.03 else { return nil }
        let elapsed = Date().timeIntervalSince(renderStarted)
        guard elapsed > 1.5 else { return nil }
        return elapsed / progress * (1 - progress)
    }
}
