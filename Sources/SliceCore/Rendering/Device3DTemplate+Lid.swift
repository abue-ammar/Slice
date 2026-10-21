//
//  Device3DTemplate+Lid.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/21/26.
//

import SceneKit
import simd

extension Device3DTemplate {
    static let lidName = "Slice lid"
    /// How far open a laptop's lid stands once the model faces the camera, before its base is laid flat: upright.
    static let modelledLid: Float = .pi / 2

    /// How far a laptop's base is tipped while its lid stands upright, as the turn about x that lays it flat: the turn
    /// that leaves everything well in front of the screen thinnest, as a slab is lying flat. (Fitting a slope to the
    /// vertices leans towards wherever the detail crowds them, the keys or the feet.)
    static func baseTilt(_ meshes: [SCNNode], display: SCNNode, in root: SCNNode) -> Float? {
        guard let screen = points(of: display, in: root), !screen.isEmpty else { return nil }
        let face = screen.reduce(0) { $0 + $1.z } / Float(screen.count) + 0.3
        let base = meshes.filter { $0 !== display }.flatMap { points(of: $0, in: root) ?? [] }.filter { $0.z > face }
        guard base.count > 16 else { return nil }
        func thickness(_ a: Float) -> Float {
            let c = cos(a), s = sin(a)
            var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
            for p in base {
                let y = p.y * c - p.z * s
                lo = min(lo, y)
                hi = max(hi, y)
            }
            return hi - lo
        }
        var best: Float = 0, step: Float = .pi / 180
        for a in stride(from: -40 * step, through: 40 * step, by: step) where thickness(a) < thickness(best) { best = a }
        // Then finer, around the best degree.
        for _ in 0 ..< 3 {
            let around = best
            step /= 10
            for a in stride(from: around - 10 * step, through: around + 10 * step, by: step) where thickness(a) < thickness(best) { best = a }
        }
        return best
    }

    /// Hangs a laptop's lid, modelled `opening` radians open, on its hinge so it can open and close. The lid is every piece rising above the base, split
    /// out of meshes that hold both (a shell moulded as one), under a node on the hinge's axis. The hinge goes where
    /// the closed lid rests on the base with its screen just clear of the keys and its lower edge flush with the
    /// base's back. Returns the hinge and the room the lid sweeps through, or nil when no lid stands out of a base.
    static func rigLid(_ meshes: [SCNNode], opening: Float, in root: SCNNode) -> (hinge: SIMD3<Float>, swept: (min: SIMD3<Float>, max: SIMD3<Float>))? {
        struct Piece { var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude) }
        struct Mesh { let node: SCNNode; let points: [SIMD3<Float>]; let triangles: [[[Int]]]; let piece: [Int] }
        var found: [Mesh] = []
        var pieces: [Piece] = []
        for node in meshes {
            guard let geometry = node.geometry, let points = points(of: node, in: root), !points.isEmpty else { continue }
            let triangles = geometry.elements.map { e in
                e.primitiveType == .triangles ? triangles(of: e).filter { $0.allSatisfy { $0 < points.count } } : []
            }
            var parent = Array(0 ..< points.count)
            func find(_ x: Int) -> Int {
                var x = x
                while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
                return x
            }
            // Corners split for their normals or texture coordinates are still one point of the surface.
            var at: [SIMD3<Int32>: Int] = [:]
            for (i, p) in points.enumerated() {
                let key = SIMD3<Int32>(p * 4096, rounding: .toNearestOrAwayFromZero)
                if let j = at[key] { parent[find(i)] = find(j) } else { at[key] = i }
            }
            for t in triangles.joined() {
                parent[find(t[0])] = find(t[1])
                parent[find(t[1])] = find(t[2])
            }
            var index: [Int: Int] = [:]
            var piece = [Int](repeating: -1, count: points.count)
            for t in triangles.joined() {
                for v in t where piece[v] < 0 {
                    let r = find(v)
                    let k = index[r] ?? { index[r] = pieces.count; pieces.append(Piece()); return pieces.count - 1 }()
                    piece[v] = k
                    pieces[k].lo = simd_min(pieces[k].lo, points[v])
                    pieces[k].hi = simd_max(pieces[k].hi, points[v])
                }
            }
            found.append(Mesh(node: node, points: points, triangles: triangles, piece: piece))
        }
        // The base is the piece spreading widest underneath; the lid, whatever stands up out of it.
        func footprint(_ p: Piece) -> Float { (p.hi.x - p.lo.x) * (p.hi.z - p.lo.z) }
        guard let base = pieces.max(by: { footprint($0) < footprint($1) }) else { return nil }
        let back = base.lo.z
        // Standing up out of the base, or tucked in behind it (the hinge's cover, hidden by the lid as modelled).
        let lid = pieces.map { $0.hi.y > base.hi.y + 0.02 || $0.hi.z < back - 0.002 }
        guard lid.contains(true), lid.contains(false) else { return nil }
        // The base's top, keys and all.
        let top = zip(pieces, lid).filter { !$0.1 }.map(\.0.hi.y).max() ?? base.hi.y

