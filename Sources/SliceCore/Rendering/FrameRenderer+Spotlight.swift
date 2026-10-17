//
//  FrameRenderer+Spotlight.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/17/26.
//

import CoreImage

extension FrameRenderer {
    static let spotlightKernel = kernel("clickSpotlight", in: "ClickSpotlight", label: "Click spotlight")

    static var hasSpotlightKernel: Bool { spotlightKernel != nil }

    /// The screen with what's around the latest click dimmed or blurred. It's done before the screen is framed, like
    /// redaction, so the circle stays on what was clicked through zooms, tilts, splits and the 3D phone, and the
    /// pointer (drawn over it later) stays crisp.
    func spotlit(_ screen: CIImage, scene: RenderScene, time t: Double) -> CIImage {
        guard let state = scene.spotlight(at: t), let kernel = Self.spotlightKernel else { return screen }
        let e = screen.extent
        guard e.width >= 1, e.height >= 1, !e.isInfinite else { return screen }
        let clips = scene.project.clips
        let i = scene.clipIndex(at: t)
        let points = clips.indices.contains(i) && clips[i].captureRect.width > 0 ? clips[i].captureRect.width : 1440
        let px = e.width / points
        let a = min(max(state.amount, 0), 1)
        let radius = ClickSpotlight.radius * CGFloat(max(state.size, 0.1)) * px * (1 + ClickSpotlight.iris * CGFloat(1 - a))
        let center = CGPoint(x: e.minX + state.center.x * e.width, y: e.minY + (1 - state.center.y) * e.height)

        var quiet = screen
        var blend = 0.0
        let darkness = min(max(state.darkness, 0), 1) * a
        // The blur grows in and out with the circle rather than cross-fading, which would ghost.
        let blurPoints = ClickSpotlight.blurPoints * min(max(state.blur, 0), 1) * a
        if blurPoints * Double(px) > 0.4 {
            quiet = softened(screen, sigma: blurPoints * Double(px))
            blend = smoothstep(blurPoints / 2.5)
        }
        // Core Image works in linear light, where halving looks like barely a quarter darker; this makes the slider's
        // dim what the eye sees.
        let shade = 1 - pow(1 - darkness, 2.2)
        let args: [Any] = [screen, quiet, CIVector(x: center.x, y: center.y), Float(radius * ClickSpotlight.core),
                           Float(radius), Float(blend), Float(shade)]
        return kernel.apply(extent: e, roiCallback: { _, r in r }, arguments: args) ?? screen
    }

    /// A wide, soft blur doesn't need every pixel: it's done on a copy scaled down until the blur is a few pixels
    /// across, then scaled back, so a blur over a 5K screen costs about what one over a thumbnail does.
    private func softened(_ image: CIImage, sigma: Double) -> CIImage {
        let e = image.extent
        let q = CGFloat(min(1, max(0.08, 3 / sigma)))
        let small = q < 1 ? image.transformed(by: CGAffineTransform(scaleX: q, y: q), highQualityDownsample: true) : image
        let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: sigma * Double(q)).cropped(to: small.extent)
        return blurred.transformed(by: CGAffineTransform(scaleX: 1 / q, y: 1 / q)).clampedToExtent().cropped(to: e)
    }
}
