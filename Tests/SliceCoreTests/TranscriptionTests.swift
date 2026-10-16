//
//  TranscriptionTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/16/26.
//

import AVFoundation
import CryptoKit
@testable import SliceCore
import XCTest

final class TranscriptionTests: XCTestCase {
    /// Levels every 10 ms: quiet, except where `speech` says.
    private func levels(duration: Double, speech: [ClosedRange<Double>]) -> SpeechLevels {
        let frames = (0 ..< Int(duration * 100)).map { i -> Double in
            let t = Double(i) / 100
            return speech.contains { $0.contains(t) } ? -20 : -80
        }
        return SpeechLevels(levels: frames, frame: 0.01, threshold: -50)
    }

    func testTokensJoinIntoWordsWithTheirOwnTimes() {
        let tokens = [
            WordTiming.Piece(text: " Hel", start: 0.08, end: 0.24, confidence: 0.9),
            WordTiming.Piece(text: "lo", start: 0.24, end: 0.32, confidence: 0.7),
            WordTiming.Piece(text: ",", start: 0.32, end: 0.40, confidence: 1),
            WordTiming.Piece(text: " world", start: 0.56, end: 0.88, confidence: 0.6),
            WordTiming.Piece(text: ".", start: 0.88, end: 0.96, confidence: 1),
        ]
        let words = WordTiming.words(fromTokens: tokens)
        XCTAssertEqual(words.map(\.text), ["Hello,", "world."])
        XCTAssertEqual(words[0].start, 0.08, accuracy: 1e-9)
        XCTAssertEqual(words[0].end, 0.40, accuracy: 1e-9)
        XCTAssertEqual(words[1].start, 0.56, accuracy: 1e-9)
        XCTAssertEqual(words[1].end, 0.96, accuracy: 1e-9)
        XCTAssertEqual(words[0].confidence ?? 0, (0.9 + 0.7 + 1) / 3, accuracy: 1e-9)
    }

    func testSegmentIsSplitInTheGapBetweenItsWords() {
        // "hi" from 0.5 to 0.8 s, "everybody" from 0.9 to 1.5 s, reported as one segment stretched from 0.4 to 1.6 s.
        let lv = levels(duration: 2, speech: [0.5 ... 0.8, 0.9 ... 1.5])
        let words = WordTiming.words(fromSegments: [WordTiming.Piece(text: "hi everybody", start: 0.4, end: 1.6)], levels: lv)
        XCTAssertEqual(words.map(\.text), ["hi", "everybody"])
        XCTAssertGreaterThanOrEqual(words[0].start, 0.45)
        XCTAssertEqual(words[0].end, 0.85, accuracy: 0.06)
        XCTAssertEqual(words[1].start, 0.88, accuracy: 0.06)
        XCTAssertLessThanOrEqual(words[1].end, 1.6)
    }

    func testTimesStayInsideWhatTheRecogniserReported() {
        let lv = levels(duration: 3, speech: [0 ... 3])
        let seg = WordTiming.Piece(text: "one two three four", start: 1, end: 2, confidence: 0.8)
        for words in [WordTiming.words(fromSegments: [seg], levels: lv), WordTiming.words(fromSegments: [seg], levels: nil)] {
            XCTAssertEqual(words.count, 4)
            for w in words {
                XCTAssertGreaterThanOrEqual(w.start, 1)
                XCTAssertLessThanOrEqual(w.end, 2)
                XCTAssertLessThan(w.start, w.end)
                XCTAssertEqual(w.confidence, 0.8)
            }
            for (a, b) in zip(words, words.dropFirst()) { XCTAssertLessThanOrEqual(a.end, b.start + 1e-9) }
        }
    }

