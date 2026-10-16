//
//  GlitchTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/9/26.
//

import AVFoundation
import CoreImage
@testable import SliceCore
import XCTest

final class GlitchTests: XCTestCase {
    func testFindsSingleBadFrameButNotMotion() {
        func thumb(_ v: Float) -> [Float] { [Float](repeating: v, count: 32 * 18) }
        var frames: [(t: Double, thumb: [Float])] = (0 ..< 10).map { i in (Double(i) / 24, thumb(120 + Float(i) * 2)) }
        frames[5].thumb = thumb(30)
        let found = CameraGlitchDetector.glitches(in: frames)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.start ?? -1, 5.0 / 24, accuracy: 1e-9)
    }

    func testCameraWithBadFrameIsRepairedInRender() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("glitch-\(UUID().uuidString)")
        let (bundle, empty) = try ProjectBundle.create(name: "G", in: dir)
        var p = empty
        let id = UUID()
        let (clipDir, rel) = try bundle.makeClipFolder(id: id)
        try await ExportTests.makeMovie(url: clipDir.appendingPathComponent("screen.mov"),
                                        image: RenderTests.fakeScreen(size: CGSize(width: 640, height: 400)), duration: 2)
        let camURL = clipDir.appendingPathComponent("camera.mov")
        try await Self.makeCamera(url: camURL, frames: 48, fps: 24, badFrame: 24)
        let glitches = try await CameraGlitchDetector.scan(camURL)
        XCTAssertEqual(glitches.count, 1)
        XCTAssertEqual(glitches.first?.start ?? -1, 1.0, accuracy: 0.01)

        p.clips = [Clip(id: id, screenFile: "\(rel)/screen.mov", cameraFile: "\(rel)/camera.mov", duration: 2,
                        screenPixelSize: CGSize(width: 640, height: 400), captureRect: .zero)]
        p.clips[0].cameraGlitches = glitches
        p.defaultCamera = .centre(coverage: 0.5)
        p.style.mirrorCamera = false
        let lumas = try await Self.cameraCentreLuma(project: p, bundle: bundle)
        XCTAssertGreaterThan(lumas.min() ?? 0, 60, "no black frame reaches the output")
        try? FileManager.default.removeItem(at: dir)
    }

    static func makeCamera(url: URL, frames: Int, fps: Int, badFrame: Int) async throws {
        let size = CGSize(width: 320, height: 180)
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
        for i in 0 ..< frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            let v: CGFloat = i == badFrame ? 0.02 : 0.6
            ctx.render(CIImage(color: CIColor(red: v, green: v, blue: v)).cropped(to: CGRect(origin: .zero, size: size)), to: pb!)
            adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
    }

    static func cameraCentreLuma(project: Project, bundle: ProjectBundle) async throws -> [Double] {
        let state = RenderState(project: project, cursor: CursorTrack(project: project, logs: [:]))
        let built = try await CompositionBuilder.build(project: project, bundle: bundle, state: state,
                                                       renderSize: CGSize(width: 640, height: 360), fps: 30)
        let reader = try AVAssetReader(asset: built.composition)
        let out = AVAssetReaderVideoCompositionOutput(videoTracks: try await built.composition.loadTracks(withMediaType: .video),
                                                      videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        out.videoComposition = built.videoComposition
        reader.add(out)
        reader.startReading()
        var lumas: [Double] = []
        while let sb = out.copyNextSampleBuffer() {
            guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
            CVPixelBufferLockBaseAddress(pb, .readOnly)
            let bpr = CVPixelBufferGetBytesPerRow(pb)
            let p = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
            let i = 180 * bpr + 320 * 4
            lumas.append(0.3 * Double(p[i + 2]) + 0.59 * Double(p[i + 1]) + 0.11 * Double(p[i]))
            CVPixelBufferUnlockBaseAddress(pb, .readOnly)
        }
        return Array(lumas.dropFirst(2))
    }
}
