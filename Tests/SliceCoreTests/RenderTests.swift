//
//  RenderTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/10/26.
//

import AppKit
import CoreImage
@testable import SliceCore
import XCTest

/// Renders sample frames. Set RENDER_OUT to a directory to also write PNGs for eyeballing.
final class RenderTests: XCTestCase {
    static func fakeScreen(size: CGSize) -> CIImage {
        let img = NSImage(size: size, flipped: true) { rect in
            NSColor(white: 0.97, alpha: 1).setFill()
            rect.fill()
            NSColor(calibratedRed: 0.15, green: 0.17, blue: 0.22, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: size.width, height: size.height * 0.05).fill()
            NSColor(calibratedRed: 0.9, green: 0.92, blue: 0.95, alpha: 1).setFill()
            NSRect(x: 0, y: size.height * 0.05, width: size.width * 0.18, height: size.height).fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size.height * 0.025),
                                                        .foregroundColor: NSColor.black]
            for i in 0 ..< 18 {
                let y = size.height * (0.1 + Double(i) * 0.048)
                ("Row \(i + 1) - the quick brown fox jumps over the lazy dog" as NSString)
                    .draw(at: NSPoint(x: size.width * 0.22, y: y), withAttributes: attrs)
            }
            NSColor.systemBlue.setFill()
            NSBezierPath(roundedRect: NSRect(x: size.width * 0.78, y: size.height * 0.1, width: size.width * 0.16,
                                             height: size.height * 0.07), xRadius: 12, yRadius: 12).fill()
            return true
        }
        let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        return CIImage(cgImage: cg)
    }

    static func fakeCamera() -> CIImage {
        let f = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: 960, y: 480), "inputRadius0": 80, "inputRadius1": 700,
            "inputColor0": CIColor(red: 1, green: 0.8, blue: 0.6), "inputColor1": CIColor(red: 0.1, green: 0.3, blue: 0.4),
        ])!
        let bg = f.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let marker = CIImage(color: .red).cropped(to: CGRect(x: 60, y: 880, width: 60, height: 160))
        return marker.composited(over: bg)
    }

    func testRenderSampleFrames() throws {
        var p = Project(name: "Render")
        p.clips = [Clip(screenFile: "s.mov", duration: 30, screenPixelSize: CGSize(width: 3024, height: 1964),
                        captureRect: .zero)]
        p.defaultCamera = .corner(.bottomRight, .square, .small)
        p.cameraBlocks = [CameraBlock(start: 10, end: 20, layout: .centre(coverage: 0.6)),
                          CameraBlock(start: 20, end: 30, layout: .hidden)]
        p.zoomBlocks = [ZoomBlock(start: 4, end: 9, scale: 2.2, focus: CGPoint(x: 0.86, y: 0.13))]
        let screen = Self.fakeScreen(size: CGSize(width: 3024, height: 1964))
        let camera = Self.fakeCamera()
        let renderer = FrameRenderer()
        let outDir = ProcessInfo.processInfo.environment["RENDER_OUT"].map { URL(fileURLWithPath: $0) }

        let frames: [(String, OutputAspect, Double)] = [
            ("a_idle", .landscape16x9, 1), ("b_zooming", .landscape16x9, 4.25), ("c_zoomed", .landscape16x9, 6),
            ("d_cam_transition", .landscape16x9, 10.25), ("e_cam_centre", .landscape16x9, 12),
            ("f_portrait", .portrait9x16, 1), ("g_square", .square1x1, 6), ("h_portrait_centre", .portrait9x16, 12),
        ]
        for (name, aspect, t) in frames {
            let out = aspect.size(shortSide: 1080)
            let scene = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
            let image = renderer.render(scene: scene, time: t, screen: screen, camera: camera)
            let start = Date()
            let cg = try XCTUnwrap(renderer.context.createCGImage(image, from: CGRect(origin: .zero, size: out)))
            print("render \(name): \(Int(Date().timeIntervalSince(start) * 1000))ms")
            XCTAssertEqual(cg.width, Int(out.width))
            if let outDir {
                let rep = NSBitmapImageRep(cgImage: cg)
                try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent("\(name).png"))
            }
        }
    }

    func testSplitAndFullscreenCamera() throws {
        var p = Project(name: "Split")
        p.clips = [Clip(screenFile: "s.mov", duration: 30, screenPixelSize: CGSize(width: 3024, height: 1964),
                        captureRect: .zero)]
        p.defaultCamera = .corner(.bottomRight, .square, .small)
        p.cameraBlocks = [CameraBlock(start: 5, end: 12, layout: .split(.right)),
                          CameraBlock(start: 12, end: 18, layout: .fullscreen)]
        p.zoomBlocks = [ZoomBlock(start: 8, end: 11, scale: 2, focus: CGPoint(x: 0.3, y: 0.3))]
        let screen = Self.fakeScreen(size: CGSize(width: 3024, height: 1964))
        let camera = Self.fakeCamera()
        let renderer = FrameRenderer()
        let outDir = ProcessInfo.processInfo.environment["RENDER_OUT"].map { URL(fileURLWithPath: $0) }
        let frames: [(String, OutputAspect, Double)] = [
            ("split_in", .landscape16x9, 5.15), ("split", .landscape16x9, 7), ("split_zoomed", .landscape16x9, 9.5),
            ("split_to_full", .landscape16x9, 12.15), ("full", .landscape16x9, 14), ("split_portrait", .portrait9x16, 7),
        ]
        for (name, aspect, t) in frames {
            let out = aspect.size(shortSide: 1080)
            let scene = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
            let image = renderer.render(scene: scene, time: t, screen: screen, camera: camera)
            let cg = try XCTUnwrap(renderer.context.createCGImage(image, from: CGRect(origin: .zero, size: out)))
            if let outDir {
                try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
                    .write(to: outDir.appendingPathComponent("\(name).png"))
            }
        }
        let out = OutputAspect.landscape16x9.size(shortSide: 1080)
        let scene = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
        let split = scene.cameraState(at: 7)
        let slot = ScreenSlot.rect(split.screenSlot, in: out)
        XCTAssertEqual(slot.width / slot.height, 3024 / 1964, accuracy: 0.01)
        XCTAssertEqual(split.rect.minX, slot.maxX, accuracy: 0.5)
        XCTAssertEqual(split.rect.minY, slot.minY, accuracy: 0.5)
        XCTAssertEqual(split.rect.height, slot.height, accuracy: 0.5)
        XCTAssertEqual(slot.minX, out.width - split.rect.maxX, accuracy: 0.5)
        XCTAssertEqual(split.seamEdge, .minXEdge)
        XCTAssertEqual(scene.cameraState(at: 9.5).rect, split.rect)
        XCTAssertEqual(scene.cameraState(at: 14).rect, CGRect(origin: .zero, size: out))
        XCTAssertEqual(scene.cameraState(at: 14).screenSlot, ScreenSlot.full)
        let moving = scene.cameraState(at: 5.15).screenSlot
        XCTAssertTrue(moving.width < 1 && moving.width > split.screenSlot.width)
    }

    func testCameraMotionBlur() throws {
        var p = Project(name: "Camera blur")
        p.clips = [Clip(screenFile: "s.mov", duration: 20, screenPixelSize: CGSize(width: 3024, height: 1964),
                        captureRect: .zero)]
        p.defaultCamera = .centre(coverage: 0.9)
        p.cameraBlocks = [CameraBlock(start: 5, end: 12, layout: .corner(.bottomRight, .square, .small))]
        p.zoomBlocks = [ZoomBlock(start: 8, end: 12, scale: 2, focus: CGPoint(x: 0.3, y: 0.3))]
        let screen = Self.fakeScreen(size: CGSize(width: 3024, height: 1964))
        let camera = Self.fakeCamera()
        let renderer = FrameRenderer()
        let out = OutputAspect.landscape16x9.size(shortSide: 1080)
        let outDir = ProcessInfo.processInfo.environment["RENDER_OUT"].map { URL(fileURLWithPath: $0) }
        func render(_ t: Double, blur: Bool) throws -> CGImage {
            p.style.motionBlur = blur
            let scene = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
            let image = renderer.render(scene: scene, time: t, screen: screen, camera: camera)
            return try XCTUnwrap(renderer.context.createCGImage(image, from: CGRect(origin: .zero, size: out)))
        }
        func pixels(_ cg: CGImage) -> [UInt8] {
            let rep = NSBitmapImageRep(cgImage: cg)
            return Array(UnsafeBufferPointer(start: rep.bitmapData, count: rep.bytesPerRow * rep.pixelsHigh))
        }
        for (name, t) in [("cam_blur_move", 5.25), ("cam_blur_zoom", 8.4), ("cam_blur_still", 7.0)] {
            let blurred = try render(t, blur: true), sharp = try render(t, blur: false)
            let differs = zip(pixels(blurred), pixels(sharp)).contains { abs(Int($0) - Int($1)) > 8 }
            XCTAssertEqual(differs, name != "cam_blur_still", name)
            if let outDir {
                try NSBitmapImageRep(cgImage: blurred).representation(using: .png, properties: [:])!
                    .write(to: outDir.appendingPathComponent("\(name).png"))
            }
        }
    }

    func testImageBackgroundAndNoPadding() throws {
        var p = Project(name: "BG")
        p.clips = [Clip(screenFile: "s.mov", duration: 10, screenPixelSize: CGSize(width: 3024, height: 1964), captureRect: .zero)]
        p.style.backgroundImage = "backgrounds/bg.png"
        let screen = Self.fakeScreen(size: CGSize(width: 3024, height: 1964))
        let camera = Self.fakeCamera()
        let stripes = CIFilter(name: "CIStripesGenerator", parameters: [
            "inputColor0": CIColor(red: 0.1, green: 0.5, blue: 0.3), "inputColor1": CIColor(red: 0.9, green: 0.8, blue: 0.2),
            "inputWidth": 120,
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 1200, height: 1600))
        let renderer = FrameRenderer()
        let out = OutputAspect.landscape16x9.size(shortSide: 1080)
        let outDir = ProcessInfo.processInfo.environment["RENDER_OUT"].map { URL(fileURLWithPath: $0) }
        for full in [false, true] {
            p.style.padding = full ? 0 : FrameStyle().padding
            let scene = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
            let g = scene.geometry(at: 1)
            if full {
                XCTAssertTrue(CGRect(origin: .zero, size: out).insetBy(dx: -1, dy: -1).contains(g.contentRect), "never crops")
                XCTAssertEqual(g.contentRect.height, 1080, accuracy: 1)
            } else {
                XCTAssertEqual(g.contentRect.height, 1080 * (1 - 2 * p.style.padding), accuracy: 1)
            }
            let image = renderer.render(scene: scene, time: 1, screen: screen, camera: camera,
                                        options: .init(backgroundImage: stripes))
            let cg = try XCTUnwrap(renderer.context.createCGImage(image, from: CGRect(origin: .zero, size: out)))
            if let outDir {
                try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
                    .write(to: outDir.appendingPathComponent(full ? "bg_full.png" : "bg_image.png"))
            }
        }
    }

    func testNoBackgroundWithoutPadding() {
        let size = CGSize(width: 1600, height: 900)
        var p = Project(name: "P")
        p.clips = [Clip(screenFile: "a", duration: 5, screenPixelSize: size, captureRect: .zero)]
        p.style.padding = 0
        p.style.backgroundTop = RGBA(1, 0, 0)
        p.style.backgroundBottom = RGBA(1, 0, 0)
        p.export.aspect = .auto
        let scene = RenderScene(project: p, output: size, cursor: CursorTrack(project: p, logs: [:]))
        var screen = CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        for corner in [CGPoint(x: 0, y: 0), CGPoint(x: size.width - 40, y: 0), CGPoint(x: 0, y: size.height - 40),
                       CGPoint(x: size.width - 40, y: size.height - 40)] {
            screen = screen.applyingFilter("CISourceOutCompositing", parameters: [
                kCIInputBackgroundImageKey: CIImage(color: .white).cropped(to: CGRect(origin: corner, size: CGSize(width: 40, height: 40))),
            ])
        }
        let image = FrameRenderer().render(scene: scene, time: 1, screen: screen, camera: nil)
        var px = [UInt8](repeating: 0, count: 4)
        CIContext().render(image, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 5, y: 5, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        XCTAssertLessThan(Int(px[0]), 20, "No red background in the corner")
    }
}
