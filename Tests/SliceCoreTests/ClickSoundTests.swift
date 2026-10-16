//
//  ClickSoundTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/8/26.
//

import AVFoundation
import CoreImage
@testable import SliceCore
import XCTest

final class ClickSoundTests: XCTestCase {
    func testBundledSoundsAreShortAndStartOnTheClick() async throws {
        XCTAssertNil(ClickSound.none.url)
        for sound in ClickSound.allCases where sound != .none {
            let url = try XCTUnwrap(sound.url, "\(sound) is bundled")
            let summary = try XCTUnwrap(AudioAnalysis.summarize(url))
            XCTAssertLessThan(summary.duration, 0.3, "\(sound) is trimmed")
            let file = try AVAudioFile(forReading: url)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 480))
            try file.read(into: buffer, frameCount: 480)
            let peak = (0 ..< Int(buffer.frameLength)).map { abs(buffer.floatChannelData![0][$0]) }.max() ?? 0
            XCTAssertGreaterThan(peak, 0.1, "\(sound) starts within 10 ms")
        }
    }

    func testPressDipsAndEasesBackWithoutOvershoot() {
        var s = CursorSettings()
        XCTAssertEqual(s.pressScale(ages: [0.05]), 1, "off by default")
        s.clickPress = true
        s.clickPressScale = 0.7
        s.clickPressDuration = 0.4
        XCTAssertEqual(s.pressScale(ages: []), 1)
        XCTAssertEqual(s.pressScale(ages: [0]), 1, accuracy: 1e-9)
        XCTAssertEqual(s.pressScale(ages: [0.1]), 0.7, accuracy: 1e-9, "deepest a quarter of the way through")
        XCTAssertEqual(s.pressScale(ages: [0.4]), 1, "back to size once it's over")
        for i in 0 ... 100 {
            let v = s.pressScale(ages: [0.4 * Double(i) / 100])
            XCTAssertTrue((0.7 - 1e-9 ... 1 + 1e-9).contains(v), "stays between the press and full size at step \(i)")
        }
        XCTAssertEqual(s.pressScale(ages: [0.35, 0.1]), 0.7, accuracy: 1e-9, "overlapping clicks take the deepest press")
        s.clickPressScale = 1.25
        XCTAssertEqual(s.pressScale(ages: [0.1]), 1.25, accuracy: 1e-9, "above 100% it grows")
    }

    func testSettingsRoundTripAndOldProjectsOpen() throws {
        var s = CursorSettings()
        s.clickSound = .deathAdder
        s.clickSoundVolume = 0.3
        s.clickPress = true
        s.clickPressScale = 0.6
        s.clickPressDuration = 0.5
        XCTAssertEqual(try JSONDecoder().decode(CursorSettings.self, from: JSONEncoder().encode(s)), s)
        let old = try JSONDecoder().decode(CursorSettings.self, from: Data(#"{"visible":true,"clickSound":"someNewMouse"}"#.utf8))
        XCTAssertEqual(old.clickSound, .none, "a sound from a newer version falls back")
        XCTAssertFalse(old.clickPress)
    }

    func testPressShrinksTheDrawnPointer() throws {
        let points = CGSize(width: 1512, height: 982), out = CGSize(width: 1920, height: 1080)
        var p = Project(name: "Press")
        p.clips = [Clip(screenFile: "s.mov", cursorFile: "c.json", duration: 4, screenPixelSize: CGSize(width: 3024, height: 1964),
                        captureRect: CGRect(origin: .zero, size: points), cursorInVideo: false)]
        p.cursor.style = .dot
        p.cursor.smoothing = 0
        p.cursor.motionBlur = 0
        let log = CursorLog(samples: [.init(t: 0, x: 0.5, y: 0.5), .init(t: 4, x: 0.5, y: 0.5)], clicks: [.init(t: 2, x: 0.5, y: 0.5)])
        let screen = CIImage(color: CIColor(red: 0.2, green: 0.6, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: 3024, height: 1964))
        func drawn(press: Bool, at t: Double) throws -> Int {
            var project = p
            project.cursor.clickPress = press
            project.cursor.clickPressScale = 0.6
            let scene = RenderScene(project: project, output: out,
                                    cursor: CursorTrack(project: project, logs: [project.clips[0].id: log]))
            let renderer = FrameRenderer()
            let image = renderer.render(scene: scene, time: t, screen: screen, camera: nil)
            let rect = CGRect(x: out.width / 2 - 150, y: out.height / 2 - 150, width: 300, height: 300)
            let cg = try XCTUnwrap(renderer.context.createCGImage(image, from: rect))
            var px = [UInt8](repeating: 0, count: 300 * 300 * 4)
            let ctx = CGContext(data: &px, width: 300, height: 300, bitsPerComponent: 8, bytesPerRow: 1200,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 300, height: 300))
            return stride(from: 0, to: px.count, by: 4).filter { px[$0 + 1] < 120 || px[$0] > 90 }.count
        }
        let normal = try drawn(press: false, at: 2.075)
        let pressed = try drawn(press: true, at: 2.075)
        XCTAssertGreaterThan(normal, 200)
        XCTAssertLessThan(Double(pressed), Double(normal) * 0.5, "about 0.6² of the area at the deepest point")
        XCTAssertEqual(try drawn(press: true, at: 1.5), normal, "untouched before the click")
        XCTAssertEqual(try drawn(press: true, at: 2.5), normal, "back to size after it")
    }

    func testClickSoundsAreExportedAtEachClick() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("click-sound-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (bundle, empty) = try ProjectBundle.create(name: "Clicks", in: dir)
        var project = empty
        let id = UUID()
        let (clipDir, rel) = try bundle.makeClipFolder(id: id)
        try await ExportTests.makeMovie(url: clipDir.appendingPathComponent("screen.mov"),
                                        image: RenderTests.fakeScreen(size: CGSize(width: 640, height: 400)), duration: 3)
        project.clips = [Clip(id: id, screenFile: "\(rel)/screen.mov", duration: 3,
                              screenPixelSize: CGSize(width: 640, height: 400), captureRect: .zero)]
        project.export.resolution = .p1080
        project.export.fps = 30
        project.cursor.clickSound = .magicMouse
        project.cursor.clickSoundVolume = 1
        let log = CursorLog(samples: [.init(t: 0, x: 0.5, y: 0.5)],
                            clicks: [.init(t: 0.5, x: 0.5, y: 0.5), .init(t: 2, x: 0.5, y: 0.5), .init(t: 2.08, x: 0.5, y: 0.5)])
        let cursor = CursorTrack(project: project, logs: [id: log])
        let out = dir.appendingPathComponent("out.mp4")
        try await Exporter.export(project: project, bundle: bundle, cursor: cursor, to: out, progress: { _ in })

        let levels = try await MusicTests.peaks(of: AVURLAsset(url: out), every: 0.05)
        func peak(_ a: Double, _ b: Double) -> Float { levels[Int(a / 0.05) ..< min(Int(b / 0.05), levels.count)].max() ?? 0 }
        XCTAssertGreaterThan(peak(0.45, 0.65), 0.2, "first click is heard")
        XCTAssertGreaterThan(peak(1.95, 2.3), 0.2, "double click is heard")
        XCTAssertLessThan(peak(0.9, 1.8), 0.01, "silent between clicks")

        project.cursor.clickSound = .none
        try await Exporter.export(project: project, bundle: bundle, cursor: cursor, to: out, progress: { _ in })
        let tracks = try await AVURLAsset(url: out).loadTracks(withMediaType: .audio)
        XCTAssertTrue(tracks.isEmpty)
    }
}
