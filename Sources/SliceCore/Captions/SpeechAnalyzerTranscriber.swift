//
//  SpeechAnalyzerTranscriber.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/3/26.
//

import AVFoundation
import Foundation
import Speech

/// Apple's on-device SpeechAnalyzer and SpeechTranscriber (macOS 26 and later).
@available(macOS 26.0, *)
enum SpeechAnalyzerTranscriber {
    static func supportedLocale(for locale: Locale) async -> Locale? {
        guard SpeechTranscriber.isAvailable else { return nil }
        return await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    }

    static func isInstalled(_ locale: Locale) async -> Bool {
        await SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }

    static func transcribe(audio url: URL, locale: Locale, levels: SpeechLevels?,
                           stage: @escaping @Sendable (TranscriptionStage) -> Void) async throws -> Transcript {
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: [.audioTimeRange, .transcriptionConfidence])
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            let progress = install.progress
            let watcher = Task {
                while !Task.isCancelled {
                    stage(.installingAssets(progress.isIndeterminate ? nil : progress.fractionCompleted))
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            defer { watcher.cancel() }
            try await install.downloadAndInstall()
        }
        try Task.checkCancellation()

        let file = try AVAudioFile(forReading: url)
        let total = Double(file.length) / file.processingFormat.sampleRate
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        stage(.transcribing(0))

        let collector = Task { () throws -> [WordTiming.Piece] in
            var pieces: [WordTiming.Piece] = []
            for try await result in transcriber.results {
                pieces += Self.pieces(from: result.text)
                if let last = pieces.last, total > 0 { stage(.transcribing(min(last.end / total, 0.99))) }
            }
            return pieces
        }
        try await withTaskCancellationHandler {
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        } onCancel: {
            collector.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
        let pieces = try await collector.value
        try Task.checkCancellation()
        stage(.transcribing(1))
        return Transcript(locale: locale.identifier, words: WordTiming.words(fromSegments: pieces, levels: levels),
                          engine: TranscriptionBackend.speechAnalyzer.rawValue)
    }

    static func pieces(from text: AttributedString) -> [WordTiming.Piece] {
        text.runs.compactMap { run in
            guard let range = run.audioTimeRange else { return nil }
            return WordTiming.Piece(text: String(text[run.range].characters), start: range.start.seconds,
                                    end: range.end.seconds, confidence: run.transcriptionConfidence)
        }
    }
}
