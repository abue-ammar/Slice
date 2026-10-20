//
//  Annotation.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/20/26.
//

import CoreGraphics
import Foundation

/// A mark drawn over the screen while recording. Every point keeps the moment it was drawn, so playback draws it
/// exactly as it went on, and `end` is when it was undone or cleared.
public struct Annotation: Codable, Hashable, Identifiable {
    public enum Tool: String, Codable, CaseIterable {
        case pen, highlighter, line, arrow, rectangle, ellipse, text
    }

    public struct Point: Codable, Hashable {
        public var t: Double
        public var x: Double
        public var y: Double
        public init(t: Double, x: Double, y: Double) { self.t = t; self.x = x; self.y = y }

        public var location: CGPoint { CGPoint(x: x, y: y) }
    }

    public var id: UUID
    public var tool: Tool
    public var color: RGBA
    /// Stroke width in screen points; a label's size follows it.
    public var width: Double
    /// A pen or highlighter's whole path; a shape's anchor and then where its other corner went; a label's anchor.
    public var points: [Point]
    public var text: String?
    public var end: Double?

    public init(id: UUID = UUID(), tool: Tool, color: RGBA, width: Double, points: [Point] = [], text: String? = nil,
                end: Double? = nil) {
        self.id = id
        self.tool = tool
        self.color = color
        self.width = width
        self.points = points
        self.text = text
        self.end = end
    }

    public var start: Double? { points.first?.t }

    /// How many of its points are drawn by `t`; none means it isn't on screen.
    public func drawnCount(at t: Double) -> Int {
        if let end, t >= end { return 0 }
        return points.firstIndex { $0.t > t } ?? points.count
    }

    /// This mark with times counted from `start`, or nil if it was gone by then. Anything already drawn is there from 0.
    public func since(_ start: Double) -> Annotation? {
        if let end, end <= start { return nil }
        var a = self
        a.points = points.map { Point(t: max($0.t - start, 0), x: $0.x, y: $0.y) }
        a.end = end.map { $0 - start }
        return a
    }

    /// Each point moved by `map`, times kept.
    public func mapped(_ map: (CGPoint) -> CGPoint) -> Annotation {
        var a = self
        a.points = points.map { p in
            let q = map(p.location)
            return Point(t: p.t, x: q.x, y: q.y)
        }
        return a
    }

    public var fontSize: Double { 12 + width * 2.4 }
}
