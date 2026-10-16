//
//  Device3DTests+Rendering.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/15/26.
//

import AppKit
import AVFoundation
import CoreImage
@testable import SliceCore
import XCTest

extension Device3DTests {
    func testRecordingIsDrawnUprightOnThePhonesDisplay() throws {
        let out = CGSize(width: 1080, height: 1920)
        let p = Self.deviceProject()
        let image = render(p, output: out)
        try write(image, size: out, "3d_portrait")
        let px = pixels(image, size: out)
        close(px(540, 960 - 400), Self.green)
        close(px(540, 960 + 400), Self.magenta)
        XCTAssertTrue((0 ..< 1080).contains { isOrange(px($0, 960)) }, "the Cosmic Orange frame is around the display")

        var flat = p
        flat.device3D.enabled = false
        let px2 = pixels(render(flat, output: out), size: out)
        XCTAssertFalse((0 ..< 1080).contains { isOrange(px2($0, 960)) }, "switched off, the take is drawn flat again")

        var blue = p
        blue.device3D.finish = .deepBlue
        let px3 = pixels(render(blue, output: out), size: out)
        XCTAssertFalse((0 ..< 1080).contains { isOrange(px3($0, 960)) })
        close(px3(540, 960 + 400), Self.magenta)
    }

    func testLandscapeTakesTurnThePhoneOnItsSide() throws {
        let canvas = CGSize(width: 1434, height: 660)
        let out = CGSize(width: 1920, height: 1080)
        let p = Self.deviceProject(canvas: canvas)
        let image = render(p, output: out, screen: Self.display(canvas, landscape: true))
        try write(image, size: out, "3d_landscape")
        let px = pixels(image, size: out)
        close(px(960 - 400, 540), Self.green)
        close(px(960 + 400, 540), Self.magenta)
    }

    func testFramedTakesShowOnlyWhatsInTheOpening() throws {
        let catalog = DeviceTests.catalog
        let def = try XCTUnwrap(try catalog.definition(model: "17 Pro Max", color: .cosmicOrange))
        let layout = DeviceLayout(frame: def, streamSize: CGSize(width: 1320, height: 2868))
        let compositor = try XCTUnwrap(DeviceCompositor.shared)
        let frame = try compositor.textures(for: def)
        let surface = try XCTUnwrap(DeviceSurfaceRenderer(compositor: compositor, size: layout.canvas))
        var stream: CVPixelBuffer?
        CVPixelBufferCreate(nil, 1320, 2868, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary, &stream)
        try renderer.context.startTask(toRender: Self.display(CGSize(width: 1320, height: 2868)),
                                       to: CIRenderDestination(pixelBuffer: stream!)).waitUntilCompleted()
        let recorded = try XCTUnwrap(surface.renderNow(screen: stream, frame: frame, layout: layout))
        var p = Self.deviceProject(canvas: surface.size, frame: "17 Pro Max", screen: layout.screenRect)
        let cutout = try XCTUnwrap(layout.cutoutRect, "the frame's Dynamic Island is found")
        XCTAssertEqual(cutout.midX, layout.screenRect.midX, accuracy: 0.01)
        XCTAssertLessThan(cutout.maxY, layout.screenRect.minY + layout.screenRect.height * 0.08)
        p.clips[0].device?.cutout = cutout
        let out = CGSize(width: 1080, height: 1920)
        let image = render(p, output: out, screen: CIImage(cvPixelBuffer: recorded))
        try write(image, size: out, "3d_framed")
        let px = pixels(image, size: out)
        close(px(540, 960 - 400), Self.green)
        close(px(540, 960 + 400), Self.magenta)
        // Just above the 3D island, where the frame's own island used to show: the display's content again.
        XCTAssertLessThan((96 ..< 130).filter { px(540, $0).r + px(540, $0).g + px(540, $0).b < 0.15 }.count, 4,
                          "no second, flat-black island peeking out above the 3D one")
    }

