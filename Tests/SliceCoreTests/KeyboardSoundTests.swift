//
//  KeyboardSoundTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/7/26.
//

import AVFoundation
@testable import SliceCore
import XCTest

final class KeyboardSoundTests: XCTestCase {
    func testPacksAreBundledShortAndStartOnThePress() throws {
        XCTAssertTrue(KeyboardSound.none.files.isEmpty)
        for sound in KeyboardSound.allCases where sound != .none {
            let files = sound.files
            let names = files.map { $0.deletingPathExtension().lastPathComponent }
            XCTAssertGreaterThanOrEqual(names.filter { $0.hasPrefix("key") }.count, 3, "\(sound) has key variants")
            XCTAssertTrue(names.contains("space") && names.contains("enter"), "\(sound) has its big keys")
            for url in files {
                let file = try AVAudioFile(forReading: url)
                XCTAssertEqual(file.processingFormat.sampleRate, 48000)
                XCTAssertLessThan(Double(file.length) / 48000, 0.33, "\(url.lastPathComponent) is trimmed")
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 480))
                try file.read(into: buffer, frameCount: 480)
                let peak = (0 ..< Int(buffer.frameLength)).map { abs(buffer.floatChannelData![0][$0]) }.max() ?? 0
                XCTAssertGreaterThan(peak, 0.03, "\(sound) \(url.lastPathComponent) is heard within 10 ms")
            }
        }
    }

    func testPicksVaryPlainKeysAndUseTheBigKeysOwnSounds() {
        let sound = KeyboardSound.cherryBlue
        let names = sound.files.map { $0.deletingPathExtension().lastPathComponent }
        let kinds: [KeyHit.Kind] = Array(repeating: .key, count: 40) + [.space, .enter, .backspace, .modifier]
        let picks = sound.picks(for: kinds)
        XCTAssertEqual(picks.count, kinds.count)
        let keys = picks.prefix(40)
        XCTAssertTrue(keys.allSatisfy { names[$0].hasPrefix("key") })
        XCTAssertTrue(zip(keys, keys.dropFirst()).allSatisfy { $0 != $1 }, "never the same key sound twice running")
        XCTAssertGreaterThan(Set(keys).count, 3, "uses the variants")
        XCTAssertEqual(picks[40 ..< 43].map { names[$0] }, ["space", "enter", "backspace"])
        XCTAssertTrue(names[picks[43]].hasPrefix("key"), "modifiers sound like a key")
        XCTAssertEqual(sound.picks(for: kinds), picks, "the same presses get the same sounds")
        let apex = KeyboardSound.apexPro
        XCTAssertTrue(apex.files[apex.picks(for: [.backspace])[0]].lastPathComponent.hasPrefix("key"))
        XCTAssertTrue(KeyboardSound.none.picks(for: kinds).isEmpty)
    }

    func testKindsNeverKeepWhichKey() {
        XCTAssertEqual(KeyHit.kind(keyCode: 0), .key, "A")
        XCTAssertEqual(KeyHit.kind(keyCode: 49), .space)
        XCTAssertEqual(KeyHit.kind(keyCode: 36), .enter)
        XCTAssertEqual(KeyHit.kind(keyCode: 51), .backspace)
        XCTAssertEqual(KeyHit.kind(keyCode: 55), .modifier, "⌘")
        let json = String(decoding: try! JSONEncoder().encode(KeyHit(t: 1, kind: .key)), as: UTF8.self)
        XCTAssertFalse(json.contains("keyCode"))
    }

    func testOldTakesSoundTheirTypingAndShortcuts() throws {
        let log = CursorLog(keys: [KeyPress(t: 2, modifiers: "⌘", key: "K"), KeyPress(t: 3, modifiers: "", key: "↩")],
                            typing: [1, 1.2])
        XCTAssertEqual(log.keyHits.map(\.t), [1, 1.2, 2, 3])
        XCTAssertEqual(log.keyHits.map(\.kind), [.key, .key, .key, .enter])
        let recorded = CursorLog(typing: [1], hits: [KeyHit(t: 1, kind: .space)])
        XCTAssertEqual(recorded.keyHits, [KeyHit(t: 1, kind: .space)], "takes that logged hits use them as they are")
        let decoded = try JSONDecoder().decode(CursorLog.self, from: JSONEncoder().encode(recorded))
        XCTAssertEqual(decoded, recorded)
        let newer = try JSONDecoder().decode(KeyHit.self, from: Data(#"{"t":1,"kind":"someNewKey"}"#.utf8))
        XCTAssertEqual(newer.kind, .key, "a kind from a newer version falls back")
    }

    func testSettingsRoundTripAndOldProjectsOpen() throws {
        var s = KeystrokeSettings()
        s.sound = .holyPanda
        s.soundVolume = 0.3
        XCTAssertEqual(try JSONDecoder().decode(KeystrokeSettings.self, from: JSONEncoder().encode(s)), s)
        let old = try JSONDecoder().decode(KeystrokeSettings.self, from: Data(#"{"visible":true,"sound":"someNewBoard"}"#.utf8))
        XCTAssertEqual(old.sound, .none)
        XCTAssertEqual(old.soundVolume, 0.5)
    }

    func testTypingIsExportedAtEachPressEvenWithShortcutsHidden() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("key-sound-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (bundle, empty) = try ProjectBundle.create(name: "Keys", in: dir)
        var project = empty
        let id = UUID()
        let (clipDir, rel) = try bundle.makeClipFolder(id: id)
        try await ExportTests.makeMovie(url: clipDir.appendingPathComponent("screen.mov"),
                                        image: RenderTests.fakeScreen(size: CGSize(width: 640, height: 400)), duration: 3)
        project.clips = [Clip(id: id, screenFile: "\(rel)/screen.mov", duration: 3,
                              screenPixelSize: CGSize(width: 640, height: 400), captureRect: .zero)]
        project.export.resolution = .p1080
        project.export.fps = 30
        project.keystrokes.visible = false
        project.keystrokes.sound = .cherryBlue
        project.keystrokes.soundVolume = 1
        let burst = (0 ..< 10).map { KeyHit(t: 2 + Double($0) * 0.06, kind: $0 == 4 ? .space : .key) }
        let log = CursorLog(samples: [.init(t: 0, x: 0.5, y: 0.5)], hits: [KeyHit(t: 0.5, kind: .key)] + burst)
        let cursor = CursorTrack(project: project, logs: [id: log])
        let out = dir.appendingPathComponent("out.mp4")
        try await Exporter.export(project: project, bundle: bundle, cursor: cursor, to: out, progress: { _ in })

        let levels = try await MusicTests.peaks(of: AVURLAsset(url: out), every: 0.05)
        func peak(_ a: Double, _ b: Double) -> Float { levels[Int(a / 0.05) ..< min(Int(b / 0.05), levels.count)].max() ?? 0 }
        XCTAssertGreaterThan(peak(0.45, 0.7), 0.2, "the press is heard")
        XCTAssertGreaterThan(peak(1.95, 2.6), 0.2, "the burst is heard")
        XCTAssertLessThan(peak(0.9, 1.8), 0.01, "silent between presses")

        project.keystrokes.sound = .none
        try await Exporter.export(project: project, bundle: bundle, cursor: cursor, to: out, progress: { _ in })
        let tracks = try await AVURLAsset(url: out).loadTracks(withMediaType: .audio)
        XCTAssertTrue(tracks.isEmpty, "with no keyboard picked, nothing is added")
    }
}
