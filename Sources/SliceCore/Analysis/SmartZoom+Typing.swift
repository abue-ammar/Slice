//
//  SmartZoom+Typing.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/17/26.
//

import CoreGraphics
import Foundation

/// Where typed text actually appears. The click before typing only says where the caret started: text grows away from
/// it, so a zoom framed on the click alone loses the words. The screen just before the typing is compared with
/// frames through it, and the change around the caret is what was typed.
extension SmartZoom {
    static let typingStep = 0.5
    static let maxTypingSamples = 12
    /// A typing zoom starts from at least this much typing when no click came before it.
    static let minLoneTyping = 1.5

    /// The moments `typedArea` should be measured for, with the times to read the screen at.
    static func typingSamples(_ moments: [Moment], duration: Double) -> [(moment: Int, before: Double, during: [Double])] {
        let last = max(duration - 0.02, 0)
        return moments.indices.compactMap { i in
            guard let start = moments[i].typingStart else { return nil }
            let lastKey = max(moments[i].end - typingTail, start)
            var during = Array(stride(from: start + typingStep, to: lastKey, by: typingStep))
            if during.count > maxTypingSamples {
                let step = Double(during.count - 1) / Double(maxTypingSamples - 1)
                during = (0 ..< maxTypingSamples).map { during[Int((Double($0) * step).rounded())] }
            }
            during.append(lastKey + 0.1)
            return (i, max(start - 0.15, 0), during.map { min($0, last) })
        }
    }

    /// The part of the screen that typing changed: the patch around the caret in each frame, joined up. Without a
    /// click to place the caret, the most substantial small change is taken to be it, and it has to keep growing as
    /// typed text does (something moving, like a progress bar, doesn't). A frame where most of the screen changed (a
    /// new page, a scroll) ends the measurement.
    static func typedArea(before: [UInt8], during: [[UInt8]], caret: CGPoint?) -> CGRect? {
        let guessed = caret == nil
        var caret = caret
        var area = CGRect.null
        var grew = 0
        for grid in during {
            let (fraction, regions) = ScreenChange.changes(before, grid)
            guard fraction <= 0.4 else { break }
            if caret == nil, let main = regions.filter({ $0.cells > 2 && $0.box.width * $0.box.height <= 0.1 }).max(by: { $0.cells < $1.cells }) {
                caret = CGPoint(x: main.box.minX, y: main.box.midY)
            }
            guard let caret, let found = ScreenChange.around(caret, in: regions) else { continue }
            let next = area.union(found)
            if next != area { grew += 1 }
            area = next
        }
        guard !area.isNull, area.width * area.height <= 0.25, !guessed || grew >= 2 else { return nil }
        return area
    }

    static func measureTyping(_ detection: inout Detection, video: URL, duration: Double,
                              progress: @escaping @Sendable (Double) -> Void) async {
        let plans = typingSamples(detection.moments, duration: duration)
        guard !plans.isEmpty else { return }
        let grids = await ScreenChange.grids(video: video, times: plans.flatMap { [$0.before] + $0.during }, progress: progress)
        for plan in plans {
            var m = detection.moments[plan.moment]
            if let before = grids[ScreenChange.key(plan.before)] {
                m.typed = typedArea(before: before, during: plan.during.compactMap { grids[ScreenChange.key($0)] },
                                    caret: m.kind == .click ? m.point : nil)
            }
            if m.kind == .typing {
                // Without a click there's nothing else to frame, so it only counts once the text is found.
                if let typed = m.typed {
                    m.point = CGPoint(x: typed.midX, y: typed.midY)
                    m.score += 0.15
                } else {
                    m.score -= 0.4
                }
            }
            detection.moments[plan.moment] = m
        }
    }

    /// The view for a stretch of typing too wide to show whole at a useful zoom: close enough to read the line,
    /// gliding from where the typing starts to where it ends.
    static func follow(_ typed: CGRect, limit: Double, _ g: ScreenGeometry) -> (scale: Double, from: CGPoint, to: CGPoint)? {
        let c = g.contentRect.size
        guard c.width > 0, c.height > 0 else { return nil }
        let tall = typed.height + 2 * margin
        let scale = min(limit * 0.85, g.fullBleedSize.height / (c.height * max(tall, 0.12)))
        guard scale >= minScale else { return nil }
        let half = g.fullBleedSize.width / scale / c.width / 2
        let from = typed.minX - margin + half, to = typed.maxX + margin - half
        guard to > from else { return nil }
        return (scale, CGPoint(x: from, y: typed.midY), CGPoint(x: to, y: typed.midY))
    }
}
