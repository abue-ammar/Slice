//
//  ExportTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/2/26.
//

import AVFoundation
import CoreImage
@testable import SliceCore
import XCTest

final class ExportTests: XCTestCase {
    static func makeMovie(url: URL, image: CIImage, duration: Double, fps: Int = 30) async throws {
        let size = image.extent.size
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
            let x = size.width * CGFloat(i) / CGFloat(frames)
            let bar = CIImage(color: .red).cropped(to: CGRect(x: x, y: 0, width: size.width * 0.02, height: size.height * 0.03))
            ctx.render(bar.composited(over: image), to: pb!)
            adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let e = writer.error { throw e }
    }

    func testTwoClipExport() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export-test-\(UUID().uuidString)")
        let (bundle, empty) = try ProjectBundle.create(name: "Export", in: dir)
        var project = empty
        let screen = RenderTests.fakeScreen(size: CGSize(width: 1512, height: 982))
        let camera = RenderTests.fakeCamera().transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))

        let a = UUID(), b = UUID()
        let (dirA, relA) = try bundle.makeClipFolder(id: a)
        let (dirB, relB) = try bundle.makeClipFolder(id: b)
        try await Self.makeMovie(url: dirA.appendingPathComponent("screen.mov"), image: screen, duration: 3)
        try await Self.makeMovie(url: dirA.appendingPathComponent("camera.mov"), image: camera, duration: 3)
        try await Self.makeMovie(url: dirB.appendingPathComponent("screen.mov"), image: screen, duration: 2)
        project.clips = [
            Clip(id: a, screenFile: "\(relA)/screen.mov", cameraFile: "\(relA)/camera.mov", duration: 3,
                 screenPixelSize: CGSize(width: 1512, height: 982), captureRect: .zero),
            Clip(id: b, screenFile: "\(relB)/screen.mov", duration: 2,
                 screenPixelSize: CGSize(width: 1512, height: 982), captureRect: .zero),
        ]
        project.zoomBlocks = [ZoomBlock(start: 1, end: 4, scale: 2, focus: CGPoint(x: 0.8, y: 0.15))]
        project.export.aspect = .landscape16x9
        project.export.resolution = .p1080
        project.export.fps = 30
        try bundle.save(project)
        XCTAssertEqual(try bundle.load(), project)

        let out = dir.appendingPathComponent("out.mp4")
        try await Exporter.export(project: project, bundle: bundle, cursor: CursorTrack(project: project, logs: [:]),
                                  to: out, progress: { _ in })
        let asset = AVURLAsset(url: out)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 5, accuracy: 0.1)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 1920, height: 1080))
        let rate = try await track.load(.estimatedDataRate)
        XCTAssertGreaterThan(Double(rate), Double(project.export.bitRate(for: size)) * 0.2)

        project.export.aspect = .auto
        project.export.fps = 60
        project.export.hevc = false
        let auto = dir.appendingPathComponent("auto.mp4")
        try await Exporter.export(project: project, bundle: bundle, cursor: CursorTrack(project: project, logs: [:]),
                                  to: auto, progress: { _ in })
        let autoTracks = try await AVURLAsset(url: auto).loadTracks(withMediaType: .video)
        let autoTrack = try XCTUnwrap(autoTracks.first)
        let autoSize = try await autoTrack.load(.naturalSize)
        XCTAssertEqual(autoSize.height, 1080)
        XCTAssertEqual(autoSize.width / autoSize.height, 1512 / 982, accuracy: 0.01)
        let autoRate = try await autoTrack.load(.nominalFrameRate)
        XCTAssertEqual(Double(autoRate), 60, accuracy: 1)

        if let outDir = ProcessInfo.processInfo.environment["RENDER_OUT"] {
            let gen = AVAssetImageGenerator(asset: asset)
            gen.requestedTimeToleranceBefore = .zero
            gen.requestedTimeToleranceAfter = .zero
            for t in [0.5, 2.5, 4.5] {
                let (cg, _) = try await gen.image(at: CMTime(seconds: t, preferredTimescale: 600))
                let rep = NSBitmapImageRep(cgImage: cg)
                try rep.representation(using: .png, properties: [:])!
                    .write(to: URL(fileURLWithPath: outDir).appendingPathComponent("export_\(t).png"))
            }
        }
        try? FileManager.default.removeItem(at: dir)
    }
}
