//
//  TimelineLanes.swift
//  Slice
//
//  Created by rit3zh CX on 10/12/26.
//

import SliceCore
import SwiftUI

extension Corner {
    var short: String {
        switch self {
        case .topLeft: "↖"
        case .topRight: "↗"
        case .bottomLeft: "↙"
        case .bottomRight: "↘"
        }
    }
}

extension EditorModel.TimelineLane {
    var color: Color {
        switch self {
        case .camera: Theme.camera
        case .zoom: Theme.zoom
        case .music: Theme.music
        }
    }

    var hint: String {
        switch self {
        case .camera: "Click to change the camera layout from here"
        case .zoom: "Click to zoom in here"
        case .music: "Click to add background music"
        }
    }

    var help: String {
        switch self {
        case .camera: "Add a camera layout here"
        case .zoom: "Add a zoom here"
        case .music: "Add music here"
        }
    }
}

@Observable
final class LaneHover {
    var x: CGFloat?
}

struct LaneTrack<Content: View>: View {
    let lane: EditorModel.TimelineLane
    let empty: Bool
    let pps: CGFloat
    let height: CGFloat
    let propose: (Double) -> ClosedRange<Double>?
    let tap: (Double) -> Void
    @ViewBuilder var content: Content
    @State private var hover = LaneHover()

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay {
                    if empty {
                        Text(lane.hint)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { v in tap(v.location.x / pps) })
            LaneGhost(lane: lane, hover: hover, pps: pps, height: height, propose: propose)
            content
        }
        .frame(height: height)
        .help(lane.help)
        .animation(Theme.hover, value: empty)
        .onContinuousHover { phase in
            switch phase {
            case let .active(p): hover.x = p.x
            case .ended: hover.x = nil
            }
        }
    }
}

struct LaneGhost: View {
    let lane: EditorModel.TimelineLane
    let hover: LaneHover
    let pps: CGFloat
    let height: CGFloat
    let propose: (Double) -> ClosedRange<Double>?
    @State private var last: ClosedRange<Double>?

    var body: some View {
        let range = hover.x.flatMap { propose($0 / pps) }
        let shown = range ?? last
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if let shown {
                let width = max((shown.upperBound - shown.lowerBound) * pps, 6)
                shape
                    .fill(LinearGradient(colors: [lane.color.opacity(0.8), lane.color.opacity(0.62)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: width, height: height)
                    .shadow(color: lane.color.opacity(0.35), radius: 8, y: 2)
                    .offset(x: shown.lowerBound * pps)
                    .transaction { $0.animation = nil }
            }
        }
        .animation(Theme.hover) { $0.opacity(range == nil ? 0 : 1) }
        .allowsHitTesting(false)
        .onChange(of: range) { _, new in if let new { last = new } }
    }
}

struct GutterButton: View {
    let symbol: String
    let hoverSymbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: hovering ? hoverSymbol : symbol)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(IconButtonStyle(size: 30, iconSize: 13))
        .onHover { hovering = $0 }
        .help(help)
    }
}
