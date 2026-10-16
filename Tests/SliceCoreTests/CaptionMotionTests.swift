//
//  CaptionMotionTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/10/26.
//

import CoreImage
import ImageIO
@testable import SliceCore
import UniformTypeIdentifiers
import XCTest

final class CaptionMotionTests: XCTestCase {
    func caption(_ text: String, at start: Double, end: Double? = nil) -> Caption {
        let words = text.split(separator: " ").enumerated().map { i, w in
            Caption.TimedWord(text: String(w), start: start + Double(i) * 0.3, end: start + Double(i) * 0.3 + 0.25)
        }
        return Caption(start: start, end: end ?? (words.last!.end + 0.3), words: words)
    }

    // MARK: - Motion

    func testComesIntoFocusHoldsAndBlursAway() throws {
        let caps = [caption("So this is the dashboard", at: 1, end: 3)]
        XCTAssertNil(CaptionMotion.state(at: 0.99, in: caps))
        let start = try XCTUnwrap(CaptionMotion.state(at: 1.01, in: caps))
        XCTAssertGreaterThan(start.blur, 0.8)
        XCTAssertLessThan(start.opacity, 0.2)
        XCTAssertLessThan(start.scale, 1)
        XCTAssertGreaterThan(start.drop, 0)
        let held = try XCTUnwrap(CaptionMotion.state(at: 2, in: caps))
        XCTAssertEqual(held.blur, 0)
        XCTAssertEqual(held.opacity, 1)
        XCTAssertEqual(held.scale, 1)
        XCTAssertEqual(held.drop, 0)
        let leaving = try XCTUnwrap(CaptionMotion.state(at: 3.1, in: caps))
        XCTAssertGreaterThan(leaving.blur, 0.3)
        XCTAssertLessThan(leaving.opacity, 1)
        XCTAssertNil(CaptionMotion.state(at: 3 + CaptionMotion.outDuration + 0.01, in: caps))
    }

    func testNextCaptionTakesOverThePlate() throws {
        let caps = [caption("So this is", at: 1, end: 2.5), caption("the dashboard where it all happens", at: 2.5)]
        XCTAssertEqual(CaptionMotion.state(at: 2.49, in: caps), CaptionMotion.State(index: 0))
        let mid = try XCTUnwrap(CaptionMotion.state(at: 2.6, in: caps))
        XCTAssertEqual(mid.index, 1)
        XCTAssertEqual(mid.previous, 0)
        XCTAssertGreaterThan(mid.shape, 0)
        XCTAssertLessThan(mid.shape, 1)
        XCTAssertGreaterThan(mid.outgoing, 0)
        XCTAssertLessThan(mid.incoming, 1)
        XCTAssertEqual(mid.opacity, 1)
        XCTAssertEqual(mid.blur, 0)
        let after = try XCTUnwrap(CaptionMotion.state(at: 2.5 + CaptionMotion.swapDuration + 0.01, in: caps))
        XCTAssertNil(after.previous)
        XCTAssertEqual(after.shape, 1)
    }

    func testShortGapsAreBridged() throws {
        let caps = [caption("So this is", at: 1, end: 2), caption("the dashboard", at: 2.4)]
        let gap = try XCTUnwrap(CaptionMotion.state(at: 2.2, in: caps))
        XCTAssertEqual(gap.index, 0)
        XCTAssertEqual(gap.opacity, 1)
        XCTAssertEqual(CaptionMotion.state(at: 2.45, in: caps)?.previous, 0)
        let apart = [caption("So this is", at: 1, end: 2), caption("the dashboard", at: 3.5)]
        XCTAssertNil(CaptionMotion.state(at: 3, in: apart))
        XCTAssertNil(CaptionMotion.state(at: 3.55, in: apart)?.previous)
        XCTAssertGreaterThan(try XCTUnwrap(CaptionMotion.state(at: 3.55, in: apart)).blur, 0.2)
    }

