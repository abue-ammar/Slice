//
//  Device3DTemplate+Geometry.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/15/26.
//

import AppKit
import SceneKit
import simd

extension Device3DTemplate {
    /// A mesh's vertices in `space`, when they're plain floats.
    static func points(of node: SCNNode, in space: SCNNode) -> [SIMD3<Float>]? {
        guard let source = node.geometry?.sources(for: .vertex).first, source.usesFloatComponents, source.bytesPerComponent == 4,
              source.componentsPerVector >= 3 else { return nil }
        let m = node.simdConvertTransform(matrix_identity_float4x4, to: space)
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(source.vectorCount)
        source.data.withUnsafeBytes { raw in
            for i in 0 ..< source.vectorCount {
                let o = source.dataOffset + i * source.dataStride
                guard o + 12 <= raw.count else { break }
                let p = m * SIMD4(raw.loadUnaligned(fromByteOffset: o, as: Float.self), raw.loadUnaligned(fromByteOffset: o + 4, as: Float.self),
                                  raw.loadUnaligned(fromByteOffset: o + 8, as: Float.self), 1)
                out.append(SIMD3(p.x, p.y, p.z))
            }
        }
        return out
    }

    /// The meshes' extent in `space`, from their vertices (their boxes where those can't be read).
    static func bounds(of nodes: [SCNNode], in space: SCNNode) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for node in nodes {
            if let points = points(of: node, in: space), !points.isEmpty {
                for p in points {
                    lo = simd_min(lo, p)
                    hi = simd_max(hi, p)
                }
            } else {
                let b = box([node], in: space)
                lo = simd_min(lo, b.min)
                hi = simd_max(hi, b.max)
            }
        }
        return (lo, hi)
    }

    /// Which way a rectangle of points runs lengthwise, within the plane of `a` and `b`: the long side of the
    /// smallest rectangle around them. (The spread of the points alone tilts when they bunch at rounded corners.)
    static func longSide(of points: [SIMD3<Float>], across a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        let flat = points.map { SIMD2<Float>(simd_dot($0, a), simd_dot($0, b)) }
        var best = (area: Float.greatestFiniteMagnitude, direction: a)
        for step in 0 ..< 360 {
            let angle = Float(step) * .pi / 360
            let u = SIMD2(cos(angle), sin(angle)), v = SIMD2(-sin(angle), cos(angle))
            var lu = Float.greatestFiniteMagnitude, hu = -lu, lv = lu, hv = -lu
            for p in flat {
                let x = simd_dot(p, u), y = simd_dot(p, v)
                lu = min(lu, x); hu = max(hu, x); lv = min(lv, y); hv = max(hv, y)
            }
            let area = (hu - lu) * (hv - lv)
            if area < best.area {
                let long = hu - lu >= hv - lv ? u : v
                best = (area, simd_normalize(a * long.x + b * long.y))
            }
        }
        return best.direction
    }

    /// The directions points spread along, widest first (the eigenvectors of their covariance, by Jacobi rotations).
    static func principalAxes(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        let n = Double(points.count)
        let mean = points.reduce(SIMD3<Double>.zero) { $0 + SIMD3<Double>($1) } / n
        var a = [[Double]](repeating: [0, 0, 0], count: 3)
        for p in points {
            let d = SIMD3<Double>(p) - mean
            for i in 0 ..< 3 { for j in 0 ..< 3 { a[i][j] += d[i] * d[j] / n } }
        }
        var v: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        for _ in 0 ..< 32 {
            var p = 0, q = 1
            for (i, j) in [(0, 2), (1, 2)] where abs(a[i][j]) > abs(a[p][q]) { p = i; q = j }
            guard abs(a[p][q]) > 1e-12 else { break }
            let theta = (a[q][q] - a[p][p]) / (2 * a[p][q])
            let t = (theta >= 0 ? 1 : -1) / (abs(theta) + (theta * theta + 1).squareRoot())
            let c = 1 / (t * t + 1).squareRoot(), s = t * c
            for k in 0 ..< 3 {
                let akp = a[k][p], akq = a[k][q]
                a[k][p] = c * akp - s * akq
                a[k][q] = s * akp + c * akq
            }
            for k in 0 ..< 3 {
                let apk = a[p][k], aqk = a[q][k]
                a[p][k] = c * apk - s * aqk
                a[q][k] = s * apk + c * aqk
            }
            for k in 0 ..< 3 {
                let vkp = v[k][p], vkq = v[k][q]
                v[k][p] = c * vkp - s * vkq
                v[k][q] = s * vkp + c * vkq
            }
        }
        return (0 ..< 3).sorted { a[$0][$0] > a[$1][$1] }.map { i in
            simd_normalize(SIMD3<Float>(Float(v[0][i]), Float(v[1][i]), Float(v[2][i])))
        }
    }

    static func box(_ nodes: [SCNNode], in space: SCNNode) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for node in nodes {
            let (a, b) = node.boundingBox
            for i in 0 ..< 8 {
                let p = SIMD3<Float>(Float(i & 1 == 0 ? a.x : b.x), Float(i & 2 == 0 ? a.y : b.y), Float(i & 4 == 0 ? a.z : b.z))
                let q = node.simdConvertPosition(p, to: space)
                lo = simd_min(lo, q)
                hi = simd_max(hi, q)
            }
        }
        return (lo, hi)
    }

    /// Replaces the display's texture coordinates with ones laid flat across its face (the model's own map a
    /// wallpaper, not a screen), and lifts it a hair off whatever is modelled flush with it. Returns its size.
    static func mapDisplay(_ display: SCNNode, in root: SCNNode) -> CGSize? {
        guard let geometry = display.geometry, let positions = geometry.sources(for: .vertex).first,
              positions.usesFloatComponents, positions.bytesPerComponent == 4, positions.componentsPerVector >= 3 else { return nil }
        var local: [SIMD3<Float>] = []
        local.reserveCapacity(positions.vectorCount)
        positions.data.withUnsafeBytes { raw in
            for i in 0 ..< positions.vectorCount {
                let o = positions.dataOffset + i * positions.dataStride
                guard o + 12 <= raw.count else { break }
                local.append(SIMD3(raw.loadUnaligned(fromByteOffset: o, as: Float.self),
                                   raw.loadUnaligned(fromByteOffset: o + 4, as: Float.self),
                                   raw.loadUnaligned(fromByteOffset: o + 8, as: Float.self)))
            }
        }
        guard local.count == positions.vectorCount, local.count >= 3 else { return nil }
        let placed = local.map { display.simdConvertPosition($0, to: root) }
        let lo = placed.reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude)) { simd_min($0, $1) }
        let hi = placed.reduce(SIMD3<Float>(repeating: -.greatestFiniteMagnitude)) { simd_max($0, $1) }
        let w = hi.x - lo.x, h = hi.y - lo.y
        guard w > 1e-5, h > 1e-5 else { return nil }
        // Metal's texture origin is the top-left; the display texture is drawn top-down to match.
        let uv = placed.map { SIMD2<Float>(($0.x - lo.x) / w, (hi.y - $0.y) / h) }
        let lift = display.simdConvertVector(SIMD3(0, 0, displayLift), from: root)
        let moved = local.map { $0 + lift }
        var sources = geometry.sources.filter { $0.semantic != .texcoord && $0.semantic != .vertex }
        sources.append(source(moved.flatMap { [$0.x, $0.y, $0.z] }, semantic: .vertex, components: 3))
        sources.append(source(uv.flatMap { [$0.x, $0.y] }, semantic: .texcoord, components: 2))
        let mapped = SCNGeometry(sources: sources, elements: geometry.elements)
        mapped.materials = geometry.materials
        display.geometry = mapped
        display.name = displayName
        return CGSize(width: CGFloat(w), height: CGFloat(h))
    }

    static func source(_ floats: [Float], semantic: SCNGeometrySource.Semantic, components: Int) -> SCNGeometrySource {
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(data: data, semantic: semantic, vectorCount: floats.count / components, usesFloatComponents: true,
                                 componentsPerVector: components, bytesPerComponent: 4, dataOffset: 0,
                                 dataStride: components * 4)
    }

    static func roundedRect(width w: Float, height h: Float, radius r: Float) -> SCNGeometry {
        let segments = 12
        let corners: [(SIMD2<Float>, Float)] = [
            (SIMD2(w / 2 - r, h / 2 - r), 0), (SIMD2(-w / 2 + r, h / 2 - r), .pi / 2),
            (SIMD2(-w / 2 + r, -h / 2 + r), .pi), (SIMD2(w / 2 - r, -h / 2 + r), 3 * .pi / 2),
        ]
        var outline: [SIMD2<Float>] = []
        for (c, start) in corners {
            for i in 0 ... segments {
                let a = start + Float(i) / Float(segments) * .pi / 2
                outline.append(c + r * SIMD2(cos(a), sin(a)))
            }
        }
        let points = [SIMD2<Float>(0, 0)] + outline
        let positions: [Float] = points.flatMap { [$0.x, $0.y, 0] }
        let normals: [Float] = points.flatMap { _ in [0, 0, 1] }
        let uv: [Float] = points.flatMap { [($0.x + w / 2) / w, (h / 2 - $0.y) / h] }
        var indices: [UInt16] = []
        for i in 1 ... outline.count { indices += [0, UInt16(i), UInt16(i % outline.count + 1)] }
        return SCNGeometry(sources: [source(positions, semantic: .vertex, components: 3), source(normals, semantic: .normal, components: 3),
                                     source(uv, semantic: .texcoord, components: 2)],
                           elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }
}
