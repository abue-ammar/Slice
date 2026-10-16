//
//  SystemCursorClassifier.swift
//  Slice
//
//  Created by rit3zh CX on 10/12/26.
//

import AppKit
import SliceCore
import VideoToolbox

final class SystemCursorClassifier {
    private struct Known {
        var type: CursorType
        var size: CGSize
        var hotSpot: CGPoint
        var pixels: [UInt8]
    }

    private let known: [Known]
    private var last: (pixels: [UInt8], type: CursorType)?

    init() {
        var cursors: [(CursorType, NSCursor)] = [
            (.arrow, .arrow), (.pointingHand, .pointingHand), (.iBeam, .iBeam),
            (.iBeamVertical, .iBeamCursorForVerticalLayout), (.crosshair, .crosshair),
            (.openHand, .openHand), (.closedHand, .closedHand), (.contextualMenu, .contextualMenu),
            (.dragCopy, .dragCopy), (.operationNotAllowed, .operationNotAllowed),
            (.zoomIn, .zoomIn), (.zoomOut, .zoomOut),
            (.resizeLeftRight, .columnResize), (.resizeLeft, .columnResize(directions: .left)),
            (.resizeRight, .columnResize(directions: .right)),
            (.resizeUpDown, .rowResize), (.resizeUp, .rowResize(directions: .up)), (.resizeDown, .rowResize(directions: .down)),
        ]
        let frames: [(NSCursor.FrameResizePosition, CursorType, CursorType, CursorType)] = [
            (.top, .resizeNorthSouth, .resizeNorth, .resizeSouth),
            (.bottom, .resizeNorthSouth, .resizeSouth, .resizeNorth),
            (.left, .resizeEastWest, .resizeWest, .resizeEast),
            (.right, .resizeEastWest, .resizeEast, .resizeWest),
            (.topLeft, .resizeNorthWestSouthEast, .resizeNorthWest, .resizeSouthEast),
            (.bottomRight, .resizeNorthWestSouthEast, .resizeSouthEast, .resizeNorthWest),
            (.topRight, .resizeNorthEastSouthWest, .resizeNorthEast, .resizeSouthWest),
            (.bottomLeft, .resizeNorthEastSouthWest, .resizeSouthWest, .resizeNorthEast),
        ]
        for (position, both, outward, inward) in frames {
            cursors.append((both, .frameResize(position: position, directions: .all)))
            cursors.append((outward, .frameResize(position: position, directions: .outward)))
            cursors.append((inward, .frameResize(position: position, directions: .inward)))
        }
        known = cursors.map { type, cursor in
            Known(type: type, size: cursor.image.size, hotSpot: cursor.hotSpot, pixels: Self.pixels(of: cursor.image))
        }
    }

    func type(of cursor: NSCursor) -> CursorType {
        let candidates = known.filter { $0.size == cursor.image.size && $0.hotSpot == cursor.hotSpot }
        guard candidates.count > 1 else { return candidates.first?.type ?? .arrow }
        let pixels = Self.pixels(of: cursor.image)
        if let last, last.pixels == pixels { return last.type }
        let best = candidates.min { Self.distance($0.pixels, pixels) < Self.distance($1.pixels, pixels) }!.type
        last = (pixels, best)
        return best
    }

    private static func pixels(of image: NSImage) -> [UInt8] {
        let w = max(Int(image.size.width.rounded()), 1), h = max(Int(image.size.height.rounded()), 1)
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
            NSGraphicsContext.restoreGraphicsState()
        }
        return data
    }

    private static func distance(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return .max }
        return zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
    }
}