    func testZoomMovesTheCameraInOnThePhone() throws {
        let out = CGSize(width: 1080, height: 1920)
        var p = Self.deviceProject()
        p.device3D.background = .color
        let edge = (x: 990, y: 1260)
        let before = pixels(render(p, output: out), size: out)(edge.x, edge.y)
        XCTAssertLessThan(before.r, 0.3, "unzoomed, that spot is off the phone")
        p.zoomBlocks = [ZoomBlock(start: 0, end: 10, scale: 2, focus: CGPoint(x: 0.5, y: 0.5))]
        p.style.zoomTransitionDuration = 0.3
        let zoomed = render(p, output: out, at: 5)
        try write(zoomed, size: out, "3d_zoomed")
        close(pixels(zoomed, size: out)(edge.x, edge.y), Self.magenta)
    }

    func testTheSameMomentRendersTheSameFrame() throws {
        let out = CGSize(width: 540, height: 960)
        var p = Self.deviceProject()
        p.device3D.yaw = 15
        p.device3D.animation.motion = .sway
        let a = render(p, output: out, at: 1.3), b = render(p, output: out, at: 1.3), c = render(p, output: out, at: 3.1)
        let pa = pixels(a, size: out), pb = pixels(b, size: out), pc = pixels(c, size: out)
        var same = true, differs = false
        for y in stride(from: 0, to: 960, by: 37) {
            for x in stride(from: 0, to: 540, by: 23) {
                let u = pa(x, y), v = pb(x, y), w = pc(x, y)
                if abs(u.r - v.r) > 0.01 || abs(u.g - v.g) > 0.01 || abs(u.b - v.b) > 0.01 { same = false }
                if abs(u.r - w.r) > 0.1 || abs(u.g - w.g) > 0.1 { differs = true }
            }
        }
        XCTAssertTrue(same, "preview, scrubbing and export agree")
        XCTAssertTrue(differs, "the sway moves the phone")
        try write(c, size: out, "3d_sway")
    }

