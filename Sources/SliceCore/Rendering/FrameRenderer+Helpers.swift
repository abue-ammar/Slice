//
//  FrameRenderer+Helpers.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/13/26.
//

import CoreImage
import CoreImage.CIFilterBuiltins

extension FrameRenderer {
    static func kernels(in resource: String, label: String) -> [CIKernel]? {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "metal.txt"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        do {
            return try CIKernel.kernels(withMetalString: source)
        } catch {
            NSLog("\(label) kernel failed to compile: \(error)")
            return nil
        }
    }

    static func kernel(_ name: String, in resource: String, label: String) -> CIKernel? {
        kernels(in: resource, label: label)?.first { $0.name == name }
    }

    func place(_ image: CIImage, sourceSize: CGSize, into rect: CGRect, sharp: Bool) -> CIImage {
        let sx = rect.width / sourceSize.width, sy = rect.height / sourceSize.height
        var scaled: CIImage
        if abs(rect.width - sourceSize.width) < 0.5 && abs(rect.height - sourceSize.height) < 0.5 {
            // Already the size (to within half a pixel). A looser test snapped near-1× zooms by up to 0.5%: tens of
            // pixels across a 4K screen, a visible jump as a zoom passed through 1:1.
            scaled = image
        } else if sharp || sx < 0.7 {
            let f = CIFilter.lanczosScaleTransform()
            f.inputImage = image.clampedToExtent().cropped(to: CGRect(origin: .zero, size: sourceSize))
            f.scale = Float(sy)
            f.aspectRatio = Float(sx / sy)
            scaled = f.outputImage!
            if sharp && sx > 1.3 {
                let f = CIFilter.sharpenLuminance()
                f.inputImage = scaled
                f.sharpness = Float(min(0.25 * (sx - 1), 0.6))
                f.radius = Float(min(0.8 * sx, 4))
                scaled = f.outputImage!.cropped(to: scaled.extent)
            }
        } else {
            scaled = image.transformed(by: CGAffineTransform(scaleX: sx, y: sy), highQualityDownsample: true)
        }
        return scaled.transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }

    func roundedRect(_ rect: CGRect, radius: CGFloat) -> CIImage {
        let f = CIFilter.roundedRectangleGenerator()
        f.extent = rect
        f.radius = Float(max(0, min(radius, min(rect.width, rect.height) / 2)))
        f.color = .white
        return f.outputImage!
    }

    func shadow(for mask: CIImage, strength: Double, blur: CGFloat, offset: CGFloat) -> CIImage {
        let dark = mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(strength)),
        ])
        return dark.applyingGaussianBlur(sigma: Double(blur))
            .cropped(to: mask.extent.insetBy(dx: -blur * 3, dy: -blur * 3))
            .transformed(by: CGAffineTransform(translationX: 0, y: -offset))
    }

    func scaleAlpha(_ image: CIImage, by a: Double) -> CIImage {
        // CIColorMatrix works on unpremultiplied colour, so only alpha is scaled.
        image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(a))])
    }

    func average(_ layers: [CIImage]) -> CIImage {
        guard layers.count > 1 else { return layers.first ?? .empty() }
        let w = 1.0 / Double(layers.count)
        return layers.map { scaleAlpha($0, by: w) }.dropFirst().reduce(scaleAlpha(layers[0], by: w)) { acc, next in
            next.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: acc])
        }
    }

    func viewed(_ r: CGRect, view: CGRect, output: CGSize) -> CGRect {
        let k = output.width / view.width
        return CGRect(x: (r.minX - view.minX) * k, y: (r.minY - view.minY) * k, width: r.width * k, height: r.height * k)
    }

    func flip(_ r: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: height - r.maxY, width: r.width, height: r.height)
    }

    func ciColor(_ c: RGBA) -> CIColor {
        CIColor(red: c.r, green: c.g, blue: c.b, alpha: c.a, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
    }
}
