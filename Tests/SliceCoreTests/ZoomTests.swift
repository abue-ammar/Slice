//
//  ZoomTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/13/26.
//

import CoreGraphics
import CoreImage
@testable import SliceCore
import XCTest

final class ZoomTests: XCTestCase {
    let out = CGSize(width: 1920, height: 1080)

    func project() -> Project {
        var p = Project(name: "Zoom")
        p.clips = [Clip(screenFile: "s.mov", duration: 20, screenPixelSize: CGSize(width: 3840, height: 2160),
                        captureRect: CGRect(x: 0, y: 0, width: 1920, height: 1080))]
        p.export.aspect = .landscape16x9
        return p
    }

    func testEveryEasingRunsFromZeroToOne() {
        for curve in EasingCurve.allCases {
            XCTAssertEqual(curve(0), 0, accuracy: 1e-9, "\(curve)")
            XCTAssertEqual(curve(1), 1, accuracy: 1e-9, "\(curve)")
            var last = 0.0
            for i in 1 ... 100 {
                let v = curve(Double(i) / 100)
                XCTAssertGreaterThanOrEqual(v, last - 1e-9, "\(curve) never goes backwards")
                XCTAssertLessThanOrEqual(v, 1 + 1e-9, "\(curve) never overshoots")
                last = v
            }
        }
    }

    func testCubicBezierMatchesCSS() {
        let linear = CubicBezier(0, 0, 1, 1)
        for x in stride(from: 0.0, through: 1, by: 0.1) { XCTAssertEqual(linear(x), x, accuracy: 1e-6) }
        XCTAssertEqual(CubicBezier(0.25, 0.1, 0.25, 1)(0.25), 0.4085, accuracy: 0.002)
        let out = CubicBezier.default
        for x in stride(from: 0.05, through: 0.95, by: 0.05) { XCTAssertGreaterThan(out(x), x) }
        let overshoot = CubicBezier.presets.first { $0.name == "overshoot" }!.curve
        XCTAssertGreaterThan((1 ..< 100).map { overshoot(Double($0) / 100) }.max()!, 1.05)
        XCTAssertEqual(overshoot(1), 1)
        XCTAssertEqual(CubicBezier(css: overshoot.css), overshoot)
        XCTAssertEqual(overshoot.css, "cubic-bezier(0.34, 1.56, 0.64, 1)")
        XCTAssertEqual(CubicBezier(css: " 0.1, -0.4,0.2,1.3 "), CubicBezier(0.1, -0.4, 0.2, 1.3))
        XCTAssertNil(CubicBezier(css: "cubic-bezier(1.2, 0, 0.5, 1)"))
        XCTAssertNil(CubicBezier(css: "ease-in"))
    }

    func testZoomFollowsItsCustomCurve() throws {
        var p = project()
        var z = ZoomBlock(start: 2, end: 8, scale: 2)
        z.transition = 1
        z.easing = .custom
        z.curve = CubicBezier(0.9, 0, 1, 0.1)
        p.zoomBlocks = [z]
        let slow = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
        p.zoomBlocks[0].curve = .default
        let fast = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
        let full = slow.geometry(at: 0).fullView.width
        XCTAssertEqual(slow.view(at: 2.5).width, full, accuracy: full * 0.02)
        XCTAssertLessThan(fast.view(at: 2.5).width, full * 0.6)
        let saved = try JSONDecoder().decode(ZoomBlock.self, from: JSONEncoder().encode(z))
        XCTAssertEqual(saved.curve, z.curve)
        XCTAssertEqual(saved.easing, .custom)
    }

    func testZoomUsesItsOwnTransitionAndPans() {
        var p = project()
        var z = ZoomBlock(start: 2, end: 8, scale: 2, focus: CGPoint(x: 0.2, y: 0.5))
        z.transition = 0.4
        z.easing = .linear
        z.endFocus = CGPoint(x: 0.8, y: 0.5)
        p.zoomBlocks = [z]
        let scene = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
        let full = scene.geometry(at: 0).fullView.width
        let zoomed = scene.geometry(at: 0).fullBleedSize.width / 2
        XCTAssertEqual(scene.view(at: 2.4).width, zoomed, accuracy: 1)
        XCTAssertGreaterThan(scene.view(at: 2.2).width, zoomed + 1)
        XCTAssertGreaterThan(scene.view(at: 7).midX, scene.view(at: 3).midX + 100)
        XCTAssertEqual(scene.view(at: 8.4).width, full, accuracy: 1)
    }

