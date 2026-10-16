//
//  AppleSpeechEngine.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/16/26.
//

import Foundation
import Speech

/// Apple's built-in speech recognition, always on this Mac: SpeechAnalyzer on macOS 26 and later, on-device
/// SFSpeechRecognizer before that or for a language SpeechAnalyzer doesn't have.
public struct AppleSpeechEngine: TranscriptionEngine {
    public enum Availability: Equatable, Sendable {
        /// Ready with this recogniser; `needsAssets` when Apple still has to download its language model.
        case available(TranscriptionBackend, needsAssets: Bool)
        case needsPermission(TranscriptionBackend)
        case unavailable(String)
    }

    public init() {}

    public var kind: TranscriptionEngineKind { .appleSpeech }

    public func transcribe(audio url: URL, locale: Locale,
                           stage: @escaping @Sendable (TranscriptionStage) -> Void) async throws -> Transcript {
        stage(.preparing("Reading the recording…"))
        let levels = SpeechLevels(url: url)
        try Task.checkCancellation()
        if #available(macOS 26.0, *), let supported = await SpeechAnalyzerTranscriber.supportedLocale(for: locale) {
            return try await SpeechAnalyzerTranscriber.transcribe(audio: url, locale: supported, levels: levels, stage: stage)
        }
        return try await SpeechRecognizerTranscriber.transcribe(audio: url, locale: locale, levels: levels, stage: stage)
    }

    public static func availability(for locale: Locale) async -> Availability {
        if #available(macOS 26.0, *), let supported = await SpeechAnalyzerTranscriber.supportedLocale(for: locale) {
            return .available(.speechAnalyzer, needsAssets: !(await SpeechAnalyzerTranscriber.isInstalled(supported)))
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            return .unavailable("Apple Speech doesn't support \(locale.languageName).")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            return .unavailable("Apple Speech can't recognise \(locale.languageName) on this Mac without sending audio to Apple, so Slice won't use it.")
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .available(.speechRecognizer, needsAssets: false)
        case .notDetermined: return .needsPermission(.speechRecognizer)
        default: return .unavailable(TranscriptionError.notAuthorized.errorDescription ?? "")
        }
    }
}
