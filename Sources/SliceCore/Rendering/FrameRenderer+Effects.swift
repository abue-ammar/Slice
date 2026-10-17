//
//  FrameRenderer+Effects.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/13/26.
//

import CoreImage

extension FrameRenderer {
    func clickEffects(on image: CIImage, scene: RenderScene, time t: Double, geometry g: ScreenGeometry, view: CGRect,
                      output: CGSize, canvas: CGRect) -> CIImage {
        let settings = scene.project.cursor
        let effect = settings.clickEffect
        let clicks = scene.clicks(at: t, lasting: effect.duration)
        guard !clicks.isEmpty else { return image }
        let content = viewed(g.contentRect, view: view, output: output)
        let clips = scene.project.clips
        let i = scene.clipIndex(at: t)
        let screenWidth = clips.indices.contains(i) && clips[i].captureRect.width > 0 ? clips[i].captureRect.width : 1440
        let unit = content.width / screenWidth * settings.clickEffectSize
        guard unit.isFinite, unit > 0.01 else { return image }
        let visible = flip(content, height: output.height).intersection(canvas)

        var result = image
        for click in clicks {
            let origin = CGPoint(x: content.minX + click.point.x * content.width,
                                 y: output.height - (content.minY + click.point.y * content.height))
            switch effect {
            case .none:
                break
            case .ripple:
                if let ring = rippleRing(at: origin, progress: click.age / effect.duration, radius: 40 * unit) {
                    result = ring.cropped(to: visible).composited(over: result)
                }
            case .liquid:
                result = liquidRipple(result, at: origin, progress: click.age / effect.duration, unit: unit)
            }
        }
        return result
    }

    static let ringSpriteRadius: CGFloat = 120