    func testLensAppearsGlidesAndLeaves() {
        var p = project()
        var z = ZoomBlock(start: 2, end: 6, scale: 2, focus: CGPoint(x: 0.3, y: 0.3), kind: .liquidGlass)
        z.endFocus = CGPoint(x: 0.7, y: 0.6)
        z.transition = 0.5
        p.zoomBlocks = [z]
        let scene = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
        XCTAssertNil(scene.lens(at: 1.9))
        XCTAssertNil(scene.lens(at: 6.1))
        XCTAssertLessThan(scene.lens(at: 2.1)!.appear, 0.5)
        XCTAssertEqual(scene.lens(at: 4)!.appear, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(scene.lens(at: 2.2)!.appear, 0.3)
        XCTAssertLessThan(scene.lens(at: 2.2)!.appear, 0.9)
        XCTAssertGreaterThan(scene.lens(at: 2.2)!.magnification, 1.1)
        XCTAssertLessThan(scene.lens(at: 2.2)!.magnification, 2)
        XCTAssertEqual(scene.lens(at: 2.4)!.appear, 1, accuracy: 1e-9)
        XCTAssertLessThan(scene.lens(at: 2.4)!.magnification, 2)
        XCTAssertLessThan(scene.lens(at: 2.1)!.magnification, 1.5)
        XCTAssertGreaterThan(scene.lens(at: 2.1)!.magnification, 1)
        XCTAssertEqual(scene.lens(at: 4)!.magnification, 2, accuracy: 1e-9)
        XCTAssertEqual(scene.lens(at: 2.3)!.center, CGPoint(x: 0.3, y: 0.3))
        XCTAssertEqual(scene.lens(at: 5.6)!.center.x, 0.7, accuracy: 1e-6)
        XCTAssertEqual(scene.lens(at: 4)!.center.x, 0.5, accuracy: 0.01)
        XCTAssertEqual(scene.view(at: 4), scene.geometry(at: 4).fullView)
    }

    func testAttachedLensesFlowIntoEachOther() {
        var p = project()
        p.style.zoomTransitionDuration = 0.5
        var a = ZoomBlock(start: 2, end: 5, scale: 2, focus: CGPoint(x: 0.2, y: 0.5), kind: .liquidGlass)
        var b = ZoomBlock(start: 5, end: 8, scale: 3, focus: CGPoint(x: 0.8, y: 0.5), kind: .liquidGlass)
        var c = ZoomBlock(start: 8, end: 11, scale: 2, focus: CGPoint(x: 0.5, y: 0.3), kind: .liquidGlass)
        a.lens.shape = .circle
        b.lens.shape = .squircle
        b.lens.size = 0.3
        c.lens.shape = .pill
        a.easing = .linear; b.easing = .linear; c.easing = .linear
        p.zoomBlocks = [c, a, b]
        let scene = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
        for t in Array(stride(from: 4.6, through: 5.6, by: 0.05)) + Array(stride(from: 7.6, through: 8.6, by: 0.05)) {
            let lens = scene.lens(at: t)
            XCTAssertEqual(lens?.appear ?? 0, 1, accuracy: 1e-9, "at \(t)")
            XCTAssertGreaterThanOrEqual(lens?.magnification ?? 0, 2 - 1e-9, "at \(t)")
        }
        XCTAssertEqual(scene.lens(at: 4.99)!.center.x, 0.2, accuracy: 1e-6)
        XCTAssertEqual(scene.lens(at: 4.99)!.shapes, [.circle: 1])
        let mid = scene.lens(at: 5.25)!
        XCTAssertEqual(mid.center.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(mid.magnification, sqrt(6), accuracy: 1e-6)
        XCTAssertEqual(mid.settings.size, (LensSettings().size + 0.3) / 2, accuracy: 1e-6)
        XCTAssertEqual(mid.shapes[.circle]!, 0.5, accuracy: 1e-6)
        XCTAssertEqual(mid.shapes[.squircle]!, 0.5, accuracy: 1e-6)
        let second = scene.lens(at: 6)!
        XCTAssertEqual(second.center.x, 0.8, accuracy: 1e-6)
        XCTAssertEqual(second.magnification, 3, accuracy: 1e-9)
        XCTAssertEqual(second.shapes, [.squircle: 1])
        XCTAssertEqual(scene.lens(at: 8.25)!.shapes[.pill]!, 0.5, accuracy: 1e-6)
        XCTAssertEqual(scene.lens(at: 9)!.shapes, [.pill: 1])
        XCTAssertLessThan(scene.lens(at: 10.9)!.appear, 0.5)
        XCTAssertNil(scene.lens(at: 11.1))
        var last = scene.lens(at: 2.6)!
        for t in stride(from: 2.61, through: 10.4, by: 0.01) {
            let now = scene.lens(at: t)!
            XCTAssertLessThan(abs(now.center.x - last.center.x), 0.03, "at \(t)")
            XCTAssertLessThan(abs(now.magnification - last.magnification), 0.05, "at \(t)")
            last = now
        }
    }

    func testLensesWithAGapStillZoomOutAndBackIn() {
        var p = project()
        p.zoomBlocks = [ZoomBlock(start: 2, end: 5, kind: .liquidGlass), ZoomBlock(start: 5.5, end: 8, kind: .liquidGlass)]
        for i in p.zoomBlocks.indices { p.zoomBlocks[i].transition = 0.4 }
        let scene = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
        XCTAssertLessThan(scene.lens(at: 4.95)!.appear, 0.5)
        XCTAssertNil(scene.lens(at: 5.2))
        XCTAssertLessThan(scene.lens(at: 5.55)!.appear, 0.5)
    }

    func testAttachedLensesRenderOneGlassThroughTheJoin() throws {
        var p = project()
        p.style.motionBlur = false
        var a = ZoomBlock(start: 2, end: 5, scale: 2, focus: CGPoint(x: 0.3, y: 0.5), kind: .liquidGlass)
        var b = ZoomBlock(start: 5, end: 8, scale: 2, focus: CGPoint(x: 0.7, y: 0.5), kind: .liquidGlass)
        a.transition = 1
        b.transition = 1
        b.lens.shape = .pill
        p.zoomBlocks = [a, b]
        let scene = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
        let screen = CIFilter(name: "CICheckerboardGenerator", parameters: ["inputWidth": 40, "inputColor0": CIColor.black,
                                                                            "inputColor1": CIColor.white])!.outputImage!
            .cropped(to: CGRect(x: 0, y: 0, width: 3840, height: 2160))
        let renderer = FrameRenderer()
        func row(_ t: Double) throws -> [UInt8] {
            let image = renderer.render(scene: scene, time: t, screen: screen, camera: nil)
            let cg = try XCTUnwrap(renderer.context.createCGImage(image, from: CGRect(x: 0, y: 540, width: out.width, height: 1)))
            var px = [UInt8](repeating: 0, count: cg.width * 4)
            let ctx = CGContext(data: &px, width: cg.width, height: 1, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: 1))
            return px
        }
        let plain = try row(1)
        func changed(_ t: Double) throws -> [Int] {
            let r = try row(t)
            return (0 ..< Int(out.width)).filter { abs(Int(r[$0 * 4]) - Int(plain[$0 * 4])) > 40 }
        }
        let settled = try changed(4.5).count
        for t in [4.99, 5.01, 5.2, 5.5, 5.8, 6.1] {
            let n = try changed(t).count
            XCTAssertGreaterThan(n, settled / 2, "at \(t)")
            XCTAssertLessThan(n, Int(Double(settled) * 2.2), "at \(t)")
        }
        func middle(_ xs: [Int]) -> Double { Double(xs.reduce(0, +)) / Double(max(xs.count, 1)) }
        XCTAssertLessThan(middle(try changed(4.5)), out.width / 2 - 200)
        XCTAssertGreaterThan(middle(try changed(6.5)), out.width / 2 + 200)
    }

    func testLensFollowsThePointer() {
        var p = project()
        p.clips[0].cursorFile = "c.json"
        p.clips[0].cursorInVideo = false
        var z = ZoomBlock(start: 1, end: 9, kind: .liquidGlass)
        z.followsCursor = true
        p.zoomBlocks = [z]
        let log = CursorLog(samples: (0 ... 600).map { i in CursorLog.Sample(t: Double(i) / 60, x: 0.1 + 0.08 * Double(i) / 60, y: 0.5) })
        let scene = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [p.clips[0].id: log]))
        XCTAssertEqual(scene.lens(at: 5)!.center.x, 0.5, accuracy: 0.03)
    }

    func testOldZoomBlocksStillOpen() throws {
        let json = #"{"id": "\#(UUID().uuidString)", "start": 1, "end": 3, "scale": 2.5, "focus": [0.2, 0.3], "isAuto": true}"#
        let z = try JSONDecoder().decode(ZoomBlock.self, from: Data(json.utf8))
        XCTAssertEqual(z.kind, .standard)
        XCTAssertEqual(z.easing, .smooth)
        XCTAssertNil(z.endFocus)
        XCTAssertNil(z.transition)
        XCTAssertEqual(z.lens, LensSettings())
        XCTAssertEqual(z.curve, .default)
        var lens = z
        lens.kind = .liquidGlass
        lens.lens.shape = .pill
        XCTAssertEqual(try JSONDecoder().decode(ZoomBlock.self, from: JSONEncoder().encode(lens)), lens)
    }

    func testLensRendersMagnifiedGlassOverTheScreen() throws {
        XCTAssertTrue(FrameRenderer.hasGlassKernel)
        var p = project()
        p.zoomBlocks = [ZoomBlock(start: 0, end: 10, scale: 2, focus: CGPoint(x: 0.5, y: 0.5), kind: .liquidGlass)]
        p.zoomBlocks[0].transition = 0
        let scene = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
        let stripes = CIFilter(name: "CIStripesGenerator", parameters: ["inputWidth": 8, "inputColor0": CIColor.black,
                                                                        "inputColor1": CIColor.white])!.outputImage!
            .cropped(to: CGRect(x: 0, y: 0, width: 3840, height: 2160))
        let renderer = FrameRenderer()
        let image = renderer.render(scene: scene, time: 5, screen: stripes, camera: nil)
        let cg = try XCTUnwrap(renderer.context.createCGImage(image, from: CGRect(origin: .zero, size: out)))
        func runs(_ y: Int, _ x0: Int, _ x1: Int) -> Double {
            var px = [UInt8](repeating: 0, count: cg.width * 4)
            let ctx = CGContext(data: &px, width: cg.width, height: 1, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg, in: CGRect(x: 0, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
            var changes = 0
            for x in x0 ..< x1 where (px[x * 4] > 128) != (px[(x + 1) * 4] > 128) { changes += 1 }
            return Double(x1 - x0) / Double(max(changes, 1))
        }
        let inside = runs(540, 900, 1020), outside = runs(540, 300, 420)
        XCTAssertEqual(inside / outside, 2, accuracy: 0.35)
    }

    func testLensZoomsInFromTheWholeScreen() throws {
        var p = project()
        p.style.motionBlur = false
        p.zoomBlocks = [ZoomBlock(start: 2, end: 8, scale: 2, focus: CGPoint(x: 0.5, y: 0.5), kind: .liquidGlass)]
        p.zoomBlocks[0].transition = 1
        let scene = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
        let screen = CIFilter(name: "CICheckerboardGenerator", parameters: ["inputWidth": 40, "inputColor0": CIColor.black,
                                                                            "inputColor1": CIColor.white])!.outputImage!
            .cropped(to: CGRect(x: 0, y: 0, width: 3840, height: 2160))
        let renderer = FrameRenderer()
        func pixels(_ t: Double) throws -> [UInt8] {
            let image = renderer.render(scene: scene, time: t, screen: screen, camera: nil)
            let cg = try XCTUnwrap(renderer.context.createCGImage(image, from: CGRect(origin: .zero, size: out)))
            var px = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            let ctx = CGContext(data: &px, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg, in: CGRect(origin: .zero, size: out))
            return px
        }
        func changed(_ a: [UInt8], _ b: [UInt8], row: Int) -> Int {
            let w = Int(out.width)
            return (0 ..< w).filter { x in abs(Int(a[(row * w + x) * 4]) - Int(b[(row * w + x) * 4])) > 40 }.count
        }
        let plain = try pixels(1)
        XCTAssertLessThan(changed(try pixels(2.01), plain, row: 540), 20)
        let settled = changed(try pixels(5), plain, row: 540)
        XCTAssertGreaterThan(changed(try pixels(2.4), plain, row: 540), settled + 200)
        XCTAssertLessThan(changed(try pixels(7.995), plain, row: 540), 20)
    }
}
