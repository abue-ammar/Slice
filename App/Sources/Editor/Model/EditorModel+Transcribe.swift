//
//  EditorModel+Transcribe.swift
//  Slice
//
//  Created by rit3zh CX on 10/16/26.
//

import SliceCore
import SwiftUI

extension EditorModel {
    var isTranscribing: Bool { transcribeTask != nil }

    /// Transcribes the takes that don't have a transcript yet with the engine picked in Settings. Runs off the main
    /// thread; each take is saved as soon as it's done, so stopping part way keeps what's finished.
    func transcribe(locale: Locale = .current) {
        let todo = untranscribedClips
        guard !todo.isEmpty, transcribeTask == nil else { return }
        let kind = TranscriptionPreferences.engine
        transcribeError = nil
        transcribeNeedsSettings = false
        // Parakeet's model is only ever downloaded when the user asks for it, in Settings.
        if kind == .parakeet, !ParakeetModel.isInstalled {
            failTranscription(TranscriptionError.modelNotInstalled, take: nil)
            return
        }
        let engine = kind.engine
        let jobs = todo.compactMap { clip in clip.speechAudioFile.map { (id: clip.id, url: bundle.file($0), duration: max(clip.duration, 0.1)) } }
        let total = jobs.reduce(0) { $0 + $1.duration }
        let throttle = ProgressThrottle()
        transcribeEngine = kind
        transcribeNote = nil
        transcribeProgress = 0
        transcribeTask = Task { [weak self] in
            var done = 0.0
            for job in jobs {
                let base = done / total, share = job.duration / total
                do {
                    let transcript = try await engine.transcribe(audio: job.url, locale: locale) { stage in
                        Task { @MainActor [weak self] in
                            self?.showTranscription(stage, progress: base, share: share, locale: locale, throttle: throttle)
                        }
                    }
                    try Task.checkCancellation()
                    try self?.save(transcript, for: job.id)
                } catch {
                    if !(error is CancellationError) { self?.failTranscription(error, take: job.id) }
                    break
                }
                done += job.duration
            }
            self?.finishTranscription()
        }
    }

    func cancelTranscription() {
        guard let task = transcribeTask else { return }
        task.cancel()
        transcribeNote = "Stopping…"
    }

    private func showTranscription(_ stage: TranscriptionStage, progress base: Double, share: Double, locale: Locale,
                                   throttle: ProgressThrottle) {
        guard transcribeTask != nil, transcribeTask?.isCancelled == false else { return }
        switch stage {
        case let .preparing(note):
            transcribeNote = note
        case let .installingAssets(fraction):
            let note = "Downloading Apple's \(locale.languageName) speech model…" + (fraction.map { " \(Int($0 * 100))%" } ?? "")
            if transcribeNote != note { transcribeNote = note }
        case let .transcribing(p):
            if transcribeNote != nil { transcribeNote = nil }
            let total = base + min(max(p, 0), 1) * share
            if throttle.shouldReport(total) { transcribeProgress = total }
        }
    }

    private func failTranscription(_ error: Error, take id: UUID?) {
        if let e = error as? TranscriptionError {
            transcribeError = e.localizedDescription
            switch e {
            case .unsupportedLanguage, .onDeviceUnavailable, .notAuthorized, .modelNotInstalled: transcribeNeedsSettings = true
            case .recognizerUnavailable, .failed: break
            }
            return
        }
        let take = id.flatMap { id in project.clips.firstIndex { $0.id == id } }.map { project.clips.count > 1 ? " take \($0 + 1)" : "" } ?? ""
        transcribeError = "Couldn't transcribe\(take): \(error.localizedDescription)"
    }

    private func finishTranscription() {
        transcribeTask = nil
        transcribeProgress = nil
        transcribeNote = nil
        transcribeEngine = nil
    }
}
