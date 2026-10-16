//
//  ClickEffectTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/1/26.
//

import CoreImage
@testable import SliceCore
import XCTest

final class ClickEffectTests: XCTestCase {
    let points = CGSize(width: 1512, height: 982)
    let out = CGSize(width: 1920, height: 1080)

    func scene(_ effect: ClickEffect) -> RenderScene {
        var p = Project(name: "Clicks")
        p.clips = [Clip(screenFile: "s.mov", cursorFile: "c.json", duration: 10, screenPixelSize: CGSize(width: 3024, height: 1964),
                        captureRect: CGRect(origin: .zero, size: points))]
        p.cursor.visible = false
        p.cursor.clickEffect = effect
        let log = CursorLog(samples: [.init(t: 0, x: 0.5, y: 0.5), .init(t: 10, x: 0.5, y: 0.5)],
                            clicks: [.init(t: 2, x: 0.5, y: 0.5)])
        return RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [p.clips[0].id: log]))
    }

    var screen: CIImage {
        let stripes = CIFilter(name: "CIStripesGenerator", parameters: [
            "inputColor0": CIColor.black, "inputColor1": CIColor.white, "inputWidth": 9,
        ])!.outputImage!
        return stripes.cropped(to: CGRect(x: 0, y: 0, width: 3024, height: 1964))
    }

    func pixels(_ effect: ClickEffect, at t: Double) throws -> [UInt8] {
        let renderer = FrameRenderer()
        let image = renderer.render(scene: scene(effect), time: t, screen: screen, camera: nil)
        let rect = CGRect(x: out.width / 2 - 200, y: out.height / 2 - 200, width: 400, height: 400)
        let cg = try XCTUnwrap(renderer.context.createCGImage(image, from: rect))
        var px = [UInt8](repeating: 0, count: 400 * 400 * 4)
        let ctx = CGContext(data: &px, width: 400, height: 400, bitsPerComponent: 8, bytesPerRow: 1600,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 400, height: 400))
        return px
    }

    func changed(_ a: [UInt8], _ b: [UInt8]) -> Int { zip(a, b).filter { abs(Int($0) - Int($1)) > 8 }.count }

    func testActiveClicks() {
        let s = scene(.ripple)
        XCTAssertTrue(s.clicks(at: 1.9, lasting: 0.5).isEmpty)
        XCTAssertEqual(s.clicks(at: 2.2, lasting: 0.5).first?.age ?? 0, 0.2, accuracy: 1e-9)
        XCTAssertTrue(s.clicks(at: 2.6, lasting: 0.5).isEmpty)
    }

    func testLiquidKernelCompiles() {
        XCTAssertTrue(FrameRenderer.hasLiquidKernel)
    }

    func testEffectsDrawOnlyWhileActive() throws {
        let plain = try pixels(.none, at: 2.2)
        for effect in [ClickEffect.ripple, .liquid] {
            XCTAssertGreaterThan(changed(plain, try pixels(effect, at: 2.2)), 500, "\(effect) should change the frame")
            XCTAssertEqual(changed(plain, try pixels(effect, at: 1.5)), 0, "\(effect) before the click")
            XCTAssertEqual(changed(plain, try pixels(effect, at: 2 + effect.duration + 0.1)), 0, "\(effect) after it ends")
        }
    }
}
