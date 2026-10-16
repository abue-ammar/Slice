//
//  TransitionRenderer.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/14/26.
//

import CoreImage
import CoreVideo
import Foundation

public struct TransitionSources {
    public var screen: CIImage?
    public var camera: CIImage?
    public var incoming: Bool

    public init(screen: CIImage?, camera: CIImage?, incoming: Bool) {
        self.screen = screen
        self.camera = camera
        self.incoming = incoming
    }
}

final class HeldFrameCache: @unchecked Sendable {
    struct Key: Equatable {
        var join: Double
        var incoming: Bool
        var size: CGSize
        var project: Project
        var hideCamera: Bool
        var ignoreZoom: Bool
    }

    private let lock = NSLock()
    private var entry: (key: Key, image: CIImage)?

    func image(for key: Key, render: () -> CIImage?) -> CIImage? {
        lock.lock()
        defer { lock.unlock() }
        if let entry, entry.key == key { return entry.image }
        guard let image = render() else { return nil }
        entry = (key, image)
        return image
    }
}

extension FrameRenderer {
    public func render(scene: RenderScene, time t: Double, screen: CIImage?, camera: CIImage?, other: TransitionSources?,
                       options: Options = Options()) -> CIImage {
        guard let other, other.screen != nil, let (placed, progress) = scene.transitions.active(at: t) else {
            return render(scene: scene, time: t, screen: screen, camera: camera, options: options)
        }
        var layer = options
        layer.clearBackground = true
        let key = HeldFrameCache.Key(join: placed.window.time, incoming: other.incoming, size: scene.output, project: scene.project,
                                     hideCamera: options.hideCamera, ignoreZoom: options.ignoreZoom)
        let held = heldFrames.image(for: key) {
            let edge = placed.window.time + (other.incoming ? 1e-3 : -1e-3)
            return rasterized(render(scene: scene, time: edge, screen: other.screen, camera: other.camera, options: layer))
        }
        guard let held else { return render(scene: scene, time: t, screen: screen, camera: camera, options: options) }
        let played = render(scene: scene, time: t, screen: screen, camera: camera, options: layer)
        let (from, to) = other.incoming ? (played, held) : (held, played)
        let backdrop = backdrop(scene: scene, time: t, options: options)
        return Self.blend(from: from, to: to, over: backdrop, transition: placed.transition, progress: progress, size: scene.output)
    }

    private func rasterized(_ image: CIImage) -> CIImage? {
        let e = image.extent
        guard e.width >= 1, e.height >= 1, e.width.isFinite, e.height.isFinite else { return nil }
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
                                         kCVPixelBufferMetalCompatibilityKey as String: true]
        CVPixelBufferCreate(nil, Int(e.width), Int(e.height), kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
        guard let buffer, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let destination = CIRenderDestination(pixelBuffer: buffer)
        destination.colorSpace = space
        _ = try? context.startTask(toRender: image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY)),
                                   to: destination)
        return CIImage(cvPixelBuffer: buffer, options: [.colorSpace: space])
            .transformed(by: CGAffineTransform(translationX: e.minX, y: e.minY))
    }

    public static func blend(from: CIImage, to: CIImage, over backdrop: CIImage? = nil, transition: ClipTransition,
                             progress: Double, size: CGSize) -> CIImage {
        let frame = CGRect(origin: .zero, size: size)
        let p = min(max(progress, 0), 1)
        let backdrop = backdrop ?? CIImage(color: .black).cropped(to: frame)
        let blurry = switch transition.kind {
        case .zoomBlur: 0.15 * (1 - cos(2 * .pi * p)) > 0.012
        case .burn: 0.03 * sin(.pi * p) > 0.0015
        default: false
        }
        let scale: CGFloat = blurry ? 0.5 : 1
        let shrink = CGAffineTransform(scaleX: scale, y: scale)
        let small = CGSize(width: size.width * scale, height: size.height * scale)
        let area = CGRect(origin: .zero, size: small)
        guard let kernel = transitionKernels?[transition.kind.kernel],
              let image = kernel.apply(extent: area, roiCallback: { _, _ in area },
                                       arguments: [from.transformed(by: shrink).clampedToExtent(),
                                                   to.transformed(by: shrink).clampedToExtent(), Float(p),
                                                   CIVector(x: small.width, y: small.height)])
        else {
            return to.faded(p).composited(over: from.faded(1 - p)).composited(over: backdrop).cropped(to: frame)
        }
        var out = image.transformed(by: shrink.inverted()).samplingLinear().cropped(to: frame).composited(over: backdrop)
        if transition.kind == .burn, let light = burnLight(progress: p, size: size) {
            out = light.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: out])
        }
        return out.cropped(to: frame)
    }

    private static func burnLight(progress: Double, size: CGSize) -> CIImage? {
        let small = CGSize(width: (size.width / 8).rounded(.up), height: (size.height / 8).rounded(.up))
        guard let kernel = transitionKernels?["burnLight"],
              let light = kernel.apply(extent: CGRect(origin: .zero, size: small), roiCallback: { _, r in r },
                                       arguments: [Float(progress), CIVector(x: small.width, y: small.height)])
        else { return nil }
        return light.samplingLinear()
            .transformed(by: CGAffineTransform(scaleX: size.width / small.width, y: size.height / small.height))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    static let transitionKernels: [String: CIKernel]? = {
        guard let url = Bundle.module.url(forResource: "Transitions", withExtension: "metal.txt"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        do {
            // Each from its own copy of the source: Core Image mixes up kernels with the same signature that were
            // compiled from one string, drawing the first for all of them.
            var kernels: [String: CIKernel] = [:]
            for name in ClipTransition.Kind.allCases.map(\.kernel) + ["burnLight"] {
                kernels[name] = try CIKernel.kernels(withMetalString: source + "\n// \(name)\n").first { $0.name == name }
            }
            return kernels
        } catch {
            NSLog("Transition kernels failed to compile: \(error)")
            return nil
        }
    }()

    public func warmUpTransitions() {
        let frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        let image = CIImage(color: .gray).cropped(to: frame)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary, &buffer)
        guard let buffer else { return }
        for kind in ClipTransition.Kind.allCases {
            let picture = Self.blend(from: image, to: image, transition: ClipTransition(clipID: UUID(), time: 0, kind: kind),
                                     progress: 0.5, size: frame.size)
            _ = try? context.startTask(toRender: picture, to: CIRenderDestination(pixelBuffer: buffer)).waitUntilCompleted()
        }
    }
}

extension ClipTransition.Kind {
    var kernel: String {
        switch self {
        case .zoomBlur: "zoomBlurTransition"
        case .pageCurl: "pageCurlTransition"
        case .revolve: "revolveTransition"
        case .burn: "burnTransition"
        case .waveScramble: "waveScrambleTransition"
        case .snap: "snapTransition"
        }
    }
}

private extension CIImage {
    func faded(_ alpha: Double) -> CIImage {
        let a = min(max(alpha, 0), 1)
        if a >= 1 { return self }
        if a <= 0 { return CIImage(color: .clear).cropped(to: extent) }
        return applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: a)])
    }
}
