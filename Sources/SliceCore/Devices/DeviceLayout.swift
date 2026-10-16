//
//  DeviceLayout.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/1/26.
//

import CoreGraphics
import Foundation

public struct DeviceLayout: Equatable, Sendable {
    public let canvas: CGSize
    public let landscape: Bool
    public let screenRect: CGRect
    /// The frame's island or notch over the display, as fractions of the canvas.
    public let cutoutRect: CGRect?
    public let streamCrop: CGRect
    public let streamSize: CGSize?

    public init(frame: DeviceFrameDefinition, streamSize: CGSize?) {
        let landscape = streamSize.map { $0.width > $0.height } ?? false
        self.landscape = landscape
        self.streamSize = streamSize
        let c = frame.canvasSize
        canvas = landscape ? CGSize(width: c.height, height: c.width) : c
        let s = frame.screen.rect
        screenRect = landscape ? CGRect(x: s.minY, y: 1 - s.maxX, width: s.height, height: s.width) : s
        cutoutRect = frame.screen.cutout.map { c in
            landscape ? CGRect(x: c.minY, y: 1 - c.maxX, width: c.height, height: c.width) : c
        }

        guard let stream = streamSize, stream.width > 0, stream.height > 0 else {
            streamCrop = CGRect(x: 0, y: 0, width: 1, height: 1)
            return
        }
        let opening = screenRect.width * canvas.width / (screenRect.height * canvas.height)
        let source = stream.width / stream.height
        if source > opening {
            let w = opening / source
            streamCrop = CGRect(x: (1 - w) / 2, y: 0, width: w, height: 1)
        } else {
            let h = source / opening
            streamCrop = CGRect(x: 0, y: (1 - h) / 2, width: 1, height: h)
        }
    }

    public func frameImagePoint(canvas p: CGPoint) -> CGPoint {
        landscape ? CGPoint(x: 1 - p.y, y: p.x) : p
    }

    public func fitted(in size: CGSize) -> CGRect {
        guard canvas.width > 0, canvas.height > 0, size.width > 0, size.height > 0 else { return .zero }
        let s = min(size.width / canvas.width, size.height / canvas.height)
        let w = canvas.width * s, h = canvas.height * s
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    public func streamPixel(canvas p: CGPoint) -> CGPoint? {
        guard let stream = streamSize else { return nil }
        let u = (p.x - screenRect.minX) / screenRect.width
        let v = (p.y - screenRect.minY) / screenRect.height
        guard (0 ... 1).contains(u), (0 ... 1).contains(v) else { return nil }
        return CGPoint(x: (streamCrop.minX + u * streamCrop.width) * stream.width,
                       y: (streamCrop.minY + v * streamCrop.height) * stream.height)
    }
}