    static func makeRingSprite() -> CIImage? {
        let r = ringSpriteRadius, margin: CGFloat = 24
        let side = Int((r + margin) * 2)
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let c = CGFloat(side) / 2
        let line = r * 0.09
        let circle = CGRect(x: c - r + line / 2, y: c - r + line / 2, width: 2 * r - line, height: 2 * r - line)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.22))
        ctx.fillEllipse(in: circle)
        ctx.setShadow(offset: .zero, blur: line * 1.6, color: CGColor(gray: 0, alpha: 0.35))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
        ctx.setLineWidth(line)
        ctx.strokeEllipse(in: circle)
        return ctx.makeImage().map { CIImage(cgImage: $0).transformed(by: CGAffineTransform(translationX: -c, y: -c)) }
    }

    func rippleRing(at origin: CGPoint, progress p: Double, radius: CGFloat) -> CIImage? {
        guard let sprite = ringSprite, p >= 0, p < 1 else { return nil }
        let grow = 1 - pow(1 - p, 3)
        let scale = radius * (0.35 + 0.65 * grow) / Self.ringSpriteRadius
        let placed = sprite.transformed(by: CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: origin.x, y: origin.y)))
        return scaleAlpha(placed, by: pow(1 - p, 1.6))
    }

    static let liquidKernel = kernel("clickPress", in: "ClickRipple", label: "Click ripple")

    static var hasLiquidKernel: Bool { liquidKernel != nil }

    func liquidRipple(_ image: CIImage, at origin: CGPoint, progress: Double, unit: CGFloat) -> CIImage {
        guard let kernel = Self.liquidKernel else { return image }
        let radius = 46 * unit
        let extent = image.extent
        let args: [Any] = [image, CIVector(x: origin.x, y: origin.y), Float(progress), Float(radius), Float(0.35)]
        return kernel.apply(extent: extent, roiCallback: { _, r in r.insetBy(dx: -radius, dy: -radius) }, arguments: args) ?? image
    }

    // MARK: - Liquid glass lens

    static let glassKernels: (lens: CIKernel, mask: CIKernel)? = {
        guard let kernels = FrameRenderer.kernels(in: "LiquidGlass", label: "Liquid glass"),
              let lens = kernels.first(where: { $0.name == "liquidGlass" }),
              let mask = kernels.first(where: { $0.name == "liquidGlassMask" }) else { return nil }
        return (lens, mask)
    }()

    static var hasGlassKernel: Bool { glassKernels != nil }

    public static func warmUp() {
        _ = glassKernels
        _ = zoomBlurKernel
        _ = cameraBlurKernel
        _ = liquidKernel
        _ = spotlightKernel
        _ = tiltKernel
        _ = cursorTrailKernel
    }

    func lensLayer(_ lens: LensState, on image: CIImage, magnified: CIImage, at focus: CGPoint,
                   from screen: (rect: CGRect, radius: CGFloat), output: CGSize) -> CIImage {
        guard let kernels = Self.glassKernels, !screen.rect.isEmpty else { return image }
        let settings = lens.settings
        let e = CGFloat(min(max(lens.appear, 0), 1))
        let ry = min(output.width, output.height) * CGFloat(min(max(settings.size, 0.05), 1)) / 2
        let shapes = lens.shapes.isEmpty ? [settings.shape: 1] : lens.shapes
        func blended(_ value: (LensShape) -> CGFloat) -> CGFloat {
            shapes.reduce(0) { $0 + value($1.key) * CGFloat($1.value) }
        }
        let rx = ry * blended(Self.lensAspect)
        let cornerRatio = blended(Self.lensCornerRatio)
        let squircle = blended { $0 == .squircle ? 1 : 0 }
        let exponent: Float = 4.5
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * e }
        let center = CGPoint(x: mix(screen.rect.midX, focus.x), y: mix(screen.rect.midY, focus.y))
        let radii = CGSize(width: mix(screen.rect.width / 2, rx), height: mix(screen.rect.height / 2, ry))
        let corner = min(mix(screen.radius, ry * cornerRatio), radii.width, radii.height)
        let weight = Float(squircle * e)
        let strength = smoothstep(Double(e) / 0.45)
        let extent = CGRect(origin: .zero, size: output)
        let clean = magnified.cropped(to: extent).clampedToExtent()

        var under = image
        if settings.shadow > 0.001 {
            let shadows = shapes.compactMap { shape, share -> CIImage? in
                let sx = ry * Self.lensAspect(shape)
                guard let shadow = lensShadow(rx: sx, ry: ry, cornerRatio: Self.lensCornerRatio(shape),
                                              squircle: shape == .squircle, exponent: exponent, kernel: kernels.mask)
                else { return nil }
                let placed = shadow.transformed(by: CGAffineTransform(scaleX: radii.width / sx, y: radii.height / ry)
                    .concatenating(CGAffineTransform(translationX: center.x, y: center.y - radii.height * 0.08)))
                return shapes.count == 1 ? placed : scaleAlpha(placed, by: share)
            }
            if let first = shadows.first {
                let shadow = shadows.dropFirst().reduce(first) {
                    $1.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: $0])
                }
                under = scaleAlpha(shadow, by: min(settings.shadow, 1) * 0.6 * strength).composited(over: image)
            }
        }
        let frosted = settings.blur > 0.01
            ? clean.applyingGaussianBlur(sigma: settings.blur * 0.05 * Double(ry)).cropped(to: extent).clampedToExtent() : clean
        let args: [Any] = [under, clean, frosted, CIVector(x: center.x, y: center.y),
                           CIVector(x: radii.width, y: radii.height), Float(corner), weight, exponent, Float(min(rx, ry)),
                           Float(strength), Float(settings.refraction), Float(settings.thickness), Float(settings.blur),
                           Float(settings.rim), Float(settings.dispersion), Float(min(max(settings.opacity, 0), 1))]
        return kernels.lens.apply(extent: image.extent, roiCallback: { i, r in i == 0 ? r : extent }, arguments: args) ?? image
    }

    static func lensAspect(_ shape: LensShape) -> CGFloat { shape == .pill ? 1.8 : 1 }
    static func lensCornerRatio(_ shape: LensShape) -> CGFloat { shape == .squircle ? 0.6 : 1 }

    func lensShadow(rx: CGFloat, ry: CGFloat, cornerRatio: CGFloat, squircle: Bool, exponent: Float,
                    kernel: CIKernel) -> CIImage? {
        let reference: CGFloat = 256
        let scale = ry / reference
        let qy = reference, qx = (rx / scale / 2).rounded() * 2
        let key = "\(qx)|\(cornerRatio)|\(squircle)" as NSString
        if let cached = lensShadows.object(forKey: key) {
            return cached.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let local = CGRect(x: -qx, y: -qy, width: 2 * qx, height: 2 * qy)
        let blur = Double(qy) * 0.14
        let bounds = local.insetBy(dx: -CGFloat(blur) * 3, dy: -CGFloat(blur) * 3).integral
        let args: [Any] = [CIVector(x: 0, y: 0), CIVector(x: qx, y: qy), Float(qy * cornerRatio),
                           Float(squircle ? 1 : 0), exponent]
        guard let mask = kernel.apply(extent: local.insetBy(dx: -2, dy: -2), roiCallback: { _, r in r }, arguments: args),
              let cg = context.createCGImage(mask.applyingGaussianBlur(sigma: blur).cropped(to: bounds), from: bounds)
        else { return nil }
        let sprite = CIImage(cgImage: cg).transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
        lensShadows.setObject(sprite, forKey: key)
        return sprite.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}
