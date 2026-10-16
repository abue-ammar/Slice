//
//  RenderScene+Pointer.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/9/26.
//

import CoreGraphics
import Foundation

extension RenderScene {
    static let joinGlide = 0.3
    static let loopGlide = 0.8
    static let typeFade = 0.09

    public func pointer(at t: Double) -> CursorPointer? {
        let settings = project.cursor
        guard settings.visible, !segments.isEmpty else { return nil }
        let si = segmentIndex(at: t)
        let seg = segments[si]
        let clip = project.clips[seg.clipIndex]
        guard clip.hasEditableCursor, let path = cursor.motion.path(for: clip.id), !path.isEmpty else { return nil }
        let smooth = settings.smoothing > 0
        let start = seg.sourceStart
        let local = start + min(max(t - seg.editedStart, 0), seg.duration)
        let points = clip.captureRect.size
        let glideFrom = joinStart(before: si, smooth: smooth)
        let loop = settings.loopPosition ? loopTarget(for: clip, smooth: smooth) : nil
        let loopGlide = min(Self.loopGlide, project.duration / 3)

        func position(_ l: Double) -> CGPoint {
            let l = max(l, start)
            guard var p = path.position(at: l, smooth: smooth) else { return .zero }
            if let from = glideFrom, l - start < Self.joinGlide {
                let e = smoothstep((l - start) / Self.joinGlide)
                p = CGPoint(x: lerp(from.x, p.x, e), y: lerp(from.y, p.y, e))
            }
            let left = project.duration - (seg.editedStart + l - start)
            if let to = loop, loopGlide > 0, left < loopGlide {
                let e = smoothstep(1 - left / loopGlide)
                p = CGPoint(x: lerp(p.x, to.x, e), y: lerp(p.y, to.y, e))
            }
            return p
        }
        func lean(_ l: Double) -> Double {
            guard settings.tilt > 0 else { return 0 }
            let h = max(settings.tiltSmoothing, 0.02) / 4
            var sum = 0.0, weights = 0.0
            var later = position(l)
            for k in 0 ..< 12 {
                let earlier = position(l - Double(k + 1) * h)
                let w = exp(-Double(k) / 4)
                sum += w * Double(later.x - earlier.x) * Double(points.width) / h
                weights += w
                later = earlier
            }
            let maxAngle = settings.tiltMaxAngle * .pi / 180
            return -maxAngle * min(settings.tilt, 1) * tanh(sum / weights / 900)
        }

        var pointer = CursorPointer(pose: CursorPose(position: position(local), angle: lean(local)), screenPoints: points)
        if settings.hideWhenIdle {
            let idle = path.idleTime(at: local) - max(settings.idleDelay, 0)
            if idle > 0 {
                pointer.opacity = 1 - smoothstep(idle / CursorSettings.idleFade)
                if pointer.opacity <= 0.001 { return nil }
            }
        }
        let state = path.stableType(at: local, settle: max(settings.stateDelay, 0))
        pointer.type = state.type
        if let previous = state.previous, state.since > start, local - state.since < Self.typeFade {
            pointer.previousType = previous
            pointer.fade = smoothstep((local - state.since) / Self.typeFade)
        }
        let shutter = min(settings.blurShutter, local - start)
        if shutter > 0 {
            let content = geometry(at: t).contentRect
            func onScreen(_ age: Double) -> CGPoint {
                let v = view(at: project.style.motionBlur ? t - age : t)
                let k = output.width / v.width
                let p = position(local - age)
                return CGPoint(x: (content.minX + p.x * content.width - v.minX) * k,
                               y: (content.minY + p.y * content.height - v.minY) * k)
            }
            var travel = 0.0
            var later = onScreen(0)
            for k in 1 ... 8 {
                let earlier = onScreen(shutter * Double(k) / 8)
                travel += hypot(Double(later.x - earlier.x), Double(later.y - earlier.y))
                later = earlier
            }
            if travel > 2 {
                let n = min(Int(travel.rounded(.up)) + 1, 64)
                pointer.trail = (0 ..< n).map { i in
                    let l = local - shutter * Double(n - 1 - i) / Double(n - 1)
                    return i == n - 1 ? pointer.pose : CursorPose(position: position(l), angle: lean(l))
                }
                pointer.shutter = shutter
            }
        }
        return pointer
    }

    func loopTarget(for clip: Clip, smooth: Bool) -> CGPoint? {
        guard let first = segments.first else { return nil }
        let a = project.clips[first.clipIndex]
        guard a.hasEditableCursor, a.captureRect == clip.captureRect, let path = cursor.motion.path(for: a.id) else { return nil }
        return path.position(at: first.sourceStart, smooth: smooth)
    }

    func segmentIndex(at t: Double) -> Int {
        var lo = 0, hi = segments.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if segments[mid].editedStart <= t { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    func joinStart(before i: Int, smooth: Bool) -> CGPoint? {
        guard i > 0 else { return nil }
        let prev = segments[i - 1], seg = segments[i]
        let a = project.clips[prev.clipIndex], b = project.clips[seg.clipIndex]
        guard prev.clipIndex != seg.clipIndex, a.hasEditableCursor, a.captureRect == b.captureRect,
              let path = cursor.motion.path(for: a.id) else { return nil }
        return path.position(at: prev.sourceEnd, smooth: smooth)
    }
}
