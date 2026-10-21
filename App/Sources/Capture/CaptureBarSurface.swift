//
//  CaptureBarSurface.swift
//  Slice
//
//  Created by rit3zh CX on 10/1/26.
//

import BorderBeamKit
import SwiftUI

enum BarStage: Equatable {
    case setup
    case countdown(Int)
    case live(canDraw: Bool)
    case drawing
    case saving

    /// `annotating` is nil when the recording can't be drawn on.
    init(phase: RecordingController.Phase?, annotating: Bool? = nil) {
        switch phase {
        case nil: self = .setup
        case .preparing: self = .countdown(3)
        case let .countdown(n): self = .countdown(n)
        case .recording, .paused: self = annotating == true ? .drawing : .live(canDraw: annotating != nil)
        case .finishing: self = .saving
        }
    }

    var surfaceSize: CGSize? {
        switch self {
        case .setup: nil
        case .countdown: CGSize(width: 112, height: 72)
        case let .live(canDraw): CGSize(width: canDraw ? LiveBar.liveWidth : LiveBar.plainWidth, height: 72)
        case .drawing: CGSize(width: LiveBar.drawingWidth, height: 72)
        case .saving: CGSize(width: 72, height: 72)
        }
    }
}

extension AnyTransition {
    static var stageContent: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.8))
                        .animation(.spring(response: 0.42, dampingFraction: 0.6).delay(0.12)),
                    removal: .opacity.combined(with: .scale(scale: 0.8))
                        .animation(.easeOut(duration: 0.14)))
    }
}

struct MorphSurface: View {
    let size: CGSize?

    var body: some View {
        GeometryReader { geo in
            let s = size ?? geo.size
            Color.clear
                .frame(width: s.width, height: s.height)
                .modifier(BarSurface())
                // Soft blues with a hint of pink; a small hue range keeps the drift from turning it purple.
                .borderBeam(.md, colorVariant: .glacier, theme: .dark, borderRadius: Bar.radius, hueRange: 8,
                            tuning: BeamTuning(strokeOpacity: 1.6, innerOpacity: 1.2, bloomOpacity: 1.4, softness: 3))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

enum Bar {
    static let hover = Animation.spring(response: 0.26, dampingFraction: 0.82)
    static let press = Animation.spring(response: 0.2, dampingFraction: 0.55)
    static let radius: CGFloat = 22
    static let inset: CGFloat = 28
    static let glide = Animation.spring(response: 0.32, dampingFraction: 0.76)
}

struct BarSurface: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Bar.radius, style: .continuous)
        content
            .background {
                if #available(macOS 26, *) {
                    GlassBackground(cornerRadius: Bar.radius)
                } else {
                    ZStack {
                        VisualEffectBackground(material: .hudWindow).clipShape(shape)
                        shape.fill(Color.black.opacity(0.12))
                        shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    }
                }
            }
            .background(BarShadow(shape: shape))
    }
}

struct BarShadow: View {
    let shape: RoundedRectangle

    var body: some View {
        shape.fill(.black)
            // Kept inside `Bar.inset`: a wider shadow is cut off square at the bar window's edge.
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
            .mask {
                Rectangle().padding(-60)
                    .overlay(shape.blendMode(.destinationOut))
                    .compositingGroup()
            }
    }
}

@available(macOS 26, *)
struct GlassBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.cornerRadius = cornerRadius
        view.style = .regular
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = cornerRadius
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
