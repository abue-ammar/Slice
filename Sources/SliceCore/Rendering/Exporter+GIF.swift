//
//  Exporter+GIF.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/17/26.
//

import AVFoundation

extension Exporter {
    static func exportGIF(project: Project, bundle: ProjectBundle, cursor: CursorTrack, captions: [Caption], to url: URL,
                          progress: @escaping @Sendable (Double) -> Void) async throws {
        let size = project.exportSize
        let built = try await build(project: project, bundle: bundle, cursor: cursor, captions: captions, size: size,
                                    fps: project.export.gifFPS)
        let total = max(project.duration, 0.001)

        let reader = try AVAssetReader(asset: built.composition)
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: try await built.composition.loadTracks(withMediaType: .video),
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()])
        output.videoComposition = built.videoComposition
        output.alwaysCopiesSampleData = false
        reader.add(output)

        let encoder = try GIFEncoder(url: url, width: Int(size.width), height: Int(size.height))
        do {
            guard reader.startReading() else { throw reader.error ?? Failure.failed("Couldn't read the project's media.") }
            let cancel = ReaderBox(reader: reader)
            let job = GIFJob(output: output, encoder: encoder)
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                    DispatchQueue(label: "export.gif").async {
                        do {
                            try job.run(total: total, progress: progress)
                            done.resume()
                        } catch {
                            done.resume(throwing: error)
                        }
                    }
                }
            } onCancel: {
                cancel.reader.cancelReading()
            }
            if Task.isCancelled || reader.status == .cancelled { throw CancellationError() }
            if reader.status == .failed { throw reader.error ?? Failure.failed("Reading the project failed.") }
            try encoder.finish(duration: total)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        progress(1)
    }
}

private struct GIFJob: @unchecked Sendable {
    let output: AVAssetReaderOutput
    let encoder: GIFEncoder

    func run(total: Double, progress: (Double) -> Void) throws {
        var time = 0.0
        while let sample = output.copyNextSampleBuffer() {
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if t.isFinite { time = t }
            CVPixelBufferLockBaseAddress(pixels, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(pixels), CVPixelBufferGetWidth(pixels) == encoder.width,
                  CVPixelBufferGetHeight(pixels) == encoder.height
            else { throw Exporter.Failure.failed("The rendered frames came out at the wrong size.") }
            try encoder.add(bgra: base, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), time: time)
            progress(min(time / total, 0.999))
        }
    }
}
