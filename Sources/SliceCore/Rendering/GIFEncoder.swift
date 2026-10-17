//
//  GIFEncoder.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/17/26.
//

import Foundation

/// Writes an animated GIF to disk a frame at a time. ImageIO holds every frame until it finalises, which runs to
/// gigabytes for a minute-long recording. Each frame here carries only the pixels that changed, on its own palette.
public final class GIFEncoder {
    public let width: Int
    public let height: Int

    private let file: FileHandle
    private let palette = GIFPalette()
    private let lzw = GIFLZW()
    private let reference: UnsafeMutablePointer<UInt8>
    private let changed: UnsafeMutablePointer<Bool>
    private var indices: [UInt8] = []
    private var started = false
    private var pending: (bytes: Data, centiseconds: Int)?

    static let tolerance = 3
    static let transparent: UInt8 = 255
    static let ditherStrength = 10
    private static let bayer: [Int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

    public init(url: URL, width: Int, height: Int) throws {
        precondition(width > 0 && height > 0 && width <= 0xFFFF && height <= 0xFFFF)
        self.width = width
        self.height = height
        try? FileManager.default.removeItem(at: url)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        file = try FileHandle(forWritingTo: url)
        reference = .allocate(capacity: width * height * 3)
        reference.initialize(repeating: 0, count: width * height * 3)
        changed = .allocate(capacity: width * height)
        changed.initialize(repeating: false, count: width * height)

        var header = Data("GIF89a".utf8)
        header.appendLE16(width)
        header.appendLE16(height)
        header += [0x00, 0x00, 0x00]
        header += [0x21, 0xFF, 0x0B] + Array("NETSCAPE2.0".utf8) + [0x03, 0x01, 0x00, 0x00, 0x00]
        try file.write(contentsOf: header)
    }

    deinit {
        reference.deallocate()
        changed.deallocate()
        try? file.close()
    }

    /// Adds an opaque 32-bit BGRA frame shown from `time` (seconds) until the next frame that differs.
    public func add(bgra base: UnsafeRawPointer, bytesPerRow: Int, time: Double) throws {
        let w = width, h = height, tolerance = Self.tolerance
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0 ..< h {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0 ..< w {
                let p = row + x * 4, i = y * w + x, ref = reference + i * 3
                let differs = !started
                    || abs(Int(p[2]) - Int(ref[0])) > tolerance
                    || abs(Int(p[1]) - Int(ref[1])) > tolerance
                    || abs(Int(p[0]) - Int(ref[2])) > tolerance
                changed[i] = differs
                if differs {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return }
        started = true

        palette.reset()
        for y in minY ... maxY {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in minX ... maxX where changed[y * w + x] {
                let p = row + x * 4
                palette.add(Int(p[2]), Int(p[1]), Int(p[0]))
            }
        }
        palette.build()

        let bw = maxX - minX + 1, bh = maxY - minY + 1
        indices.removeAll(keepingCapacity: true)
        indices.reserveCapacity(bw * bh)
        let strength = Self.ditherStrength
        for y in minY ... maxY {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in minX ... maxX {
                let i = y * w + x
                guard changed[i] else { indices.append(Self.transparent); continue }
                let p = row + x * 4, ref = reference + i * 3
                let r = Int(p[2]), g = Int(p[1]), b = Int(p[0])
                ref[0] = UInt8(r); ref[1] = UInt8(g); ref[2] = UInt8(b)
                let exact = palette.index(r, g, b)
                if palette.isClose(exact, r, g, b) {
                    indices.append(exact)
                } else {
                    let d = (Self.bayer[(y & 3) << 2 | (x & 3)] * 2 - 15) * strength / 32
                    indices.append(palette.index(clamp(r + d), clamp(g + d), clamp(b + d)))
                }
            }
        }

        var frame = Data([0x2C])
        frame.appendLE16(minX)
        frame.appendLE16(minY)
        frame.appendLE16(bw)
        frame.appendLE16(bh)
        frame.append(0x87)
        var table = palette.colors
        table += [UInt8](repeating: 0, count: 768 - table.count)
        frame += table
        indices.withUnsafeBufferPointer { lzw.encode($0, into: &frame) }

        let centiseconds = Int((time * 100).rounded())
        try flush(until: centiseconds)
        pending = (frame, centiseconds)
    }

    /// Writes the last frame, held until `duration`, and closes the file.
    public func finish(duration: Double) throws {
        try flush(until: Int((duration * 100).rounded()))
        try file.write(contentsOf: Data([0x3B]))
        try file.close()
    }

    private func flush(until centiseconds: Int) throws {
        guard let pending else { return }
        let delay = min(max(centiseconds - pending.centiseconds, 2), 0xFFFF)
        var control = Data([0x21, 0xF9, 0x04, 0x05])
        control.appendLE16(delay)
        control += [Self.transparent, 0x00]
        try file.write(contentsOf: control + pending.bytes)
        self.pending = nil
    }

    @inline(__always) private func clamp(_ v: Int) -> Int { min(max(v, 0), 255) }
}

private extension Data {
    mutating func appendLE16(_ v: Int) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
    }
}
