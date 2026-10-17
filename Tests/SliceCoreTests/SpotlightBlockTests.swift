//
//  SpotlightBlockTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/17/26.
//

import CoreImage
@testable import SliceCore
import XCTest

final class SpotlightBlockTests: XCTestCase {
    let out = CGSize(width: 1920, height: 1080)

    func project(_ blocks: [SpotlightBlock], clicks: Bool = false) -> Project {
        var p = Project(name: "Spotlights")
        p.clips = [Clip(screenFile: "s.mov", cursorFile: "c.json", duration: 10, screenPixelSize: CGSize(width: 3024, height: 1964),
                        captureRect: CGRect(x: 0, y: 0, width: 1512, height: 982))]
        p.cursor.visible = false
        p.cursor.spotlight.enabled = clicks
        p.spotlights = blocks
        return p
    }

    func scene(_ p: Project) -> RenderScene {
        let log = CursorLog(samples: [.init(t: 0, x: 0.1, y: 0.1), .init(t: 10, x: 0.9, y: 0.9)],
                            clicks: [.init(t: 2, x: 0.2, y: 0.3), .init(t: 3.6, x: 0.2, y: 0.3)])
        return RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [p.clips[0].id: log]))
    }

    func testFadesInsideItsOwnEdges() throws {
        let s = scene(project([SpotlightBlock(start: 4, end: 6, center: CGPoint(x: 0.7, y: 0.6))]))
        XCTAssertNil(s.spotlight(at: 3.99))
        XCTAssertNil(s.spotlight(at: 6))
        XCTAssertLessThan(try XCTUnwrap(s.spotlight(at: 4.05)).amount, 0.1)
        let mid = try XCTUnwrap(s.spotlight(at: 5))
        XCTAssertEqual(mid.amount, 1, accuracy: 1e-9)
        XCTAssertEqual(mid.center, CGPoint(x: 0.7, y: 0.6))
        XCTAssertLessThan(try XCTUnwrap(s.spotlight(at: 5.97)).amount, 0.05)
    }

    func testFollowsThePointer() throws {
        let s = scene(project([SpotlightBlock(start: 1, end: 9, followsPointer: true)]))
        let a = try XCTUnwrap(s.spotlight(at: 3)).center, b = try XCTUnwrap(s.spotlight(at: 7)).center
        XCTAssertGreaterThan(b.x - a.x, 0.2, "it moves with the pointer")
        XCTAssertEqual(a.x, try XCTUnwrap(s.cursor.position(at: 3)).x, accuracy: 0.02)
    }

    func testHandsOverSmoothlyWithClickSpotlights() throws {
        let s = scene(project([SpotlightBlock(start: 2.3, end: 3.8, center: CGPoint(x: 0.8, y: 0.8), mode: .blur)], clicks: true))
        var last: SpotlightState?
        var t = 1.7
        while t < 5.5 {
            let now = s.spotlight(at: t)
            if let a = last, let b = now {
                XCTAssertLessThan(abs(b.amount - a.amount), 0.03, "amount jumps at \(t)")
                XCTAssertLessThan(abs(b.blur - a.blur), 0.03, "look jumps at \(t)")
                XCTAssertLessThan(hypot(b.center.x - a.center.x, b.center.y - a.center.y), 0.02, "centre jumps at \(t)")
            } else if let state = last ?? now {
                XCTAssertLessThan(state.amount, 0.03, "appears or vanishes abruptly at \(t)")
            }
            last = now
            t += 1 / 240
        }
        XCTAssertEqual(try XCTUnwrap(s.spotlight(at: 3)).center.x, 0.8, accuracy: 1e-6, "the block wins while it's in")
    }

    /// Blocks starting, holding and ending around the clicks (at 2 and 3.6) every way they can, and the circle never snaps.
    func testNeverSnapsWhereverBlocksMeetClicks() {
        let spans: [(Double, Double)] = [(1.5, 2.4), (2.3, 3.8), (2.6, 3.3), (3.1, 3.7), (3.5, 4.4), (1, 6), (3.62, 4.4), (2.9, 3.62)]
        for (start, end) in spans {
            for follows in [false, true] {
                let block = SpotlightBlock(start: start, end: end, center: CGPoint(x: 0.85, y: 0.8), followsPointer: follows, mode: .blur, size: 1.6)
                let s = scene(project([block], clicks: true))
                var last = s.spotlight(at: 1.5)
                var t = 1.5
                while t < 6.5 {
                    t += 1 / 240
                    let now = s.spotlight(at: t)
                    let label = "block \(start)–\(end) follows \(follows) at \(t)"
                    if let a = last, let b = now {
                        XCTAssertLessThan(abs(b.amount - a.amount), 0.03, "amount, \(label)")
                        if min(a.amount, b.amount) > 0.05 {
                            XCTAssertLessThan(hypot(b.center.x - a.center.x, b.center.y - a.center.y), 0.02, "centre, \(label)")
                            XCTAssertLessThan(abs(b.size - a.size), 0.04, "size, \(label)")
                            XCTAssertLessThan(abs(b.blur - a.blur), 0.03, "look, \(label)")
                        }
                    } else if let state = last ?? now {
                        XCTAssertLessThan(state.amount, 0.03, "appears or vanishes, \(label)")
                    }
                    last = now
                }
            }
        }
    }

    func testTouchingBlocksGlideWithoutDipping() throws {
        let s = scene(project([SpotlightBlock(start: 1, end: 3, center: CGPoint(x: 0.2, y: 0.2)),
                               SpotlightBlock(start: 3, end: 5, center: CGPoint(x: 0.8, y: 0.8))]))
        var t = 2.5
        var last = try XCTUnwrap(s.spotlight(at: t))
        while t < 4 {
            t += 1 / 240
            let now = try XCTUnwrap(s.spotlight(at: t))
            XCTAssertEqual(now.amount, 1, accuracy: 1e-9)
            XCTAssertLessThan(hypot(now.center.x - last.center.x, now.center.y - last.center.y), 0.02)
            last = now
        }
        XCTAssertEqual(last.center.x, 0.8, accuracy: 1e-6)
    }

    func testCutsMoveAndDropBlocks() {
        var p = project([SpotlightBlock(start: 1, end: 2), SpotlightBlock(start: 6, end: 8)])
        p.removeTime(from: 0.5, to: 2.5)
        XCTAssertEqual(p.spotlights.count, 1)
        XCTAssertEqual(p.spotlights[0].start, 4, accuracy: 1e-9)
    }

    func testOldProjectsOpenWithoutSpotlights() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(Project(name: "Old"))) as? [String: Any])
        json["spotlights"] = nil
        let p = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(p.spotlights.isEmpty)
    }

    func testRendersWithClickSpotlightsOff() throws {
        let stripes = CIFilter(name: "CIStripesGenerator", parameters: [
            "inputColor0": CIColor(red: 0.2, green: 0.2, blue: 0.2), "inputColor1": CIColor.white, "inputWidth": 9,
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 3024, height: 1964))
        let renderer = FrameRenderer()
        func frame(_ blocks: [SpotlightBlock]) throws -> CGImage {
            let image = renderer.render(scene: scene(project(blocks)), time: 5, screen: stripes, camera: nil)
            return try XCTUnwrap(renderer.context.createCGImage(image, from: CGRect(origin: .zero, size: out)))
        }
        let plain = try frame([]), lit = try frame([SpotlightBlock(start: 4, end: 6)])
        func mean(_ cg: CGImage, _ r: CGRect) -> Double {
            let data = CFDataGetBytePtr(cg.cropping(to: r)!.dataProvider!.data)!
            let cropped = cg.cropping(to: r)!
            var sum = 0.0
            for y in 0 ..< cropped.height {
                for x in 0 ..< cropped.width * 4 where x % 4 != 3 { sum += Double(data[y * cropped.bytesPerRow + x]) }
            }
            return sum / Double(cropped.width * cropped.height * 3)
        }
        let middle = CGRect(x: 940, y: 520, width: 40, height: 40), aside = CGRect(x: 400, y: 520, width: 40, height: 40)
        XCTAssertEqual(mean(lit, middle), mean(plain, middle), accuracy: 1)
        XCTAssertLessThan(mean(lit, aside), mean(plain, aside) * 0.7)
    }
}
