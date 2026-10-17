//
//  GIFPalette.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/17/26.
//

/// A frame's colours cut down to 255 by median cut over a 6-bit-per-channel histogram.
final class GIFPalette {
    static let maxColors = 255
    private static let bins = 1 << 18

    private let count = UnsafeMutablePointer<Int32>.allocate(capacity: bins)
    private let sums = UnsafeMutablePointer<Int>.allocate(capacity: bins * 3)
    private let lookup = UnsafeMutablePointer<UInt16>.allocate(capacity: bins)
    private var used: [Int32] = []
    private var looked: [Int32] = []
    private(set) var colors: [UInt8] = []

    init() {
        count.initialize(repeating: 0, count: Self.bins)
        sums.initialize(repeating: 0, count: Self.bins * 3)
        lookup.initialize(repeating: 0, count: Self.bins)
    }

    deinit {
        count.deallocate()
        sums.deallocate()
        lookup.deallocate()
    }

    var colorCount: Int { colors.count / 3 }

    @inline(__always) private static func key(_ r: Int, _ g: Int, _ b: Int) -> Int { (r >> 2) << 12 | (g >> 2) << 6 | b >> 2 }

    func reset() {
        for k in used {
            count[Int(k)] = 0
            sums[Int(k) * 3] = 0; sums[Int(k) * 3 + 1] = 0; sums[Int(k) * 3 + 2] = 0
        }
        for k in looked { lookup[Int(k)] = 0 }
        used.removeAll(keepingCapacity: true)
        looked.removeAll(keepingCapacity: true)
        colors.removeAll(keepingCapacity: true)
    }

    @inline(__always) func add(_ r: Int, _ g: Int, _ b: Int) {
        let k = Self.key(r, g, b)
        if count[k] == 0 { used.append(Int32(k)) }
        count[k] += 1
        sums[k * 3] += r; sums[k * 3 + 1] += g; sums[k * 3 + 2] += b
    }

    private struct Box {
        var lo: Int, hi: Int, population: Int, axis: Int, extent: Int
    }

    @inline(__always) private static func component(_ key: Int32, _ axis: Int) -> Int32 {
        switch axis {
        case 0: key >> 12
        case 1: (key >> 6) & 63
        default: key & 63
        }
    }

    private func measure(_ keys: [Int32], _ lo: Int, _ hi: Int) -> Box {
        var mins: [Int32] = [63, 63, 63], maxs: [Int32] = [0, 0, 0], population = 0
        for i in lo ..< hi {
            let k = keys[i]
            population += Int(count[Int(k)])
            for a in 0 ..< 3 {
                let c = Self.component(k, a)
                mins[a] = min(mins[a], c); maxs[a] = max(maxs[a], c)
            }
        }
        let extents = (0 ..< 3).map { Int(maxs[$0] - mins[$0]) }
        let axis = extents.indices.max { extents[$0] < extents[$1] } ?? 0
        return Box(lo: lo, hi: hi, population: population, axis: axis, extent: extents[axis])
    }

    /// Splits the busiest boxes first so large areas stay smooth, then the widest so small, distinct colours
    /// (a pointer, a button) keep their own entry.
    func build() {
        var keys = used
        guard !keys.isEmpty else { return }
        var boxes = [measure(keys, 0, keys.count)]
        while boxes.count < Self.maxColors {
            let byPopulation = boxes.count < Self.maxColors / 2
            var best = -1, bestScore = 0
            for (i, box) in boxes.enumerated() where box.extent > 0 {
                let score = byPopulation ? box.population * box.extent : box.extent << 32 | min(box.population, Int(Int32.max))
                if score > bestScore { best = i; bestScore = score }
            }
            guard best >= 0 else { break }
            let box = boxes[best]
            keys[box.lo ..< box.hi].sort { Self.component($0, box.axis) < Self.component($1, box.axis) }
            var half = 0, cut = box.lo + 1
            for i in box.lo ..< box.hi - 1 {
                half += Int(count[Int(keys[i])])
                cut = i + 1
                if half * 2 >= box.population { break }
            }
            boxes[best] = measure(keys, box.lo, cut)
            boxes.append(measure(keys, cut, box.hi))
        }
        for box in boxes {
            var r = 0, g = 0, b = 0
            for i in box.lo ..< box.hi {
                let k = Int(keys[i]) * 3
                r += sums[k]; g += sums[k + 1]; b += sums[k + 2]
            }
            let n = max(box.population, 1)
            colors += [UInt8((r + n / 2) / n), UInt8((g + n / 2) / n), UInt8((b + n / 2) / n)]
        }
    }

    /// Flat areas (window fills, text on white) that the palette already holds aren't dithered, so they stay clean.
    @inline(__always) func isClose(_ index: UInt8, _ r: Int, _ g: Int, _ b: Int) -> Bool {
        let i = Int(index) * 3
        return abs(Int(colors[i]) - r) <= 3 && abs(Int(colors[i + 1]) - g) <= 3 && abs(Int(colors[i + 2]) - b) <= 3
    }

    @inline(__always) func index(_ r: Int, _ g: Int, _ b: Int) -> UInt8 {
        let k = Self.key(r, g, b)
        let cached = lookup[k]
        if cached != 0 { return UInt8(cached - 1) }
        let cr = (r & ~3) | 2, cg = (g & ~3) | 2, cb = (b & ~3) | 2
        var best = 0, bestDistance = Int.max
        colors.withUnsafeBufferPointer { c in
            for i in 0 ..< c.count / 3 {
                let dr = Int(c[i * 3]) - cr, dg = Int(c[i * 3 + 1]) - cg, db = Int(c[i * 3 + 2]) - cb
                let d = 3 * dr * dr + 4 * dg * dg + 2 * db * db
                if d < bestDistance { best = i; bestDistance = d }
            }
        }
        lookup[k] = UInt16(best + 1)
        looked.append(Int32(k))
        return UInt8(best)
    }
}
