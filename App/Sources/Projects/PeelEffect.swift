//
//  PeelEffect.swift
//  Slice
//
//  Created by rit3zh CX on 10/9/26.
//

import AppKit
import SwiftUI

/// Peels its content back from the trailing edge like a page lifting off, uncovering `underneath`. `progress` runs
/// from 0 (flat) to 1 (peeled away). The lifted part folds back over the rest, mirrored and paler like the back of a
/// print, and never leaves the content's bounds. After inspo/PagePeelSwipe.
struct PeelEffect<Content: View, Underneath: View>: View {
    var progress: CGFloat
    var cornerRadius: CGFloat
    @ViewBuilder var content: Content
    @ViewBuilder var underneath: (CGFloat) -> Underneath

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .hidden()
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width
                    let p = min(max(progress, 0), 1)
                    let fold = w * (1 - p)
                    ZStack(alignment: .leading) {
                        if p > 0 {
                            underneath(w - fold)
                                .frame(width: w, height: geo.size.height)
                                .clipShape(shape)
                            Rectangle()
                                .fill(.black)
                                .frame(width: fold)
                                .shadow(color: .black.opacity(0.5), radius: 10, x: 8)
                                .frame(width: w, alignment: .leading)
                                .mask(shape)
                                .allowsHitTesting(false)
                        }
                        content
                            .mask(alignment: .leading) { Rectangle().frame(width: fold) }
                            .allowsHitTesting(false)
                        if p > 0 {
                            back(width: w, peeled: w - fold, fold: fold, shape: shape)
                        }
                    }
                    .clipShape(shape)
                }
            }
    }

    private func back(width w: CGFloat, peeled: CGFloat, fold: CGFloat, shape: RoundedRectangle) -> some View {
        content
            .overlay {
                ZStack(alignment: .trailing) {
                    shape.fill(Color.white.opacity(0.26))
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.4), location: 0.07),
                        .init(color: .clear, location: 0.35),
                        .init(color: .black.opacity(0.22), location: 1),
                    ], startPoint: .leading, endPoint: .trailing)
                        .frame(width: peeled)
                }
                .clipShape(shape)
            }
            .scaleEffect(x: -1)
            .offset(x: fold - peeled)
            .shadow(color: .black.opacity(0.35), radius: 6, x: -4)
            .mask(alignment: .leading) { Rectangle().frame(width: fold) }
            .allowsHitTesting(false)
    }
}

@MainActor
final class HorizontalSwipe {
    var onChange: (_ travel: CGFloat, _ ended: Bool) -> Void = { _, _ in }
    private var monitor: Any?
    private var tracking = false
    private var horizontal: Bool?
    private var travel: CGFloat = 0

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                return self.handle(event)
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if tracking, horizontal == true { onChange(travel, true) }
        tracking = false
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if !event.momentumPhase.isEmpty { return horizontal == true ? nil : event }
        guard event.hasPreciseScrollingDeltas, !event.phase.isEmpty else { return event }
        if event.phase.contains(.began) {
            tracking = true
            horizontal = nil
            travel = 0
        }
        guard tracking else { return event }
        if horizontal == nil, abs(event.scrollingDeltaX) + abs(event.scrollingDeltaY) > 0.5 {
            horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.3
        }
        let ended = event.phase.contains(.ended) || event.phase.contains(.cancelled)
        if ended { tracking = false }
        guard horizontal == true else { return event }
        // Deltas follow the content, which natural scrolling turns around; this is always the fingers' direction.
        travel += event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        onChange(travel, ended)
        return nil
    }
}

enum Haptic {
    static func tick() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    static func thud() { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
}
