//
//  Clip+DeviceDisplay.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/15/26.
//

import CoreGraphics
import Foundation

extension Clip {
    /// The device's display in this take's picture, in pixels with Core Image's bottom-left origin. A framed
    /// recording has the frame drawn around it (and its Dynamic Island over it); a frameless one is all display.
    public var deviceDisplayRect: CGRect? {
        guard let device else { return nil }
        let size = screenPixelSize
        guard size.width > 0, size.height > 0 else { return nil }
        let r: CGRect
        if let screen = device.screen, screen.width > 0, screen.height > 0 {
            r = screen
        } else if device.frame != nil {
            // Recorded before the opening was saved, and not matched to a frame since: a typical Pro frame's.
            let typical = CGRect(x: 100.0 / 1520, y: 100.0 / 3068, width: 1320.0 / 1520, height: 2868.0 / 3068)
            r = size.width > size.height
                ? CGRect(x: typical.minY, y: 1 - typical.maxX, width: typical.height, height: typical.width) : typical
        } else {
            r = CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return pixels(r)
    }

    /// The frame's island or notch over the display, in the same pixels as `deviceDisplayRect`.
    public var deviceCutoutRect: CGRect? {
        guard let cutout = device?.cutout, cutout.width > 0, cutout.height > 0, screenPixelSize.width > 0 else { return nil }
        return pixels(cutout)
    }

    private func pixels(_ r: CGRect) -> CGRect {
        let size = screenPixelSize
        let x0 = (r.minX * size.width).rounded(), x1 = (r.maxX * size.width).rounded()
        let y0 = ((1 - r.maxY) * size.height).rounded(), y1 = ((1 - r.minY) * size.height).rounded()
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).intersection(CGRect(origin: .zero, size: size))
    }

    /// A take recorded with the phone on its side: its picture is the portrait screen turned a quarter counter-clockwise.
    public var isLandscapeDevice: Bool { device != nil && screenPixelSize.width > screenPixelSize.height }
}