    func testStudioBackgroundAndDrawSpeed() throws {
        let out = CGSize(width: 1080, height: 1920)
        var p = Self.deviceProject()
        p.device3D.background = .studio
        p.device3D.yaw = 16
        _ = render(p, output: out)
        let start = CACurrentMediaTime()
        var image = CIImage.empty()
        for i in 0 ..< 20 {
            image = render(p, output: out, at: Double(i) / 30)
            _ = renderer.context.createCGImage(image, from: CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let each = (CACurrentMediaTime() - start) / 20
        print("3D frame at 1080×1920: \(String(format: "%.1f", each * 1000)) ms")
        XCTAssertLessThan(each, 0.25)
        try write(image, size: out, "3d_studio")
        let corner = pixels(image, size: out)(4, 4)
        XCTAssertLessThan(corner.r, 0.2, "the studio's dark edge")
    }

    func testEveryFrameShapeShowsTheWholePhone() throws {
        for out in [CGSize(width: 1920, height: 1080), CGSize(width: 1080, height: 1080), CGSize(width: 1080, height: 1920)] {
            var p = Self.deviceProject()
            p.device3D.background = .color
            p.device3D.shadowOpacity = 0
            let image = render(p, output: out)
            try write(image, size: out, "3d_shape_\(Int(out.width))x\(Int(out.height))")
            let px = pixels(image, size: out)
            let cx = Int(out.width / 2), cy = Int(out.height / 2)
            close(px(cx, cy - Int(out.height * 0.2)), Self.green)
            close(px(cx, cy + Int(out.height * 0.2)), Self.magenta)
            // The top and bottom rows are background: the phone is inside the frame, not cropped by it.
            for x in stride(from: 0, to: Int(out.width), by: 16) {
                XCTAssertLessThan(px(x, 2).r + px(x, 2).g, 0.5, "\(out) top")
                XCTAssertLessThan(px(x, Int(out.height) - 3).r + px(x, Int(out.height) - 3).g, 0.5, "\(out) bottom")
            }
        }
    }

    func testMovedTurnedAndHugePhonesStillDraw() throws {
        let out = CGSize(width: 1280, height: 720)
        var p = Self.deviceProject()
        p.device3D.position = CGPoint(x: 0.3, y: -0.2)
        let moved = pixels(render(p, output: out), size: out)
        close(moved(640 + 384, 360 + 144 + 100), Self.magenta)
        p.device3D.position = .zero
        p.device3D.yaw = 180
        let back = pixels(render(p, output: out), size: out)
        XCTAssertFalse([Self.green, Self.magenta].contains { c in
            let q = back(640, 300)
            return abs(q.r - Double(c.red)) < 0.1 && abs(q.g - Double(c.green)) < 0.1
        }, "turned right round, the back faces the camera")
        p.device3D.yaw = 0
        p.device3D.pitch = 80
        p.device3D.scale = 4
        p.device3D.perspective = 1
        _ = render(p, output: out)
    }

    func testANarrowLensNeverSlicesThePhone() throws {
        // At the flattest perspective the camera stands far off; its depth range once sliced off the near side of a
        // turned phone, showing its inside.
        let out = CGSize(width: 1920, height: 1080)
        var p = Self.deviceProject()
        p.device3D.perspective = 0
        p.device3D.yaw = -60
        p.device3D.background = .color
        for model in Device3DModel.allCases {
            p.device3D.model = model
            let image = render(p, output: out, screen: CIImage(color: Self.magenta).cropped(to: CGRect(origin: .zero, size: Self.portraitCanvas)))
            try write(image, size: out, "3d_narrow_\(model.shortLabel)")
            let px = pixels(image, size: out)
            // Down the display's near side, where the slice was: still the recording.
            for y in [700, 800, 880] { close(px(1030, y), Self.magenta, within: 0.15) }
        }
    }

    // MARK: - Export

    /// A movie whose picture changes colour halfway through.
    static func makeTimedMovie(url: URL, size: CGSize, duration: Double, fps: Int = 30) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let ctx = CIContext()
        let frames = Int(duration * Double(fps))
        for i in 0 ..< frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            let color = i < frames / 2 ? CIColor(red: 0.9, green: 0.15, blue: 0.1) : CIColor(red: 0.1, green: 0.3, blue: 0.95)
            ctx.render(CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size)), to: pb!)
            adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let e = writer.error { throw e }
    }

    func testExportDrawsEachRecordedFrameOnThe3DDisplayAtItsTime() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export-3d-\(UUID().uuidString)")
        let (bundle, empty) = try ProjectBundle.create(name: "Export 3D", in: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let (clipDir, rel) = try bundle.makeClipFolder(id: id)
        try await Self.makeTimedMovie(url: clipDir.appendingPathComponent("screen.mov"), size: Self.portraitCanvas, duration: 4)
        var project = empty
        var clip = Clip(id: id, screenFile: "\(rel)/screen.mov", duration: 4, screenPixelSize: Self.portraitCanvas, captureRect: .zero)
        clip.device = RecordedDevice(name: "iPhone", identifier: "iPhone18,2", frame: nil, color: nil, opensIn3D: true)
        project.clips = [clip]
        project.device3D.enabled = true
        project.device3D.yaw = 0
        project.device3D.pitch = 0
        project.export.aspect = .portrait9x16
        project.export.resolution = .p1080
        project.export.fps = 30
        try bundle.save(project)

        let out = dir.appendingPathComponent("out.mp4")
        try await Exporter.export(project: project, bundle: bundle, cursor: CursorTrack(project: project, logs: [:]), to: out,
                                  progress: { _ in })
        let asset = AVURLAsset(url: out)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 4, accuracy: 0.1)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        let rate = try await track.load(.nominalFrameRate)
        XCTAssertEqual(size, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(Double(rate), 30, accuracy: 1)

        let gen = AVAssetImageGenerator(asset: asset)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        for (t, expected) in [(0.8, CIColor(red: 0.9, green: 0.15, blue: 0.1)), (3.2, CIColor(red: 0.1, green: 0.3, blue: 0.95))] {
            let (cg, _) = try await gen.image(at: CMTime(seconds: t, preferredTimescale: 600))
            let image = CIImage(cgImage: cg)
            try write(image, size: CGSize(width: 1080, height: 1920), "3d_export_\(t)")
            let px = pixels(image, size: CGSize(width: 1080, height: 1920))
            close(px(540, 960), expected, within: 0.15)
            XCTAssertTrue((0 ..< 1080).contains { isOrange(px($0, 960)) }, "exported on the 3D phone")
        }
    }
}
