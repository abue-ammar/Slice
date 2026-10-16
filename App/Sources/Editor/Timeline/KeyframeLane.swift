//
//  KeyframeLane.swift
//  Slice
//
//  Created by rit3zh CX on 10/15/26.
//

import SliceCore
import SwiftUI

/// The timeline's 3D track: the phone's keyframes, as diamonds the phone moves between. Click the track to add one
/// with the pose the phone has there, drag one to retime it, select one to pose the phone at it.
struct KeyframeLane: View {
    @ObservedObject var editor: EditorModel
    let pps: CGFloat
    let height: CGFloat
    @State private var hoverX: CGFloat?

    private var keys: [Device3DKeyframe] { editor.project.device3D.keyframes }

    var body: some View {
        let keys = keys
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay {
                    if keys.isEmpty {
                        Text("Click to add a keyframe. The phone moves from one to the next")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { v in
                    withAnimation(Theme.hover) { editor.addKeyframe(at: v.location.x / pps) }
                })
            ForEach(Array(keys.indices.dropLast()), id: \.self) { i in
                let a = keys[i], b = keys[i + 1]
                let still = a.placement == b.placement
                Capsule()
                    .fill(Theme.phone.opacity(still ? 0.16 : 0.42))
                    .frame(width: max((b.time - a.time) * pps, 0), height: still ? 2 : 4)
                    .offset(x: a.time * pps, y: height / 2 - (still ? 1 : 2))
                    .allowsHitTesting(false)
            }
            if let x = hoverX, !keys.contains(where: { abs($0.time * pps - x) < KeyframeDiamond.size }) {
                KeyframeDiamond(selected: false, ghost: true)
                    .offset(x: x - KeyframeDiamond.size / 2, y: (height - KeyframeDiamond.size) / 2)
                    .allowsHitTesting(false)
                    .transaction { $0.animation = nil }
            }
            ForEach(keys) { key in
                KeyframeHandle(editor: editor, key: key, pps: pps)
                    .offset(x: key.time * pps - KeyframeDiamond.size / 2, y: (height - KeyframeDiamond.size) / 2)
            }
        }
        .frame(height: height)
        .help("3D keyframes: click to add one, drag one to move it, Delete removes the selected one")
        .animation(Theme.hover, value: keys.isEmpty)
        .onContinuousHover { phase in
            switch phase {
            case let .active(p): hoverX = p.x
            case .ended: hoverX = nil
            }
        }
    }
}

private struct KeyframeHandle: View {
    @ObservedObject var editor: EditorModel
    let key: Device3DKeyframe
    let pps: CGFloat
    @State private var origin: Double?

    var body: some View {
        KeyframeDiamond(selected: editor.selection == .keyframe(key.id))
            .contentShape(Rectangle().inset(by: -4))
            .onTapGesture { editor.selectKeyframe(key.id) }
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { v in
                    if origin == nil {
                        origin = key.time
                        editor.selection = .keyframe(key.id)
                    }
                    let t = origin! + v.translation.width / pps
                    editor.moveKeyframe(key.id, to: t)
                    editor.scrub(to: min(max(t, 0), editor.duration))
                }
                .onEnded { _ in
                    origin = nil
                    editor.endScrub()
                })
    }
}

struct KeyframeDiamond: View {
    static let size: CGFloat = 14
    let selected: Bool
    var ghost = false
    @State private var hovering = false

    var body: some View {
        let lit = hovering || selected
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(ghost ? AnyShapeStyle(Theme.phone.opacity(0.35))
                : AnyShapeStyle(LinearGradient(colors: [Theme.phone.opacity(lit ? 1 : 0.92), Theme.phone.opacity(lit ? 0.8 : 0.7)],
                                               startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Color.white.opacity(selected ? 0.95 : ghost ? 0.25 : hovering ? 0.4 : 0.18), lineWidth: selected ? 2 : 1))
            .frame(width: Self.size / 1.25, height: Self.size / 1.25)
            .rotationEffect(.degrees(45))
            .frame(width: Self.size, height: Self.size)
            .scaleEffect(selected ? 1.18 : hovering ? 1.08 : 1)
            .shadow(color: Theme.phone.opacity(lit && !ghost ? 0.5 : 0), radius: 6, y: 1)
            .onHover { hovering = $0 }
            .animation(Theme.hover, value: hovering)
            .animation(Theme.hover, value: selected)
    }
}