    func testWordsComeIntoFocusAsTheyreSpoken() {
        let w = Caption.TimedWord(text: "dashboard", start: 2, end: 2.4)
        XCTAssertEqual(CaptionMotion.focus(of: w, at: 1.9), 0)
        XCTAssertGreaterThan(CaptionMotion.focus(of: w, at: 2.05), 0)
        XCTAssertLessThan(CaptionMotion.focus(of: w, at: 2.05), 1)
        XCTAssertEqual(CaptionMotion.focus(of: w, at: 2.3), 1)
    }

    // MARK: - Layout

    func testWordPiecesTileTheText() throws {
        let c = caption("So this is the dashboard and here you can see every citation we tracked this week", at: 0)
        let layout = try XCTUnwrap(FrameRenderer.makeCaptionLayout(c, fontSize: 48, maxWidth: 900))
        let pieces = layout.words.flatMap { $0 }
        XCTAssertEqual(layout.words.count, c.words.count)
        XCTAssertTrue(layout.words.allSatisfy { !$0.isEmpty })
        XCTAssertGreaterThan(Set(pieces.map(\.minY)).count, 1)
        let extent = layout.text.extent
        XCTAssertEqual(pieces.reduce(0) { $0 + $1.width * $1.height }, extent.width * extent.height, accuracy: extent.width * 2)
        for (i, a) in pieces.enumerated() {
            for b in pieces[(i + 1)...] { XCTAssertLessThan(a.intersection(b).width * a.intersection(b).height, 2) }
        }
    }

    // MARK: - Shortcuts stand clear

    let out = CGSize(width: 1920, height: 1080)

