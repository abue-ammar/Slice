//
//  TiltTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/1/26.
//

import AppKit
import CoreGraphics
import CoreImage
@testable import SliceCore
import XCTest

final class TiltTests: XCTestCase {
    let out = CGSize(width: 1920, height: 1080)

    func project(tilt: ZoomTilt) -> Project {
        var p = Project(name: "Tilt")
        p.clips = [Clip(screenFile: "s.mov", duration: 20, screenPixelSize: CGSize(width: 3024, height: 1964),
                        captureRect: .zero)]
        var z = ZoomBlock(start: 4, end: 9, scale: 2, focus: CGPoint(x: 0.5, y: 0.5))
        z.tilt = tilt
        p.zoomBlocks = [z]
        return p
    }

    func tilt(_ direction: TiltDirection = .right, strength: Double = 0.6) -> ZoomTilt {
        var t = ZoomTilt()
        t.enabled = true
        t.direction = direction
        t.strength = strength
        return t
    }

    func testOldProjectsDecodeFlatAndTiltRoundTrips() throws {
        var z = ZoomBlock(start: 1, end: 2)
        XCTAssertFalse(z.tilt.enabled)
        z.tilt = tilt(.left, strength: 0.8)
        let decoded = try JSONDecoder().decode(ZoomBlock.self, from: JSONEncoder().encode(z))
        XCTAssertEqual(decoded.tilt, z.tilt)
        let old = #"{"id":"\#(UUID().uuidString)","start":1,"end":2}"#
        XCTAssertEqual(try JSONDecoder().decode(ZoomBlock.self, from: Data(old.utf8)).tilt, ZoomTilt())
    }

    func testTiltTurnsInStepWithTheZoomAndBack() {
        let p = project(tilt: tilt(strength: 0.6))
        let scene = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
        let full = p.zoomBlocks[0].tilt.pose
        XCTAssertEqual(full.yaw, 0.6 * 30 * .pi / 180, accuracy: 1e-9)
        XCTAssertTrue(scene.tilt(at: 3).isFlat)
        XCTAssertTrue(scene.tilt(at: 12).isFlat)
        XCTAssertEqual(scene.tilt(at: 6.5), full)
        XCTAssertEqual(scene.tilt(at: 4.0001).yaw, 0, accuracy: 1e-3)
        XCTAssertEqual(scene.tilt(at: 9.0001).yaw, full.yaw, accuracy: 1e-3)
        let unzoomed = scene.view(at: 3).width, zoomed = scene.view(at: 6.5).width
        for t in Array(stride(from: 4.0, through: 5.0, by: 0.05)) + Array(stride(from: 9.0, through: 10.0, by: 0.05)) {
            let zoom = log(unzoomed / scene.view(at: t).width) / log(unzoomed / zoomed)
            XCTAssertEqual(scene.tilt(at: t).yaw / full.yaw, zoom, accuracy: 0.01, "at \(t)")
        }
        var last = scene.tilt(at: 0).yaw
        for f in 1 ... 20 * 120 {
            let y = scene.tilt(at: Double(f) / 120).yaw
            XCTAssertLessThan(abs(y - last), full.yaw * 0.05, "at \(Double(f) / 120)")
            last = y
        }
    }

    func testAttachedZoomsTurnFromOneTiltToTheNext() {
        var p = project(tilt: tilt(.right))
        var next = ZoomBlock(start: 9, end: 14, scale: 2.5, focus: CGPoint(x: 0.3, y: 0.3))
        next.tilt = tilt(.left)
        p.zoomBlocks.append(next)
        let scene = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
        XCTAssertEqual(scene.tilt(at: 8.99).yaw, p.zoomBlocks[0].tilt.pose.yaw, accuracy: 1e-3)
        let mid = scene.tilt(at: 9.3).yaw
        XCTAssertTrue(mid < p.zoomBlocks[0].tilt.pose.yaw && mid > next.tilt.pose.yaw)
        XCTAssertEqual(scene.tilt(at: 12), next.tilt.pose)
    }

    func testDisabledOrLensZoomsStayFlat() {
        var off = tilt()
        off.enabled = false
        var p = project(tilt: off)
        XCTAssertTrue(RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:])).tilt(at: 6.5).isFlat)
        p = project(tilt: tilt())
        p.zoomBlocks[0].kind = .liquidGlass
        XCTAssertTrue(RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:])).tilt(at: 6.5).isFlat)
    }

    func testProjectionTurnsTheChosenSideAway() throws {
        let frame = CGRect(origin: .zero, size: out)
        for direction in TiltDirection.allCases {
            let h = tilt(direction, strength: 1).pose.homography(output: out)
            func edgeHeight(_ x: CGFloat) throws -> CGFloat {
                let top = try XCTUnwrap(h.apply(CGPoint(x: x, y: out.height))), bottom = try XCTUnwrap(h.apply(CGPoint(x: x, y: 0)))
                return top.y - bottom.y
            }
            let left = try edgeHeight(0), right = try edgeHeight(out.width)
            XCTAssertEqual(direction == .right, right < left, "\(direction)")
            let near = try XCTUnwrap(h.apply(CGPoint(x: direction == .right ? 0 : out.width, y: out.height / 2)))
            XCTAssertTrue(frame.insetBy(dx: 10, dy: 0).contains(near), "\(direction) \(near)")
            let p = CGPoint(x: 300, y: 700)
            let back = try XCTUnwrap(h.inverse?.apply(XCTUnwrap(h.apply(p))))
            XCTAssertEqual(back.x, p.x, accuracy: 1e-6)
            XCTAssertEqual(back.y, p.y, accuracy: 1e-6)
        }
        let flat = ScreenTilt.flat.homography(output: out)
        XCTAssertEqual(try XCTUnwrap(flat.apply(CGPoint(x: 123, y: 456))), CGPoint(x: 123, y: 456))
    }

    func testRenderTiltedFrame() throws {
        let screen = RenderTests.fakeScreen(size: CGSize(width: 3024, height: 1964))
        let renderer = FrameRenderer()
        let outDir = ProcessInfo.processInfo.environment["RENDER_OUT"].map { URL(fileURLWithPath: $0) }
        func pixel(_ cg: CGImage, _ x: Int, _ y: Int) -> NSColor {
            NSBitmapImageRep(cgImage: cg).colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        }
        for (name, direction, motionBlur, t) in [("tilt_right", TiltDirection.right, false, 6.5),
                                                 ("tilt_left", .left, false, 6.5),
                                                 ("tilt_zooming", .right, true, 4.3)] {
            var p = project(tilt: tilt(direction, strength: 0.7))
            p.zoomBlocks[0].focus = CGPoint(x: direction == .right ? 0.98 : 0.02, y: 0.4)
            p.style.motionBlur = motionBlur
            let scene = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
            let image = renderer.render(scene: scene, time: t, screen: screen, camera: nil)
            let cg = try XCTUnwrap(renderer.context.createCGImage(image, from: CGRect(origin: .zero, size: out)))
            if let outDir {
                try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
                    .write(to: outDir.appendingPathComponent("\(name).png"))
            }
            guard t == 6.5 else { continue }
            let far = pixel(cg, direction == .right ? Int(out.width) - 4 : 4, Int(out.height) / 2)
            let near = pixel(cg, direction == .right ? 40 : Int(out.width) - 40, Int(out.height) / 2)
            XCTAssertGreaterThan(far.blueComponent - far.greenComponent, 0.15, "\(name): background at the far edge, \(far)")
            XCTAssertLessThan(abs(near.blueComponent - near.greenComponent), 0.1, "\(name): screen at the near edge, \(near)")
        }
    }
}