    func testWordsAreTrimmedToTheirSpeech() {
        // The recogniser stretched the first word back over two seconds of silence.
        let lv = levels(duration: 3, speech: [2.2 ... 2.5])
        let words = WordTiming.words(fromSegments: [WordTiming.Piece(text: "Okay", start: 0, end: 2.6)], levels: lv)
        XCTAssertEqual(words.first?.start ?? 0, 2.17, accuracy: 0.03)
        XCTAssertEqual(words.first?.end ?? 0, 2.56, accuracy: 0.03)
    }

    func testTidyJoinsPunctuationAndEndsOverlaps() {
        let words = WordTiming.tidy([Word(text: "b", start: 1, end: 1.6), Word(text: "a", start: 0, end: 1.2), Word(text: "?", start: 1.6, end: 1.7)])
        XCTAssertEqual(words.map(\.text), ["a", "b?"])
        XCTAssertEqual(words[0].end, 1, accuracy: 1e-9)
        XCTAssertEqual(words[1].end, 1.7, accuracy: 1e-9)
    }

    func testLongRecordingsAreSplitInQuietMoments() {
        let lv = levels(duration: 130, speech: [0 ... 44, 44.5 ... 89, 89.6 ... 130])
        let chunks = SpeechRecognizerTranscriber.chunks(duration: 130, levels: lv)
        XCTAssertEqual(chunks.first?.start, 0)
        XCTAssertEqual(chunks.last?.end ?? 0, 130, accuracy: 1e-9)
        for c in chunks { XCTAssertLessThanOrEqual(c.end - c.start, SpeechRecognizerTranscriber.maxChunk + 1e-9) }
        for (a, b) in zip(chunks, chunks.dropFirst()) { XCTAssertEqual(a.end, b.start) }
        XCTAssertEqual(chunks[0].end, 44.25, accuracy: 0.05)
        XCTAssertEqual(chunks[1].end, 89.3, accuracy: 0.05)
        XCTAssertEqual(SpeechRecognizerTranscriber.chunks(duration: 120, levels: nil).map(\.end), [50, 100, 120])
    }

    func testParakeetDownloadIsPinnedAndComplete() {
        XCTAssertEqual(ParakeetModel.downloadBytes, 632_162_964)
        let paths = Set(ParakeetModel.files.map(\.path))
        XCTAssertEqual(paths.count, ParakeetModel.files.count)
        for bundle in ["Preprocessor", "Encoder", "Decoder", "JointDecisionv3"] {
            XCTAssertTrue(paths.contains("\(bundle).mlmodelc/coremldata.bin"), bundle)
            XCTAssertTrue(paths.contains("\(bundle).mlmodelc/weights/weight.bin"), bundle)
        }
        XCTAssertTrue(paths.contains("parakeet_vocab.json"))
        let url = ParakeetModel.url(for: ParakeetModel.files[0]).absoluteString
        XCTAssertTrue(url.hasPrefix("https://huggingface.co/FluidInference/parakeet-ultra-coreml/resolve/\(ParakeetModel.revision)/"))
        XCTAssertEqual(ParakeetModel.directory.lastPathComponent, "parakeet-ultra")
    }

    func testDownloadedFilesAreCheckedAgainstTheirHashes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("slice-hash-\(UUID().uuidString)")
        try Data("hello\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let blob = ParakeetModel.File("a", 6, .gitBlob("ce013625030ba8dba906f756967f9e9ca394464a"))
        let lfs = ParakeetModel.File("b", 6, .sha256("5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"))
        XCTAssertTrue(try ParakeetModel.verified(blob, at: url, sizeOnly: false))
        XCTAssertTrue(try ParakeetModel.verified(lfs, at: url, sizeOnly: false))
        XCTAssertFalse(try ParakeetModel.verified(ParakeetModel.File("c", 6, .sha256(String(repeating: "0", count: 64))), at: url, sizeOnly: false))
        XCTAssertFalse(try ParakeetModel.verified(ParakeetModel.File("d", 7, .gitBlob("ce013625030ba8dba906f756967f9e9ca394464a")), at: url, sizeOnly: true))
    }

