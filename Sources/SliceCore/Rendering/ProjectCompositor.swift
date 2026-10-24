//
//  ProjectCompositor.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/8/26.
//

import AVFoundation
import CoreImage

final class ProjectInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let screenTrackID: CMPersistentTrackID
    let cameraTrackID: CMPersistentTrackID
    let state: RenderState
    let packing: PreviewPacking?

    init(timeRange: CMTimeRange, screenTrackID: CMPersistentTrackID, cameraTrackID: CMPersistentTrackID, state: RenderState,
         packing: PreviewPacking?) {
        self.timeRange = timeRange
        self.screenTrackID = screenTrackID
        self.cameraTrackID = cameraTrackID
        self.state = state
        self.packing = packing
        requiredSourceTrackIDs = [screenTrackID, cameraTrackID]
            .filter { $0 != kCMPersistentTrackID_Invalid }
            .map { NSNumber(value: $0) }
    }
}

final class ProjectCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    static let renderer = FrameRenderer()

    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA],
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA],
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
    ]

    private let queue = DispatchQueue(label: "compositor", qos: .userInitiated)
    private let renderQueue = DispatchQueue(label: "compositor.render", qos: .userInitiated, attributes: .concurrent)
    private let inFlight = DispatchSemaphore(value: 4)
    private var renderContext: AVVideoCompositionRenderContext?
    /// Screen captures only deliver frames when something changes; hold the last one across tiny gaps.
    private var lastScreen: (time: Double, image: CIImage)?
    private var lastCamera: (time: Double, image: CIImage)?

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        queue.sync { renderContext = newRenderContext }
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async { [self] in
            guard let instruction = request.videoCompositionInstruction as? ProjectInstruction,
                  let out = renderContext?.newPixelBuffer() else {
                request.finish(with: NSError(domain: "Compositor", code: 1))
                return
            }
            let t = request.compositionTime.seconds
            var screen = request.sourceFrame(byTrackID: instruction.screenTrackID).map { CIImage(cvPixelBuffer: $0) }
            if let screen {
                lastScreen = (t, screen)
            } else if let last = lastScreen, abs(t - last.time) < 0.5 {
                screen = last.image
            }
            let size = CGSize(width: CVPixelBufferGetWidth(out), height: CVPixelBufferGetHeight(out))
            let project = instruction.state.current().project
            // Past the end of a take's camera file AVFoundation keeps handing back its last frame, so the
            // take itself decides whether there is a camera.
            let clips = project.clips
            let clipIndex = project.clipStarts.lastIndex { $0 <= t } ?? 0
            let local = project.sourceTime(edited: t)?.local ?? t
            let takeHasCamera = clipIndex < clips.count && clips[clipIndex].hasCamera(at: local)
            var camera = !takeHasCamera || instruction.cameraTrackID == kCMPersistentTrackID_Invalid ? nil
                : request.sourceFrame(byTrackID: instruction.cameraTrackID).map { CIImage(cvPixelBuffer: $0) }
            if let current = camera {
                let glitches = clipIndex < clips.count ? clips[clipIndex].cameraGlitches ?? [] : []
                if glitches.contains(where: { $0.contains(local) }), let last = lastCamera, abs(t - last.time) < 0.3 {
                    camera = last.image
                } else {
                    lastCamera = (t, current)
                }
            }
            if let packing = instruction.packing {
                Self.renderer.context.render(packing.pack(screen: screen, camera: camera, clip: clipIndex), to: out,
                                             bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
                request.finish(withComposedVideoFrame: out)
                return
            }
            let (scene, options) = instruction.state.snapshot(size: size)
            let other = instruction.state.transitionSources(at: t)
            inFlight.wait()
            renderQueue.async { [screen, camera, inFlight] in
                defer { inFlight.signal() }
                let image = Self.renderer.render(scene: scene, time: t, screen: screen, camera: camera, other: other,
                                                 options: options)
                Self.renderer.context.render(image, to: out, bounds: CGRect(origin: .zero, size: size),
                                             colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
                request.finish(withComposedVideoFrame: out)
            }
        }
    }

    func cancelAllPendingVideoCompositionRequests() {}
}
