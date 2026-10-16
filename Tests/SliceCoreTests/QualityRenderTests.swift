//
//  QualityRenderTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/14/26.
//

import AppKit
import AVFoundation
import CoreImage
@testable import SliceCore
import XCTest

/// Visual checks written to RENDER_OUT. CAMERA_SAMPLE (a movie with a person) enables the blur check.
final class QualityRenderTests: XCTestCase {
    private func write(_ image: CIImage, size: CGSize, _ name: String, renderer: FrameRenderer) throws {
        let cg = try XCTUnwrap(renderer.context.createCGImage(image, from: CGRect(origin: .zero, size: size)))
        guard let dir = ProcessInfo.processInfo.environment["RENDER_OUT"] else { return }
        try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
    }

    func testZoomedLowResScreenAt4K() throws {
        var p = Project(name: "Q")
        let size = CGSize(width: 1554, height: 744)
        p.clips = [Clip(screenFile: "s", duration: 10, screenPixelSize: size, captureRect: .zero)]
        p.zoomBlocks = [ZoomBlock(start: 0, end: 10, scale: 2, focus: CGPoint(x: 0.35, y: 0.3))]
        p.defaultCamera = .hidden
        let out = OutputAspect.landscape16x9.size(shortSide: 2160)
        let renderer = FrameRenderer()
        let scene = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
        try write(renderer.render(scene: scene, time: 5, screen: RenderTests.fakeScreen(size: size), camera: nil),
                  size: out, "q_zoom4k.png", renderer: renderer)
    }

    func testCameraBackgroundBlur() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAMERA_SAMPLE"] else { throw XCTSkip("CAMERA_SAMPLE not set") }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
        let (cg, _) = try await gen.image(at: CMTime(seconds: 1, preferredTimescale: 600))
        let camera = CIImage(cgImage: cg)
        var p = Project(name: "B")
        p.clips = [Clip(screenFile: "s", duration: 10, screenPixelSize: CGSize(width: 1920, height: 1080), captureRect: .zero)]
        p.defaultCamera = .centre(coverage: 0.8)
        let out = OutputAspect.landscape16x9.size(shortSide: 1080)
        let renderer = FrameRenderer()
        for blur in [0.0, 0.7] {
            p.style.cameraBackgroundBlur = blur
            let scene = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
            let start = Date()
            let image = renderer.render(scene: scene, time: 1, screen: RenderTests.fakeScreen(size: CGSize(width: 1920, height: 1080)),
                                        camera: camera, options: .init(accurateSegmentation: true))
            try write(image, size: out, "q_blur_\(blur).png", renderer: renderer)
            print("blur \(blur): \(Int(Date().timeIntervalSince(start) * 1000))ms")
        }
    }

    func testCaptionRendering() throws {
        var p = Project(name: "C")
        p.clips = [Clip(screenFile: "s", duration: 10, screenPixelSize: CGSize(width: 3024, height: 1964), captureRect: .zero)]
        p.subtitles.burnIn = true
        let text = "So this is the dashboard, and here you can see every citation we tracked this week."
        let words = text.split(separator: " ").enumerated().map { i, w in Word(text: String(w), start: Double(i) * 0.3, end: Double(i) * 0.3 + 0.25) }
        let renderer = FrameRenderer()
        for (name, aspect, layout) in [("cap_16x9", OutputAspect.landscape16x9, CameraLayout.corner(.bottomRight, .square, .large)),
                                       ("cap_9x16", OutputAspect.portrait9x16, CameraLayout.corner(.bottomLeft, .portrait, .small))] {
            p.defaultCamera = layout
            let caps = CaptionBuilder.captions(project: p, transcripts: [p.clips[0].id: Transcript(locale: "en", words: words)],
                                               maxCharacters: aspect == .landscape16x9 ? 48 : 30)
            XCTAssertGreaterThan(caps.count, 1)
            let out = aspect.size(shortSide: 1080)
            let scene = RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [:]))
            let image = renderer.render(scene: scene, time: 1.0, screen: RenderTests.fakeScreen(size: CGSize(width: 3024, height: 1964)),
                                        camera: RenderTests.fakeCamera(), options: .init(captions: caps))
            try write(image, size: out, "\(name).png", renderer: renderer)
        }
    }
}