    func testOldTranscriptsStillOpen() throws {
        let json = #"{"locale":"en_GB","words":[{"text":"Hi","start":0.1,"end":0.4,"hidden":true}]}"#
        let t = try JSONDecoder().decode(Transcript.self, from: Data(json.utf8))
        XCTAssertEqual(t.words, [{ var w = Word(text: "Hi", start: 0.1, end: 0.4); w.hidden = true; return w }()])
        XCTAssertNil(t.engine)
        let round = try JSONDecoder().decode(Transcript.self, from: JSONEncoder().encode(
            Transcript(locale: "en", words: [Word(text: "a", start: 0, end: 1, confidence: 0.5)], engine: "parakeet-ultra")))
        XCTAssertEqual(round.words.first?.confidence, 0.5)
        XCTAssertEqual(round.engine, "parakeet-ultra")
    }

    func testParakeetRefusesLanguagesItWasNotTrainedOn() async {
        do {
            _ = try await ParakeetEngine.shared.transcribe(audio: URL(fileURLWithPath: "/nonexistent.m4a"), locale: Locale(identifier: "ja-JP")) { _ in }
            XCTFail("expected an unsupported-language error")
        } catch {
            guard case .unsupportedLanguage(.parakeet, _)? = error as? TranscriptionError else { return XCTFail("\(error)") }
        }
    }

    /// Downloads Parakeet Ultra (632 MB) into SLICE_PARAKEET_MODEL_DIR and transcribes speech made with `say`.
    /// Run with SLICE_PARAKEET_E2E=1 SLICE_PARAKEET_MODEL_DIR=/tmp/slice-parakeet.
    func testParakeetTranscribesSpeechWithWordTimes() async throws {
        guard ProcessInfo.processInfo.environment["SLICE_PARAKEET_E2E"] == "1",
              ProcessInfo.processInfo.environment["SLICE_PARAKEET_MODEL_DIR"] != nil else { throw XCTSkip("SLICE_PARAKEET_E2E not set") }
        if !ParakeetModel.isInstalled { try await ParakeetModel.install { _ in } }
        XCTAssertTrue(ParakeetModel.isInstalled)
        let audio = try Self.say("Welcome to the demo. This part is a mistake and should go. Here is the real content.")
        defer { try? FileManager.default.removeItem(at: audio) }
        let start = Date()
        let t = try await ParakeetEngine.shared.transcribe(audio: audio, locale: Locale(identifier: "en-GB")) { _ in }
        let again = Date()
        _ = try await ParakeetEngine.shared.transcribe(audio: audio, locale: Locale(identifier: "en-GB")) { _ in }
        print("PARAKEET (\(String(format: "%.1f", again.timeIntervalSince(start)))s first, \(String(format: "%.1f", Date().timeIntervalSince(again)))s again):")
        print(t.words.map { String(format: "%@[%.2f-%.2f %.2f]", $0.text, $0.start, $0.end, $0.confidence ?? -1) }.joined(separator: " "))
        let heard = t.words.map(\.text).joined(separator: " ").lowercased()
        XCTAssertTrue(heard.contains("welcome"))
        XCTAssertTrue(heard.contains("mistake"))
        XCTAssertEqual(t.engine, TranscriptionBackend.parakeetUltra.rawValue)
        for w in t.words { XCTAssertLessThan(w.start, w.end) }
        for (a, b) in zip(t.words, t.words.dropFirst()) { XCTAssertLessThanOrEqual(a.end, b.start + 1e-6) }
        let duration = try await AVURLAsset(url: audio).load(.duration).seconds
        XCTAssertLessThanOrEqual(t.words.last?.end ?? 0, duration + 0.1)
        let loaded = await ParakeetEngine.shared.isLoaded
        XCTAssertTrue(loaded)
    }

    static func say(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("slice-say-\(UUID().uuidString).m4a")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", url.path, "--data-format=aac", text]
        try say.run()
        say.waitUntilExit()
        return url
    }
}
