//
//  PreviewPacking.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/8/26.
//

import AVFoundation
import CoreImage

public struct PreviewPacking: Equatable, @unchecked Sendable {
    public let screens: [CGSize]
    public let cameras: [CGRect?]
    public let canvas: CGSize

    static let cameraBox = CGSize(width: 1280, height: 960)

    public init(screens: [CGSize], cameras: [CGSize?]) {
        self.screens = screens
        let width = max(screens.map(\.width).max() ?? 16, 16)
        let height = max(screens.map(\.height).max() ?? 16, 16)
        let hasCamera = cameras.contains { $0 != nil }
        let box = CGRect(x: width, y: 0, width: hasCamera ? Self.cameraBox.width : 0, height: Self.cameraBox.height)
        self.cameras = cameras.map { size in
            guard let size, size.width > 0, size.height > 0 else { return nil }
            let s = min(box.width / size.width, box.height / size.height, 1)
            return CGRect(x: box.minX, y: 0, width: (size.width * s).rounded(), height: (size.height * s).rounded())
        }
        canvas = CGSize(width: (Int(width + box.width + 1) / 2) * 2,
                        height: (Int(max(height, hasCamera ? box.height : 0) + 1) / 2) * 2 + (hasCamera ? 2 : 0))
        marker = hasCamera ? CGPoint(x: width, y: canvas.height - 1) : nil
    }

    /// A pixel in the top row, above everything else, lit when the frame carries a camera picture. The player has no
    /// camera frame at some moments (past the end of a shorter camera file, or before one decodes), and an empty slot
    /// would otherwise unpack as a transparent camera: its shadow with nothing in it.
    let marker: CGPoint?

    func pack(screen: CIImage?, camera: CIImage?, clip: Int) -> CIImage {
        var image = CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: canvas))
        if let screen {
            image = screen.transformed(by: CGAffineTransform(translationX: -screen.extent.minX, y: -screen.extent.minY))
                .composited(over: image)
        }
        if let camera, clip < cameras.count, let rect = cameras[clip] {
            let e = camera.extent
            image = camera.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY)
                .concatenating(CGAffineTransform(scaleX: rect.width / e.width, y: rect.height / e.height))
                .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
                .composited(over: image)
            if let marker {
                image = CIImage(color: .white).cropped(to: CGRect(origin: marker, size: CGSize(width: 1, height: 1)))
                    .composited(over: image)
            }
        }
        return image
    }

    public func hasCamera(in buffer: CVPixelBuffer) -> Bool {
        guard let marker, CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              CVPixelBufferGetHeight(buffer) == Int(canvas.height), CVPixelBufferGetWidth(buffer) > Int(marker.x)
        else { return true }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return true }
        let pixel = base.assumingMemoryBound(to: UInt8.self) + Int(marker.x) * 4
        return pixel[3] > 127
    }

    public func unpack(_ packed: CIImage, clip: Int, hasCamera: Bool) -> (screen: CIImage?, camera: CIImage?) {
        guard clip < screens.count else { return (nil, nil) }
        let screen = packed.cropped(to: CGRect(origin: .zero, size: screens[clip]))
        var camera: CIImage?
        if hasCamera, clip < cameras.count, let rect = cameras[clip] {
            camera = packed.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        }
        return (screen, camera)
    }
}
