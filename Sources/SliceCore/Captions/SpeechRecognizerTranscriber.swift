//
//  SpeechRecognizerTranscriber.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/16/26.
//

import AVFoundation
import Foundation
import Speech

/// SFSpeechRecognizer, used where SpeechAnalyzer isn't available (macOS 15 to 25, or a language it lacks).
///
/// Only on-device recognition is used: a language the Mac can't recognise locally is refused rather than sent to
/// Apple's servers. The audio goes in pieces of under a minute, each ending in the quietest moment near its end, so
/// no single request runs long and words aren't cut in half.
enum SpeechRecognizerTranscriber {
    static let maxChunk = 50.0
    static let minChunk = 30.0
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    static func recognizer(for locale: Locale) -> SFSpeechRecognizer? {
        guard let r = SFSpeechRecognizer(locale: locale), r.supportsOnDeviceRecognition else { return nil }
        return r
    }

    static func authorize() async -> SFSpeechRecognizerAuthorizationStatus {
        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
    }

    static func transcribe(audio url: URL, locale: Locale, levels: SpeechLevels?,
                           stage: @escaping @Sendable (TranscriptionStage) -> Void) async throws -> Transcript {
        guard let probe = SFSpeechRecognizer(locale: locale) else {
            throw TranscriptionError.unsupportedLanguage(engine: .appleSpeech, language: locale.languageName)
        }
        guard probe.supportsOnDeviceRecognition else { throw TranscriptionError.onDeviceUnavailable(language: locale.languageName) }
        stage(.preparing("Asking for speech recognition permission…"))
        guard await authorize() == .authorized else { throw TranscriptionError.notAuthorized }
        guard probe.isAvailable else { throw TranscriptionError.recognizerUnavailable }
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        probe.queue = queue

        let file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate
        let total = Double(file.length) / rate
        stage(.transcribing(0))
        var pieces: [WordTiming.Piece] = []
        for chunk in chunks(duration: total, levels: levels) {
            try Task.checkCancellation()
            guard let buffer = try read(file, from: chunk.start, to: chunk.end) else { continue }
            let segments = try await recognize(buffer, with: probe)
            pieces += segments.map { s in
                WordTiming.Piece(text: s.substring, start: chunk.start + s.timestamp, end: chunk.start + s.timestamp + s.duration,
                                 confidence: s.confidence > 0 ? Double(s.confidence) : nil)
            }
            stage(.transcribing(min(chunk.end / max(total, 0.001), 1)))
        }
        return Transcript(locale: probe.locale.identifier, words: WordTiming.words(fromSegments: pieces, levels: levels),
                          engine: TranscriptionBackend.speechRecognizer.rawValue)
    }

    /// Stretches of at most `maxChunk` seconds, each ending in the quietest moment of its last 20 seconds.
    static func chunks(duration: Double, levels: SpeechLevels?) -> [TimeSpan] {
        var out: [TimeSpan] = []
        var start = 0.0
        while duration - start > maxChunk {
            var end = start + maxChunk
            if let quiet = levels?.quietest(from: start + minChunk, to: start + maxChunk, near: start + maxChunk) { end = quiet }
            out.append(TimeSpan(start: start, end: end))
            start = end
        }
        if duration - start > 0.05 { out.append(TimeSpan(start: start, end: duration)) }
        return out
    }

    private static func read(_ file: AVAudioFile, from start: Double, to end: Double) throws -> AVAudioPCMBuffer? {
        let rate = file.processingFormat.sampleRate
        let first = AVAudioFramePosition(start * rate), count = AVAudioFrameCount(max((end - start) * rate, 0))
        guard count > 0, let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count),
              let converter = AVAudioConverter(from: file.processingFormat, to: format),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(count) * 16000 / rate) + 1024)
        else { return nil }
        file.framePosition = first
        try file.read(into: input, frameCount: count)
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        return output.frameLength > 0 ? output : nil
    }

    private static func recognize(_ buffer: AVAudioPCMBuffer, with recognizer: SFSpeechRecognizer) async throws -> [SFTranscriptionSegment] {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.append(buffer)
        request.endAudio()

        let box = RecognitionBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<[SFTranscriptionSegment], Error>) in
                box.begin(c)
                box.attach(recognizer.recognitionTask(with: request) { result, error in
                    if let result, result.isFinal {
                        box.finish(.success(result.bestTranscription.segments))
                    } else if let error {
                        box.finish(Self.isNoSpeech(error) ? .success([]) : .failure(error))
                    }
                })
            }
        } onCancel: {
            box.cancel()
        }
    }

    /// The recogniser reports a stretch with no speech in it as an error.
    static func isNoSpeech(_ error: Error) -> Bool {
        let e = error as NSError
        return e.domain == "kAFAssistantErrorDomain" && e.code == 1110
    }

    private final class RecognitionBox: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<[SFTranscriptionSegment], Error>?
        private var task: SFSpeechRecognitionTask?
        private var cancelled = false

        func begin(_ c: CheckedContinuation<[SFTranscriptionSegment], Error>) {
            let wasCancelled = lock.withLock {
                continuation = c
                return cancelled
            }
            if wasCancelled { finish(.failure(CancellationError())) }
        }

        func attach(_ t: SFSpeechRecognitionTask) {
            let wasCancelled = lock.withLock {
                task = t
                return cancelled
            }
            if wasCancelled { t.cancel() }
        }

        func finish(_ result: Result<[SFTranscriptionSegment], Error>) {
            let c = lock.withLock { () -> CheckedContinuation<[SFTranscriptionSegment], Error>? in
                defer { continuation = nil }
                return continuation
            }
            c?.resume(with: result)
        }

        func cancel() {
            let t = lock.withLock {
                cancelled = true
                return task
            }
            t?.cancel()
            finish(.failure(CancellationError()))
        }
    }
}