        // Up the lid and out of its face, in (y, z).
        let c = cos(opening), s = sin(opening)
        let up = SIMD2(s, c), out = SIMD2(-c, s)
        var low = Float.greatestFiniteMagnitude, front = -Float.greatestFiniteMagnitude
        var lidPoints: [SIMD3<Float>] = []
        for mesh in found {
            for (v, p) in mesh.points.enumerated() where mesh.piece[v] >= 0 && lid[mesh.piece[v]] {
                lidPoints.append(p)
                let q = SIMD2(p.y, p.z)
                low = min(low, simd_dot(q, up))
                if p.y > top + 0.1 { front = max(front, simd_dot(q, out)) }
            }
        }
        guard front > -.greatestFiniteMagnitude else { return nil }
        // Closed (turned by `opening` about the hinge h), the face comes to rest at y = h.y - (front - h·out), just clear
        // of the keys, and the lid's lower edge reaches z = h.z + (low - h·up), flush with the base's back.
        let a = 1 - c, rest = top + 0.002 + front, flush = back - low
        let hinge = SIMD3<Float>(0, (a * rest - s * flush) / (a * a + s * s), (s * rest + a * flush) / (a * a + s * s))

        let pivot = SCNNode()
        pivot.name = lidName
        pivot.simdPosition = hinge
        root.addChildNode(pivot)
        let offset = simd_float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(-hinge, 1)))
        for mesh in found {
            guard let geometry = mesh.node.geometry else { continue }
            let onLid = { (t: [Int]) in mesh.piece[t[0]] >= 0 && lid[mesh.piece[t[0]]] }
            let all = mesh.triangles.joined()
            guard all.contains(where: onLid) else { continue }
            let placed = mesh.node.simdConvertTransform(matrix_identity_float4x4, to: root)
            if all.allSatisfy(onLid), mesh.node.childNodes.isEmpty {
                mesh.node.removeFromParentNode()
                mesh.node.simdTransform = offset * placed
                pivot.addChildNode(mesh.node)
                continue
            }
            guard let part = subset(of: geometry, mesh.triangles, where: onLid) else { continue }
            let node = SCNNode(geometry: part)
            node.name = (mesh.node.name ?? "") + " lid"
            node.categoryBitMask = mesh.node.categoryBitMask
            node.simdTransform = offset * placed
            pivot.addChildNode(node)
            mesh.node.geometry = subset(of: geometry, mesh.triangles) { !onLid($0) }
        }

        // From closed (a quarter turn forward) to as far open as a lid goes, past upright.
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        let widest = Float(Device3DSettings.lidRange.upperBound) * .pi / 180
        for step in 0 ... 12 {
            let turn = opening - widest * Float(step) / 12
            let tc = cos(turn), ts = sin(turn)
            for p in lidPoints {
                let dy = p.y - hinge.y, dz = p.z - hinge.z
                let q = SIMD3(p.x, hinge.y + dy * tc - dz * ts, hinge.z + dy * ts + dz * tc)
                lo = simd_min(lo, q)
                hi = simd_max(hi, q)
            }
        }
        return (hinge, (lo, hi))
    }

    /// The triangles of `triangles` (per element of `geometry`) that `take` picks, as a geometry of their own sharing
    /// the vertices and materials.
    private static func subset(of geometry: SCNGeometry, _ triangles: [[[Int]]], where take: ([Int]) -> Bool) -> SCNGeometry? {
        var elements: [SCNGeometryElement] = [], materials: [SCNMaterial] = []
        for (e, list) in triangles.enumerated() {
            let picked = list.filter(take)
            guard !picked.isEmpty else { continue }
            elements.append(SCNGeometryElement(indices: picked.joined().map { UInt32($0) }, primitiveType: .triangles))
            if !geometry.materials.isEmpty { materials.append(geometry.materials[e % geometry.materials.count]) }
        }
        guard !elements.isEmpty else { return nil }
        let part = SCNGeometry(sources: geometry.sources, elements: elements)
        part.materials = materials
        return part
    }
}
