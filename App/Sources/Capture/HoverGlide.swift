//
//  HoverGlide.swift
//  Slice
//
//  Created by rit3zh CX on 10/1/26.
//

import SwiftUI

@Observable
final class HoverGlide {
    private(set) var id: AnyHashable?
    /// Leaving one item and entering the next arrive as two events; hold the highlight briefly so it slides across.
    @ObservationIgnored private var leaving: DispatchWorkItem?

    func enter(_ id: AnyHashable) {
        leaving?.cancel()
        leaving = nil
        guard self.id != id else { return }
        withAnimation(Bar.glide) { self.id = id }
    }

    func exit(_ id: AnyHashable) {
        guard self.id == id else { return }
        leaving?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.id == id else { return }
            withAnimation(Bar.hover) { self.id = nil }
        }
        leaving = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07, execute: work)
    }
}

struct BarGlide {
    let tracker: HoverGlide
    let namespace: Namespace.ID
}

extension EnvironmentValues {
    @Entry var barGlide: BarGlide?
}

struct GlideHover: ViewModifier {
    let id: AnyHashable
    var cornerRadius: CGFloat = 12
    var opacity: Double = 0.08
    var enabled = true
    @Environment(\.barGlide) private var glide

    func body(content: Content) -> some View {
        content
            .background {
                if let glide, glide.tracker.id == id {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(opacity))
                        .matchedGeometryEffect(id: "hover", in: glide.namespace)
                        .transition(.opacity)
                }
            }
            .onHover { inside in
                guard let glide else { return }
                if inside && enabled { glide.tracker.enter(id) } else { glide.tracker.exit(id) }
            }
    }
}

extension View {
    func glideHover(_ id: AnyHashable, cornerRadius: CGFloat = 12, opacity: Double = 0.08, enabled: Bool = true) -> some View {
        modifier(GlideHover(id: id, cornerRadius: cornerRadius, opacity: opacity, enabled: enabled))
    }
}

struct GlideState {
    let glide: BarGlide?
    func hovering(_ id: AnyHashable) -> Bool { glide?.tracker.id == id }
}
