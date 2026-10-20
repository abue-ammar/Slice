//
//  CursorLog.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/15/26.
//

import CoreGraphics
import Foundation

public struct CursorLog: Codable, Equatable {
    public struct Sample: Codable, Equatable {
        public var t: Double
        public var x: Double
        public var y: Double
        public init(t: Double, x: Double, y: Double) { self.t = t; self.x = x; self.y = y }
    }

    public struct TypeChange: Codable, Equatable {
        public var t: Double
        public var type: CursorType
        public init(t: Double, type: CursorType) { self.t = t; self.type = type }
    }

    public var samples: [Sample]
    public var clicks: [Sample]
    public var types: [TypeChange]
    public var keys: [KeyPress]
    public var scrolls: [Sample]
    public var typing: [Double]
    public var hits: [KeyHit]
    public var annotations: [Annotation]

    public init(samples: [Sample] = [], clicks: [Sample] = [], types: [TypeChange] = [], keys: [KeyPress] = [],
                scrolls: [Sample] = [], typing: [Double] = [], hits: [KeyHit] = [], annotations: [Annotation] = []) {
        self.samples = samples
        self.clicks = clicks
        self.types = types
        self.keys = keys
        self.scrolls = scrolls
        self.typing = typing
        self.hits = hits
        self.annotations = annotations
    }

    public var keyHits: [KeyHit] {
        guard hits.isEmpty else { return hits }
        return (keys.map { KeyHit(t: $0.t, kind: KeyHit.kind(named: $0.key)) } + typing.map { KeyHit(t: $0, kind: .key) })
            .sorted { $0.t < $1.t }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        samples = try c.decode([Sample].self, forKey: .samples)
        clicks = try c.decode([Sample].self, forKey: .clicks)
        types = try c.decodeIfPresent([TypeChange].self, forKey: .types) ?? []
        keys = try c.decodeIfPresent([KeyPress].self, forKey: .keys) ?? []
        scrolls = try c.decodeIfPresent([Sample].self, forKey: .scrolls) ?? []
        typing = try c.decodeIfPresent([Double].self, forKey: .typing) ?? []
        hits = try c.decodeIfPresent([KeyHit].self, forKey: .hits) ?? []
        annotations = try c.decodeIfPresent([Annotation].self, forKey: .annotations) ?? []
    }
}