    func scene(keys: [KeyPress], _ edit: (inout Project) -> Void = { _ in }) -> RenderScene {
        var p = Project(name: "Captions")
        p.clips = [Clip(screenFile: "s.mov", cursorFile: "c.json", duration: 12, screenPixelSize: CGSize(width: 3024, height: 1964),
                        captureRect: CGRect(x: 0, y: 0, width: 1512, height: 982))]
        p.cursor.visible = false
        p.cursor.clickEffect = .none
        p.subtitles.burnIn = true
        edit(&p)
        let log = CursorLog(samples: [.init(t: 0, x: 0.5, y: 0.5)], keys: keys)
        return RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [p.clips[0].id: log]))
    }

    var captions: [Caption] {
        [caption("So this is the dashboard", at: 1, end: 2.6),
         caption("and here you can see every single citation we tracked over the whole of this week", at: 2.6),
         caption("Nice", at: 9.2, end: 10)]
    }

    var presses: [KeyPress] {
        stride(from: 0.4, to: 10.5, by: 0.7).map { KeyPress(t: $0, modifiers: "⌘", key: "K") }
    }

    func testShortcutsNeverSitOnTheCaption() throws {
        let cases: [(SubtitleSettings.Position, KeystrokeSettings.Position, Double)] = [(.bottom, .bottom, 0.04), (.top, .top, 0.04),
                                                                                         (.bottom, .bottom, 0.08)]
        for (subtitles, keys, size) in cases {
            let s = scene(keys: presses) {
                $0.subtitles.position = subtitles
                $0.keystrokes.position = keys
                $0.keystrokes.size = size
            }
            let renderer = FrameRenderer()
            let settings = s.project.keystrokes
            let fontSize = (min(out.width, out.height) * settings.size).rounded()
            var lifted = false
            var t = 0.0
            while t < 11 {
                defer { t += 1.0 / 60 }
                let clearance = renderer.captionClearance(at: t, captions: captions, settings: s.project.subtitles, camera: nil, output: out)
                lifted = lifted || clearance > 0
                guard let placed = renderer.captionPlacement(at: t, captions: captions, settings: s.project.subtitles,
                                                             camera: nil, output: out),
                      placed.state.opacity > 0.05 else { continue }
                for state in s.keystrokes.states(at: t) where state.opacity > 0.05 {
                    let cap = try XCTUnwrap(FrameRenderer.keycapImage(state.label, count: state.count, fontSize: fontSize))
                    let size = cap.extent.insetBy(dx: FrameRenderer.keycapMargin(fontSize), dy: FrameRenderer.keycapMargin(fontSize)).size
                    var drop = state.drop * size.height
                    if clearance > 0, keys == .bottom { drop = min(drop, out.height * 0.06 * 0.3 * 0.8) }
                    let rect = FrameRenderer.keycapRect(size: size, position: settings.position, clearance: clearance, camera: nil, output: out)
                        .offsetBy(dx: 0, dy: drop)
                    XCTAssertFalse(rect.intersects(placed.plate), "keys on the caption at \(t)s (\(subtitles))")
                }
            }
            XCTAssertTrue(lifted)
        }
    }

    func testShortcutsStayPutAtTheOtherEdge() {
        let s = scene(keys: presses) {
            $0.subtitles.position = .top
            $0.keystrokes.position = .bottom
        }
        let renderer = FrameRenderer()
        let screen = CIImage(color: CIColor(red: 0.62, green: 0.45, blue: 0.9)).cropped(to: CGRect(x: 0, y: 0, width: 3024, height: 1964))
        let bottom = CGRect(x: 0, y: 0, width: out.width, height: out.height * 0.3)
        let with = renderer.render(scene: s, time: 1.5, screen: screen, camera: nil, options: .init(captions: captions))
        let without = renderer.render(scene: s, time: 1.5, screen: screen, camera: nil)
        XCTAssertEqual(changedPixels(with, without, in: bottom, renderer: renderer), 0)
        let shared = scene(keys: presses)
        XCTAssertGreaterThan(changedPixels(renderer.render(scene: shared, time: 1.5, screen: screen, camera: nil, options: .init(captions: captions)),
                                           renderer.render(scene: shared, time: 1.5, screen: screen, camera: nil), in: bottom,
                                           renderer: renderer), 1000)
    }

    func changedPixels(_ a: CIImage, _ b: CIImage, in rect: CGRect, renderer: FrameRenderer) -> Int {
        func pixels(_ image: CIImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: Int(rect.width) * Int(rect.height) * 4)
            renderer.context.render(image, toBitmap: &data, rowBytes: Int(rect.width) * 4, bounds: rect, format: .RGBA8,
                                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return data
        }
        let pa = pixels(a), pb = pixels(b)
        var changed = 0
        for i in stride(from: 0, to: pa.count, by: 4) where (0 ..< 3).contains(where: { abs(Int(pa[i + $0]) - Int(pb[i + $0])) > 6 }) {
            changed += 1
        }
        return changed
    }

    func testLongCaptionStaysAtTheBottomBesideTheCamera() throws {
        let s = scene(keys: [])
        let renderer = FrameRenderer()
        let long = [caption("with one thing, no one can ever understand how you feel when it happens to you", at: 0, end: 5)]
        let camera = CGRect(x: 1540, y: 740, width: 340, height: 300)
        let placed = try XCTUnwrap(renderer.captionPlacement(at: 2, captions: long, settings: s.project.subtitles,
                                                             camera: camera, output: out))
        XCTAssertFalse(placed.plate.intersects(camera))
        XCTAssertEqual(placed.plate.maxY, out.height - out.height * 0.06, accuracy: 2)
    }

    /// Writes frames for eyeballing: CAPTION_FRAMES=/some/dir swift test --filter testDumpCaptionFrames
    func testDumpCaptionFrames() throws {
        guard let dir = ProcessInfo.processInfo.environment["CAPTION_FRAMES"] else { throw XCTSkip("set CAPTION_FRAMES") }
        let s = scene(keys: presses)
        let renderer = FrameRenderer()
        let screen = RenderTests.fakeScreen(size: CGSize(width: 3024, height: 1964))
        var t = 0.7
        while t < 4.2 {
            let image = renderer.render(scene: s, time: t, screen: screen, camera: nil, options: .init(captions: captions))
            let cg = try XCTUnwrap(renderer.context.createCGImage(image, from: CGRect(x: 160, y: 0, width: 1600, height: 520)))
            let url = URL(fileURLWithPath: dir).appendingPathComponent(String(format: "c_%06.3f.png", t))
            let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(dest, cg, nil)
            CGImageDestinationFinalize(dest)
            t += 1.0 / 20
        }
    }
}
