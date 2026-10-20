//
//  AnnotationBlock.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/20/26.
//

import CoreGraphics
import Foundation

/// A mark drawn while recording, placed on the timeline so it can be edited like any other block. It's a copy of
/// what the take logged, so changing or deleting it never touches the recording or its log.
public struct AnnotationBlock: Codable, Equatable, Identifiable {
    public var id: UUID
    public var start: Double
    public var end: Double
    /// Its points timed from `start`, as fractions of the screen with a top-left origin.
    public var mark: Annotation
    /// Draws itself on stroke by stroke as it was drawn; off, it's all there from `start`.
    public var drawsIn: Bool
    /// The take it was drawn over.
    public var clipID: UUID?

    public init(id: UUID = UUID(), start: Double, end: Double, mark: Annotation, drawsIn: Bool = true, clipID: UUID? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.mark = mark
        self.drawsIn = drawsIn
        self.clipID = clipID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        start = try c.decode(Double.self, forKey: .start)
        end = try c.decode(Double.self, forKey: .end)
        mark = try c.decode(Annotation.self, forKey: .mark)
        drawsIn = try c.decodeIfPresent(Bool.self, forKey: .drawsIn) ?? true
        clipID = try c.decodeIfPresent(UUID.self, forKey: .clipID)
    }

    public func isActive(at t: Double) -> Bool { t >= start && t < end }

    /// How many points are drawn at timeline time `t`.
    public func drawnCount(at t: Double) -> Int {
        guard isActive(at: t) else { return 0 }
        return drawsIn ? max(mark.drawnCount(at: t - start), 1) : mark.points.count
    }

    /// Where the mark sits, as fractions of a screen `screenPoints` big, with a top-left origin.
    public func bounds(screenPoints size: CGSize) -> CGRect {
        let pts = mark.points.map(\.location)
        guard let first = pts.first, size.width > 0, size.height > 0 else { return .zero }
        guard mark.tool == .text else {
            return pts.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        }
        let r = AnnotationPainter.bounds(of: mark, count: pts.count, scale: 1) {
            CGPoint(x: $0.x * size.width, y: (1 - $0.y) * size.height)
        }
        return CGRect(x: r.minX / size.width, y: 1 - r.maxY / size.height, width: r.width / size.width, height: r.height / size.height)
    }

    /// Moves the mark so its bounds become `rect`, scaling its points, or a label's size, to fit.
    public mutating func fit(to rect: CGRect, screenPoints size: CGSize) {
        let old = bounds(screenPoints: size)
        if mark.tool == .text {
            let k = old.height > 1e-6 ? rect.height / old.height : 1
            mark.width = min(max(mark.width * k, 0.5), 40)
            let anchor = mark.points.first?.location ?? .zero
            let dx = rect.minX - old.minX, dy = rect.minY - old.minY
            mark.points = mark.points.map { .init(t: $0.t, x: anchor.x + dx, y: anchor.y + dy) }
            return
        }
        let sx = old.width > 1e-6 ? rect.width / old.width : 1
        let sy = old.height > 1e-6 ? rect.height / old.height : 1
        mark.points = mark.points.map { p in
            .init(t: p.t, x: rect.minX + (p.x - old.minX) * sx, y: rect.minY + (p.y - old.minY) * sy)
        }
    }

    /// The marks a take logged, each from its first point until it was undone, cleared or the take ended.
    public static func imported(from log: CursorLog, clipIndex i: Int, in project: Project) -> [AnnotationBlock] {
        guard project.clips.indices.contains(i) else { return [] }
        let clip = project.clips[i]
        return log.annotations.compactMap { a in
            guard let first = a.start, first <= clip.duration else { return nil }
            let start = project.editedPosition(clipIndex: i, local: first)
            let end = project.editedPosition(clipIndex: i, local: min(a.end ?? clip.duration, clip.duration))
            guard end - start > 0.05 else { return nil }
            var mark = a
            mark.points = a.points.map { .init(t: $0.t - first, x: $0.x, y: $0.y) }
            mark.end = nil
            return AnnotationBlock(start: start, end: end, mark: mark, clipID: clip.id)
        }
    }
}

extension Project {
    public func annotations(at t: Double) -> [AnnotationBlock] { annotations.filter { $0.isActive(at: t) } }
}
