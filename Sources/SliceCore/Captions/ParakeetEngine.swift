//
//  ParakeetEngine.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/16/26.
//

import FluidAudio
import Foundation

/// Transcribes with Parakeet Ultra through FluidAudio, entirely on this Mac.
///
/// The model is loaded once and kept for the next recording, then let go after a while unused to give back its
/// memory. FluidAudio is kept in offline mode, so a missing or damaged file is reported instead of fetched behind
/// the user's back; only `ParakeetModel.install` downloads, and only when asked.
public actor ParakeetEngine: TranscriptionEngine {
    public static let shared = ParakeetEngine()
    static let idleTime: Duration = .seconds(600)

    private var manager: AsrManager?
    private var loading: Task<AsrManager, Error>?
    private var idleUnload: Task<Void, Never>?
    private var busy = 0

    public nonisolated var kind: TranscriptionEngineKind { .parakeet }

    public var isLoaded: Bool { manager != nil }

    /// Loads the model into memory if it isn't already.
    public func load() async throws {
        _ = try await prepared()
        scheduleIdleUnload()
    }

    public func unload() {
        idleUnload?.cancel()
        idleUnload = nil
        loading?.cancel()
        loading = nil
        let old = manager
        manager = nil
        if let old { Task { await old.cleanup() } }
    }

    public func transcribe(audio url: URL, locale: Locale,
                           stage: @escaping @Sendable (TranscriptionStage) -> Void) async throws -> Transcript {
        guard let code = locale.language.languageCode?.identifier, ParakeetModel.languages.contains(code) else {
            throw TranscriptionError.unsupportedLanguage(engine: .parakeet, language: locale.languageName)
        }
        guard ParakeetModel.isInstalled else { throw TranscriptionError.modelNotInstalled }
        busy += 1
        idleUnload?.cancel()
        defer {
            busy -= 1
            scheduleIdleUnload()
        }
        if manager == nil { stage(.preparing("Loading Parakeet AI…")) }
        let asr = try await prepared()
        try Task.checkCancellation()

        stage(.transcribing(0))
        let watcher = Task {
            for try await p in await asr.transcriptionProgressStream { stage(.transcribing(min(max(p, 0), 0.99))) }
        }
        defer { watcher.cancel() }
        var state = try TdtDecoderState(decoderLayers: await asr.decoderLayerCount)
        let result: ASRResult
        do {
            result = try await asr.transcribe(url, decoderState: &state, language: Language(rawValue: code))
        } catch ASRError.invalidAudioData {
            // Shorter than the model's shortest input, so there's nothing to hear.
            return Transcript(locale: locale.identifier, words: [], engine: TranscriptionBackend.parakeetUltra.rawValue)
        }
        try Task.checkCancellation()
        stage(.transcribing(1))
        return Transcript(locale: locale.identifier, words: Self.words(from: result, audio: url),
                          engine: TranscriptionBackend.parakeetUltra.rawValue)
    }

    static func words(from result: ASRResult, audio url: URL) -> [Word] {
        if let tokens = result.tokenTimings, !tokens.isEmpty {
            return WordTiming.words(fromTokens: tokens.map {
                WordTiming.Piece(text: $0.token, start: $0.startTime, end: $0.endTime, confidence: Double($0.confidence))
            })
        }
        // No token times came back: align the text to the speech in the recording rather than guess evenly.
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let span = AudioAnalysis.speech(in: url)
        let piece = WordTiming.Piece(text: text, start: span.first?.start ?? 0, end: span.last?.end ?? result.duration,
                                     confidence: Double(result.confidence))
        return WordTiming.words(fromSegments: [piece], levels: SpeechLevels(url: url))
    }

    private func prepared() async throws -> AsrManager {
        if let manager { return manager }
        if let loading { return try await loading.value }
        let task = Task { () throws -> AsrManager in
            ModelHub.offlineMode = true
            let models = try await AsrModels.load(from: ParakeetModel.directory, version: .ultra)
            let asr = AsrManager(config: .default)
            try await asr.loadModels(models)
            return asr
        }
        loading = task
        do {
            let asr = try await task.value
            if loading == task { manager = asr }
            loading = nil
            return asr
        } catch {
            if loading == task { loading = nil }
            throw error
        }
    }

    private func scheduleIdleUnload() {
        idleUnload?.cancel()
        guard busy == 0, manager != nil else { return }
        idleUnload = Task { [weak self] in
            try? await Task.sleep(for: Self.idleTime)
            guard !Task.isCancelled else { return }
            await self?.unloadIfIdle()
        }
    }

    private func unloadIfIdle() {
        guard busy == 0 else { return }
        unload()
    }
}
