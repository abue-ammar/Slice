//
//  CursorTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/7/26.
//

import CoreGraphics
import CoreImage
@testable import SliceCore
import XCTest

final class CursorTests: XCTestCase {
    let points = CGSize(width: 1512, height: 982)

    func path(_ samples: [CursorLog.Sample], clicks: [CursorLog.Sample] = [], duration: Double) -> CursorPath {
        CursorPath(log: CursorLog(samples: samples, clicks: clicks), duration: duration, pointSize: points)
    }

    func samples(duration: Double, _ f: (Double) -> CGPoint) -> [CursorLog.Sample] {
        (0 ... Int(duration * 60)).map { i in
            let t = Double(i) / 60
            let p = f(t)
            return CursorLog.Sample(t: t, x: p.x, y: p.y)
        }
    }

    func testSmoothingRemovesJitter() {
        var seed: UInt64 = 42
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31) * 2 - 1
        }
        let s = samples(duration: 4) { _ in CGPoint(x: 0.5 + noise() * 1.5 / 1512, y: 0.5 + noise() * 1.5 / 982) }
        let p = path(s, duration: 4)
        func spread(smooth: Bool) -> Double {
            let xs = stride(from: 0.5, to: 3.5, by: 1.0 / 120).map { Double(p.position(at: $0, smooth: smooth)!.x) * 1512 }
            let mean = xs.reduce(0, +) / Double(xs.count)
            return (xs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(xs.count)).squareRoot()
        }
        XCTAssertLessThan(spread(smooth: true), spread(smooth: false) * 0.25)
    }

    func testSteadyMotionKeepsItsPaceAndHasNoLag() {
        let p = path(samples(duration: 3) { t in CGPoint(x: 0.1 + 0.25 * t, y: 0.8 - 0.1 * t) }, duration: 3)
        for t in stride(from: 0.0, through: 3, by: 0.05) {
            let a = p.position(at: t, smooth: true)!, b = p.position(at: t, smooth: false)!
            XCTAssertEqual(a.x, b.x, accuracy: 1e-4, "t=\(t)")
            XCTAssertEqual(a.y, b.y, accuracy: 1e-4, "t=\(t)")
        }
    }

    func testQuickMoveIsNeitherLateNorEarly() {
        let p = path(samples(duration: 3) { t in
            let f = min(max((t - 1) / 0.15, 0), 1)
            return CGPoint(x: 0.2 + 0.6 * f, y: 0.5)
        }, duration: 3)
        func crossing(smooth: Bool) -> Double {
            stride(from: 0.8, to: 1.4, by: 0.001).first { Double(p.position(at: $0, smooth: smooth)!.x) >= 0.5 }!
        }
        XCTAssertEqual(crossing(smooth: true), crossing(smooth: false), accuracy: 0.01)
        XCTAssertEqual(Double(p.position(at: 0.85, smooth: true)!.x), 0.2, accuracy: 1.0 / 1512)
        XCTAssertEqual(Double(p.position(at: 1.3, smooth: true)!.x), 0.8, accuracy: 1.0 / 1512)
        let v0 = p.position(at: 1.0, smooth: true)!.x - p.position(at: 0.99, smooth: true)!.x
        let raw0 = p.position(at: 1.01, smooth: false)!.x - p.position(at: 1.0, smooth: false)!.x
        XCTAssertLessThan(v0, raw0)
    }

    func testClicksLandExactlyOnTarget() {
        let curve: (Double) -> CGPoint = { t in CGPoint(x: 0.3 + 0.2 * cos(t * 4), y: 0.5 + 0.2 * sin(t * 4)) }
        let clickT = 1.234
        let target = curve(clickT)
        let p = path(samples(duration: 3, curve), clicks: [CursorLog.Sample(t: clickT, x: target.x, y: target.y)], duration: 3)
        let at = p.position(at: clickT, smooth: true)!
        XCTAssertEqual(Double(at.x) * 1512, Double(target.x) * 1512, accuracy: 0.1)
        XCTAssertEqual(Double(at.y) * 982, Double(target.y) * 982, accuracy: 0.1)
    }

    func project(cursorInVideo: Bool = false) -> (Project, CursorTrack) {
        var p = Project(name: "Cursor")
        p.clips = [Clip(screenFile: "s.mov", cursorFile: "c.json", duration: 10, screenPixelSize: CGSize(width: 3024, height: 1964),
                        captureRect: CGRect(origin: .zero, size: points), cursorInVideo: cursorInVideo)]
        let log = CursorLog(samples: samples(duration: 10) { t in CGPoint(x: t / 10, y: 0.5) })
        return (p, CursorTrack(project: p, logs: [p.clips[0].id: log]))
    }

    func testPointerFollowsCutsAndSettings() {
        var (p, _) = project()
        p.cuts = [Cut(clipID: p.clips[0].id, start: 2, end: 4)]
        let track = CursorTrack(project: p, logs: [p.clips[0].id: CursorLog(samples: samples(duration: 10) { t in CGPoint(x: t / 10, y: 0.5) })])
        let out = CGSize(width: 1920, height: 1080)
        let pointer = RenderScene(project: p, output: out, cursor: track).pointer(at: 2.5)
        XCTAssertEqual(Double(pointer?.position.x ?? 0), 0.45, accuracy: 0.002)
        XCTAssertEqual(pointer?.screenPoints, points)

        p.cursor.visible = false
        XCTAssertNil(RenderScene(project: p, output: out, cursor: track).pointer(at: 2.5))

        let (baked, bakedTrack) = project(cursorInVideo: true)
        XCTAssertNil(RenderScene(project: baked, output: out, cursor: bakedTrack).pointer(at: 1))
    }

    func testLoopGlidesBackToTheStart() {
        var (p, track) = project()
        let out = CGSize(width: 1920, height: 1080)
        func x(_ t: Double) -> Double { Double(RenderScene(project: p, output: out, cursor: track).pointer(at: t)!.position.x) }
        let end = p.duration - 0.001
        XCTAssertEqual(x(end), 1, accuracy: 0.01)
        p.cursor.loopPosition = true
        XCTAssertEqual(x(5), 0.5, accuracy: 0.002)
        XCTAssertEqual(x(end), x(0), accuracy: 0.01)
        XCTAssertLessThan(x(p.duration - 0.4), 0.96)
        XCTAssertGreaterThan(x(p.duration - 0.4), x(0))
    }

    func testMotionIsReusedAcrossEdits() {
        let (p, track) = project()
        let again = CursorMotion(project: p, logs: [:], reusing: track.motion)
        XCTAssertNotNil(again.path(for: p.clips[0].id))
        XCTAssertNil(CursorMotion(project: p, logs: [:]).path(for: p.clips[0].id))
    }

    func testBothMacOSSetsHaveEveryCursor() throws {
        XCTAssertEqual(CursorSettings().style, .native, "Big Sur is the default")
        for set in NativeCursor.Set.macOS {
            for type in CursorType.allCases {
                let drawn = try XCTUnwrap(NativeCursor.for(type, in: set), "\(set) \(type)")
                if type != .arrow { XCTAssertFalse(drawn.image === NativeCursor.for(.arrow, in: set)!.image, "\(set) \(type)") }
                let size = drawn.artwork.bounds.size
                XCTAssertTrue((8 ... 45).contains(max(size.width, size.height)), "\(set) \(type): \(size)")
            }
        }
        for style in [CursorStyle.tahoe, .macOS27] {
            XCTAssertFalse(NativeCursor.for(.arrow, in: style.nativeSet!)!.image === NativeCursor.for(.arrow, in: .bigSur)!.image)
            XCTAssertNotNil(style.preview(.pointingHand, scale: 2))
            XCTAssertTrue(style.followsSystemCursor)
        }
        XCTAssertFalse(CursorStyle.dot.followsSystemCursor)
    }

    // MARK: - Rendering

    func render(types: [CursorLog.TypeChange] = [], _ configure: (inout Project) -> Void) throws -> (CGImage, CGPoint, Double) {
        var (p, _) = project()
        configure(&p)
        let log = CursorLog(samples: [CursorLog.Sample(t: 0, x: 0.5, y: 0.5), CursorLog.Sample(t: 10, x: 0.5, y: 0.5)],
                            types: types)
        let track = CursorTrack(project: p, logs: [p.clips[0].id: log])
        let out = CGSize(width: 1920, height: 1080)
        let scene = RenderScene(project: p, output: out, cursor: track)
        let screen = CIImage(color: CIColor(red: 0.6, green: 0.6, blue: 0.6)).cropped(to: CGRect(x: 0, y: 0, width: 3024, height: 1964))
        let renderer = FrameRenderer()
        let image = renderer.render(scene: scene, time: 5, screen: screen, camera: nil)
        let cg = try XCTUnwrap(renderer.context.createCGImage(image, from: CGRect(origin: .zero, size: out)))
        let c = scene.geometry(at: 5).contentRect
        let k = Double(c.width / points.width) * p.cursor.size
        return (cg, CGPoint(x: c.midX, y: c.midY), k)
    }

    func brightness(_ image: CGImage, _ x: Double, _ y: Double) -> Double {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -x.rounded(.down), y: -(Double(image.height) - 1 - y.rounded(.down)),
                                   width: Double(image.width), height: Double(image.height)))
        return Double(px[0]) / 255
    }

    func testRendersPointerOnItsHotspot() throws {
        let (shown, hot, k) = try render { $0.cursor.style = .dot }
        let inside = 0.6 * 0.5 + 0.5
        XCTAssertEqual(brightness(shown, hot.x, hot.y), inside, accuracy: 0.04)
        XCTAssertEqual(brightness(shown, hot.x + 7 * k, hot.y), inside, accuracy: 0.04)
        XCTAssertEqual(brightness(shown, hot.x + 12 * k, hot.y), 0.6, accuracy: 0.02)
        XCTAssertEqual(brightness(shown, hot.x - 12 * k, hot.y), 0.6, accuracy: 0.02)

        let (hidden, _, _) = try render { $0.cursor.style = .dot; $0.cursor.visible = false }
        XCTAssertEqual(brightness(hidden, hot.x, hot.y), 0.6, accuracy: 0.02)

        let (big, _, bigK) = try render { $0.cursor.style = .dot; $0.cursor.size = 2 * CursorSettings().size }
        XCTAssertEqual(bigK, 2 * k, accuracy: 1e-9)
        XCTAssertEqual(brightness(big, hot.x + 12 * k, hot.y), inside, accuracy: 0.04)
    }

    func testCuteSetsAndRemovedArrow() throws {
        for style in [CursorStyle.pompompurin, .pizza, .watermelon] {
            XCTAssertEqual(style.family, .cute)
            let set = try XCTUnwrap(style.nativeSet)
            let arrow = try XCTUnwrap(NativeCursor.for(.arrow, in: set), "\(style)")
            let size = arrow.artwork.bounds.size
            XCTAssertEqual(max(size.width, size.height), 20, accuracy: 0.5, "\(style) is sized like a cursor")
            XCTAssertTrue(NativeCursor.for(.iBeam, in: set)!.image === arrow.image)
        }
        XCTAssertEqual(CursorStyle.pompompurin.previewTypes, [.arrow, .pointingHand])
        XCTAssertEqual(CursorStyle.watermelon.previewTypes, [.arrow], "no hand in that set")
        XCTAssertEqual(CursorStyle.macOS27.label, "Golden Gate")
        for removed in ["arrow", "whiteArrow"] {
            XCTAssertNil(CursorStyle(rawValue: removed))
            let old = try JSONDecoder().decode(CursorSettings.self, from: Data(#"{"style":"\#(removed)"}"#.utf8))
            XCTAssertEqual(old.style, .native)
        }
    }

    // MARK: - Persistence

    func testSettingsAndOlderTakesDecode() throws {
        let settings = try JSONDecoder().decode(CursorSettings.self, from: Data(#"{"size": 2, "style": "sparkles"}"#.utf8))
        XCTAssertEqual(settings.size, 2)
        XCTAssertEqual(settings.style, CursorSettings().style)
        XCTAssertTrue(settings.visible)
        XCTAssertEqual(settings.smoothing, CursorSettings().smoothing)
        let off = try JSONDecoder().decode(CursorSettings.self, from: Data(#"{"smooth": false}"#.utf8))
        XCTAssertEqual(off.smoothing, 0)

        var old = project().0
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        var clips = json["clips"] as! [[String: Any]]
        clips[0].removeValue(forKey: "cursorInVideo")
        var trimmed = json
        trimmed["clips"] = clips
        trimmed.removeValue(forKey: "cursor")
        let decoded = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: trimmed))
        XCTAssertTrue(decoded.clips[0].cursorInVideo)
        XCTAssertFalse(decoded.clips[0].hasEditableCursor)
        XCTAssertEqual(decoded.cursor, CursorSettings())

        old.cursor.style = .dot
        XCTAssertEqual(try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(old)), old)
    }

    // MARK: - System cursor types

    func testTypeFollowsRecordedChanges() {
        let log = CursorLog(samples: [CursorLog.Sample(t: 0, x: 0.5, y: 0.5)],
                            types: [.init(t: 2, type: .iBeam), .init(t: -0.1, type: .arrow), .init(t: 5, type: .pointingHand)])
        let p = CursorPath(log: log, duration: 10, pointSize: points)
        XCTAssertEqual(p.type(at: 0), .arrow)
        XCTAssertEqual(p.type(at: 1.99), .arrow)
        XCTAssertEqual(p.type(at: 2), .iBeam)
        XCTAssertEqual(p.type(at: 9), .pointingHand)
        XCTAssertEqual(path([CursorLog.Sample(t: 0, x: 0.5, y: 0.5)], duration: 1).type(at: 0.5), .arrow)
    }

    func testPointerCarriesTypeInTakeTime() {
        var (p, _) = project()
        p.cuts = [Cut(clipID: p.clips[0].id, start: 2, end: 4)]
        let log = CursorLog(samples: samples(duration: 10) { t in CGPoint(x: t / 10, y: 0.5) },
                            types: [.init(t: 0, type: .arrow), .init(t: 4.2, type: .pointingHand)])
        let scene = RenderScene(project: p, output: CGSize(width: 1920, height: 1080),
                                cursor: CursorTrack(project: p, logs: [p.clips[0].id: log]))
        XCTAssertEqual(scene.pointer(at: 2.1)?.type, .arrow)
        XCTAssertEqual(scene.pointer(at: 2.5)?.type, .pointingHand)
    }

    func testLogsDecodeWithAndWithoutTypes() throws {
        let legacy = try JSONDecoder().decode(CursorLog.self, from: Data(#"{"samples": [], "clicks": []}"#.utf8))
        XCTAssertEqual(legacy.types, [])
        let newer = try JSONDecoder().decode(CursorLog.self, from: Data(
            #"{"samples": [], "clicks": [], "types": [{"t": 1, "type": "iBeam"}, {"t": 2, "type": "laserPointer"}]}"#.utf8))
        XCTAssertEqual(newer.types.map(\.type), [.iBeam, .arrow])
        let log = CursorLog(types: [.init(t: 1, type: .resizeNorthEast)])
        XCTAssertEqual(try JSONDecoder().decode(CursorLog.self, from: JSONEncoder().encode(log)), log)
    }

    func testEveryTypeHasNativeArtwork() throws {
        let arrow = try XCTUnwrap(NativeCursor.for(.arrow))
        for type in CursorType.allCases {
            let art = try XCTUnwrap(NativeCursor.for(type), "\(type)")
            if type != .arrow { XCTAssertFalse(art.image === arrow.image, "\(type) fell back to the arrow") }
            XCTAssertTrue(CGRect(x: 0, y: 0, width: art.image.width, height: art.image.height).contains(art.hotspot), "\(type)")
            XCTAssertLessThanOrEqual(CGFloat(max(art.image.width, art.image.height)) / art.pixelsPerPoint, 32, "\(type)")
        }
    }

    func testNativeStyleDrawsTheRecordedCursor() throws {
        let (shown, hot, k) = try render { $0.cursor.size = 4 }
        XCTAssertLessThan(brightness(shown, hot.x + 3 * k, hot.y + 9 * k), 0.15)
        XCTAssertGreaterThan(brightness(shown, hot.x - 3 * k, hot.y - 3 * k), 0.4)

        let (beam, beamHot, beamK) = try render(types: [.init(t: 0, type: .iBeam)]) { $0.cursor.size = 4 }
        XCTAssertLessThan(brightness(beam, beamHot.x, beamHot.y + 4 * beamK), 0.15)
        XCTAssertEqual(brightness(beam, beamHot.x + 8 * beamK, beamHot.y + 4 * beamK), 0.6, accuracy: 0.05)
        XCTAssertEqual(brightness(beam, beamHot.x - 8 * beamK, beamHot.y + 4 * beamK), 0.6, accuracy: 0.05)
    }

    // MARK: - State stabilisation, tilt, blur, pause joins

    func testBriefCursorChangesAreIgnoredAndLastingOnesAreOnTime() {
        let log = CursorLog(samples: [.init(t: 0, x: 0.5, y: 0.5)], types: [
            .init(t: 0, type: .arrow), .init(t: 1, type: .pointingHand), .init(t: 2, type: .arrow),
            .init(t: 2.05, type: .pointingHand), .init(t: 3, type: .iBeam),
        ])
        let p = CursorPath(log: log, duration: 5, pointSize: points)
        XCTAssertEqual(p.stableType(at: 0.5, settle: 0.12).type, .arrow)
        XCTAssertEqual(p.stableType(at: 1.0, settle: 0.12).type, .pointingHand, "switches when it happened, not late")
        for t in stride(from: 1.9, through: 2.2, by: 0.01) {
            XCTAssertEqual(p.stableType(at: t, settle: 0.12).type, .pointingHand, "no flicker at \(t)")
        }
        let text = p.stableType(at: 3.5, settle: 0.12)
        XCTAssertEqual(text.type, .iBeam)
        XCTAssertEqual(text.since, 3)
        XCTAssertEqual(text.previous, .pointingHand)
        XCTAssertEqual(p.stableType(at: 2.5, settle: 0.12).since, 1)
        XCTAssertEqual(p.stableType(at: 2.02, settle: 0).type, .arrow)
    }

    func testCursorChangeCrossFades() {
        var (p, _) = project()
        p.cursor.motionBlur = 0
        let log = CursorLog(samples: samples(duration: 10) { _ in CGPoint(x: 0.5, y: 0.5) },
                            types: [.init(t: 0, type: .arrow), .init(t: 4, type: .pointingHand)])
        let scene = RenderScene(project: p, output: CGSize(width: 1920, height: 1080),
                                cursor: CursorTrack(project: p, logs: [p.clips[0].id: log]))
        let mid = scene.pointer(at: 4.045)!
        XCTAssertEqual(mid.type, .pointingHand)
        XCTAssertEqual(mid.previousType, .arrow)
        XCTAssertGreaterThan(mid.fade, 0.2)
        XCTAssertLessThan(mid.fade, 0.8)
        XCTAssertNil(scene.pointer(at: 4.5)!.previousType)
        XCTAssertEqual(scene.pointer(at: 3.99)!.position, scene.pointer(at: 4.01)!.position)
    }

    func testTiltLeansIntoMovementAndSettlesWhenStill() {
        var (p, _) = project()
        p.cursor.tilt = 1
        p.cursor.motionBlur = 0
        let log = CursorLog(samples: samples(duration: 10) { t in
            let x = t < 2 ? 0.2 : t < 3 ? 0.2 + 0.4 * (t - 2) : t < 6 ? 0.6 : t < 7 ? 0.6 - 0.4 * (t - 6) : 0.2
            return CGPoint(x: x, y: 0.5)
        })
        let scene = RenderScene(project: p, output: CGSize(width: 1920, height: 1080),
                                cursor: CursorTrack(project: p, logs: [p.clips[0].id: log]))
        let right = scene.pointer(at: 2.6)!.pose.angle, left = scene.pointer(at: 6.6)!.pose.angle
        XCTAssertLessThan(right, -0.05, "moving right leans clockwise")
        XCTAssertGreaterThan(left, 0.05)
        XCTAssertLessThanOrEqual(abs(right), p.cursor.tiltMaxAngle * .pi / 180 + 1e-9)
        XCTAssertEqual(scene.pointer(at: 5)!.pose.angle, 0, accuracy: 0.002, "upright again at rest")
        var last = scene.pointer(at: 1.9)!.pose.angle
        for t in stride(from: 1.9, through: 4, by: 1.0 / 120) {
            let a = scene.pointer(at: t)!.pose.angle
            XCTAssertLessThan(abs(a - last), 0.03, "t=\(t)")
            last = a
        }
    }

    func testMotionBlurOnlyWhileMovingFastAlongThePath() {
        var (p, _) = project()
        p.cursor.motionBlur = 1
        let log = CursorLog(samples: samples(duration: 10) { t in
            CGPoint(x: t < 4 ? 0.2 : t < 4.2 ? 0.2 + 3 * (t - 4) : 0.8, y: 0.5)
        })
        let scene = RenderScene(project: p, output: CGSize(width: 1920, height: 1080),
                                cursor: CursorTrack(project: p, logs: [p.clips[0].id: log]))
        XCTAssertTrue(scene.pointer(at: 2)!.trail.isEmpty, "still: sharp")
        XCTAssertTrue(scene.pointer(at: 8)!.trail.isEmpty)
        let fast = scene.pointer(at: 4.1)!
        XCTAssertGreaterThan(fast.trail.count, 4)
        XCTAssertEqual(fast.trail.last, fast.pose)
        XCTAssertLessThan(fast.trail.first!.position.x, fast.pose.position.x)
        p.cursor.motionBlur = 0
        let off = RenderScene(project: p, output: CGSize(width: 1920, height: 1080),
                              cursor: CursorTrack(project: p, logs: [p.clips[0].id: log]))
        XCTAssertTrue(off.pointer(at: 4.1)!.trail.isEmpty)
    }

    func testPointerIsDeterministicForScrubbing() {
        var (p, _) = project()
        p.cursor.tilt = 1
        p.cursor.motionBlur = 1
        let log = CursorLog(samples: samples(duration: 10) { t in CGPoint(x: 0.5 + 0.3 * sin(t * 3), y: 0.5 + 0.2 * cos(t * 2)) })
        let track = CursorTrack(project: p, logs: [p.clips[0].id: log])
        let a = RenderScene(project: p, output: CGSize(width: 1920, height: 1080), cursor: track)
        let forward = stride(from: 0.0, to: 10, by: 0.37).map { a.pointer(at: $0) }
        let backward = stride(from: 0.0, to: 10, by: 0.37).reversed().map { a.pointer(at: $0) }.reversed()
        XCTAssertEqual(forward, Array(backward))
    }

    func testResumedTakeGlidesOnFromWherePausedTakeStopped() {
        let rect = CGRect(origin: .zero, size: points)
        var p = Project(name: "Pause")
        p.clips = [
            Clip(screenFile: "a.mov", cursorFile: "a.json", duration: 2, screenPixelSize: CGSize(width: 3024, height: 1964),
                 captureRect: rect, cursorInVideo: false),
            Clip(screenFile: "b.mov", cursorFile: "b.json", duration: 2, screenPixelSize: CGSize(width: 3024, height: 1964),
                 captureRect: rect, cursorInVideo: false),
        ]
        let logs = [p.clips[0].id: CursorLog(samples: samples(duration: 2) { _ in CGPoint(x: 0.3, y: 0.3) }),
                    p.clips[1].id: CursorLog(samples: samples(duration: 2) { _ in CGPoint(x: 0.7, y: 0.6) })]
        let scene = RenderScene(project: p, output: CGSize(width: 1920, height: 1080), cursor: CursorTrack(project: p, logs: logs))
        let end = scene.pointer(at: 1.999)!.position, start = scene.pointer(at: 2.0)!.position
        XCTAssertEqual(end.x, start.x, accuracy: 0.002, "no snap at the join")
        XCTAssertEqual(scene.pointer(at: 2.5)!.position.x, 0.7, accuracy: 0.001)
        XCTAssertEqual(scene.pointer(at: 1.9)!.position.x, 0.3, accuracy: 0.001)
    }

    func testSmoothingStrengthIsAdjustable() {
        var seed: UInt64 = 7
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31) * 2 - 1
        }
        let log = CursorLog(samples: samples(duration: 4) { _ in CGPoint(x: 0.5 + noise() * 2 / 1512, y: 0.5) })
        func spread(_ strength: Double) -> Double {
            let path = CursorPath(log: log, duration: 4, pointSize: points, smoother: CursorSmoother(strength: strength))
            let xs = stride(from: 0.5, to: 3.5, by: 1.0 / 120).map { Double(path.position(at: $0, smooth: true)!.x) * 1512 }
            let mean = xs.reduce(0, +) / Double(xs.count)
            return (xs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(xs.count)).squareRoot()
        }
        let raw = spread(0), soft = spread(0.5), smoothest = spread(1)
        XCTAssertGreaterThan(raw, soft)
        XCTAssertGreaterThan(soft, smoothest)
    }
}
