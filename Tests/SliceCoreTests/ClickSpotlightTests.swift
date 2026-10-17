//
//  ClickSpotlightTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/17/26.
//

import CoreImage
@testable import SliceCore
import XCTest

final class ClickSpotlightTests: XCTestCase {
    let points = CGSize(width: 1512, height: 982)
    let out = CGSize(width: 1920, height: 1080)

    func scene(_ mode: SpotlightMode?, clicks: [CursorLog.Sample] = [.init(t: 2, x: 0.5, y: 0.5)]) -> RenderScene {
        var p = Project(name: "Spotlight")
        p.clips = [Clip(screenFile: "s.mov", cursorFile: "c.json", duration: 10, screenPixelSize: CGSize(width: 3024, height: 1964),
                        captureRect: CGRect(origin: .zero, size: points))]
        p.cursor.visible = false
        p.cursor.spotlight.enabled = mode != nil
        if let mode { p.cursor.spotlight.mode = mode }
        let log = CursorLog(samples: [.init(t: 0, x: 0.5, y: 0.5), .init(t: 10, x: 0.5, y: 0.5)], clicks: clicks)
        return RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [p.clips[0].id: log]))
    }

    var screen: CIImage {
        let stripes = CIFilter(name: "CIStripesGenerator", parameters: [
            "inputColor0": CIColor(red: 0.2, green: 0.2, blue: 0.2), "inputColor1": CIColor.white, "inputWidth": 9,
        ])!.outputImage!
        return stripes.cropped(to: CGRect(x: 0, y: 0, width: 3024, height: 1964))
    }

    func pixels(_ mode: SpotlightMode?, at t: Double, in rect: CGRect) throws -> [UInt8] {
        let renderer = FrameRenderer()
        let image = renderer.render(scene: scene(mode), time: t, screen: screen, camera: nil)
        let w = Int(rect.width), h = Int(rect.height)
        let cg = try XCTUnwrap(renderer.context.createCGImage(image, from: rect))
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return px
    }

    var middle: CGRect { CGRect(x: out.width / 2 - 20, y: out.height / 2 - 20, width: 40, height: 40) }
    var aside: CGRect { CGRect(x: out.width / 2 - 520, y: out.height / 2 - 20, width: 40, height: 40) }

    func changed(_ a: [UInt8], _ b: [UInt8]) -> Int { zip(a, b).filter { abs(Int($0) - Int($1)) > 6 }.count }
    func mean(_ a: [UInt8]) -> Double {
        let rgb = a.enumerated().filter { $0.offset % 4 != 3 }.map { Int($0.element) }
        return Double(rgb.reduce(0, +)) / Double(rgb.count)
    }

    func testKernelCompiles() {
        XCTAssertTrue(FrameRenderer.hasSpotlightKernel)
    }

    func testTiming() throws {
        let s = scene(.dim)
        XCTAssertNil(s.spotlight(at: 1.8))
        XCTAssertGreaterThan(try XCTUnwrap(s.spotlight(at: 1.95)).amount, 0)
        XCTAssertEqual(try XCTUnwrap(s.spotlight(at: 2.5)).amount, 1, accuracy: 1e-9)
        XCTAssertNil(s.spotlight(at: 2 + 0.9 + ClickSpotlight.fadeOut + 0.01))
        XCTAssertNil(scene(nil).spotlight(at: 2.5))
    }

    func testGlidesBetweenClicksWithoutJumps() throws {
        let s = scene(.dim, clicks: [.init(t: 2, x: 0.2, y: 0.3), .init(t: 2.6, x: 0.8, y: 0.7), .init(t: 4.4, x: 0.4, y: 0.4)])
        var last: SpotlightState?
        var t = 1.7
        while t < 7 {
            let now = s.spotlight(at: t)
            if let a = last, let b = now {
                XCTAssertLessThan(abs(b.amount - a.amount), 0.03, "amount jumps at \(t)")
                XCTAssertLessThan(hypot(b.center.x - a.center.x, b.center.y - a.center.y), 0.02, "centre jumps at \(t)")
            } else if let state = last ?? now {
                XCTAssertLessThan(state.amount, 0.03, "appears or vanishes abruptly at \(t)")
            }
            last = now
            t += 1 / 240
        }
        XCTAssertEqual(try XCTUnwrap(s.spotlight(at: 3.2)).center.x, 0.8, accuracy: 1e-6)
    }

    func testOldProjectsDecodeWithSpotlightOff() throws {
        let data = try JSONEncoder().encode(CursorSettings())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["spotlight"] = nil
        let decoded = try JSONDecoder().decode(CursorSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.spotlight, ClickSpotlight())
        XCTAssertFalse(decoded.spotlight.enabled)
    }

    func testDimDarkensAroundTheClickOnly() throws {
        let plainAside = try pixels(nil, at: 2.5, in: aside)
        XCTAssertEqual(changed(try pixels(nil, at: 2.5, in: middle), try pixels(.dim, at: 2.5, in: middle)), 0)
        XCTAssertLessThan(mean(try pixels(.dim, at: 2.5, in: aside)), mean(plainAside) * 0.7)
        XCTAssertEqual(changed(plainAside, try pixels(.dim, at: 1.5, in: aside)), 0, "before the click")
        XCTAssertEqual(changed(plainAside, try pixels(.dim, at: 4.5, in: aside)), 0, "after it fades")
    }

    func testBlurSoftensAroundTheClickOnly() throws {
        let plainAside = try pixels(nil, at: 2.5, in: aside)
        XCTAssertEqual(changed(try pixels(nil, at: 2.5, in: middle), try pixels(.blur, at: 2.5, in: middle)), 0)
        XCTAssertGreaterThan(changed(plainAside, try pixels(.blur, at: 2.5, in: aside)), 1000)
    }
}
