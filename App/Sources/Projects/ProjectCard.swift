//
//  ProjectCard.swift
//  Slice
//
//  Created by rit3zh CX on 10/2/26.
//

import SliceCore
import SwiftUI

struct ProjectCard: View {
    let bundle: ProjectBundle
    let open: () -> Void
    let delete: () -> Void
    @State private var preview: ProjectPreview?
    @State private var loaded = false
    @State private var hovering = false
    @State private var width: CGFloat = 1
    @State private var peel: CGFloat = 0
    @State private var peelStart: CGFloat?
    @State private var deleting = false
    @State private var swipe = HorizontalSwipe()

    private static let radius: CGFloat = 12
    private static let opened: CGFloat = 0.4
    private static let openAt: CGFloat = 0.18
    private static let deleteAt: CGFloat = 0.72
    private static let settle = Animation.spring(duration: 0.4, bounce: 0)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PeelEffect(progress: peel, cornerRadius: Self.radius) { face } underneath: { tray($0) }
            caption
                .opacity(deleting ? 0 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if peel > 0 { close() } else { open() }
        }
        .contextMenu {
            Button("Open") { open() }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([bundle.url]) }
            Divider()
            Button("Move to Trash", role: .destructive) { remove() }
        }
        .onHover { inside in
            hovering = inside
            if inside {
                followSwipes()
            } else {
                swipe.stop()
                if peel > 0, !deleting { close() }
            }
        }
        .onDisappear { swipe.stop() }
        .animation(Theme.hover, value: hovering)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task(id: bundle.url) {
            let made = await ProjectPreviews.shared.preview(for: bundle)
            withAnimation(.easeOut(duration: 0.25)) {
                preview = made
                loaded = true
            }
        }
    }

    private var face: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        return shape
            .fill(Theme.panel)
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay {
                if let image = preview?.image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: (preview?.aspect ?? 1) >= 1.3 ? .fill : .fit)
                        .scaleEffect(hovering ? 1.025 : 1)
                        .transition(.opacity)
                } else if loaded {
                    Image(systemName: "video")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.quaternary)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let preview {
                    Text(Self.timecode(preview.duration))
                        .font(.rounded(11, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(.black.opacity(0.5)))
                        .background(Capsule().fill(.ultraThinMaterial))
                        .padding(8)
                        .transition(.opacity)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(hovering ? 0.13 : 0.05), lineWidth: 1))
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bundle.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hovering ? Color.primary : Color.primary.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(preview.map { Self.age($0.modified) } ?? " ")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 2)
    }

    private func tray(_ uncovered: CGFloat) -> some View {
        let shown = min(1, uncovered / 70)
        return ZStack(alignment: .trailing) {
            Color(red: 0.86, green: 0.25, blue: 0.25)
            Button {
                Haptic.thud()
                remove()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .scaleEffect(0.8 + 0.2 * shown)
                    .frame(width: max(uncovered, 1))
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(shown)
            .help("Move to Trash")
        }
        .opacity(deleting ? 0 : 1)
    }

    // MARK: Peeling

    private func followSwipes() {
        swipe.onChange = { travel, ended in
            let start = peelStart ?? peel
            peelStart = start
            let next = Self.resist(start - travel / max(width, 1))
            feel(from: peel, to: next)
            guard ended else {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { peel = next }
                return
            }
            peelStart = nil
            if next >= Self.deleteAt {
                remove()
            } else if next >= Self.openAt, !(start >= Self.opened && next < start - 0.08) {
                withAnimation(Self.settle) { peel = Self.opened }
            } else {
                close()
            }
        }
        swipe.start()
    }

    private static func resist(_ p: CGFloat) -> CGFloat {
        let knee: CGFloat = 0.85
        guard p > knee else { return max(p, 0) }
        return min(knee + (p - knee) * 0.35, 0.97)
    }

    private func feel(from old: CGFloat, to new: CGFloat) {
        if (old < Self.deleteAt) != (new < Self.deleteAt) {
            Haptic.thud()
        } else if (old < Self.openAt) != (new < Self.openAt) {
            Haptic.tick()
        }
    }

    private func close() {
        withAnimation(Self.settle) { peel = 0 }
    }

    private func remove() {
        guard !deleting else { return }
        swipe.stop()
        withAnimation(.easeIn(duration: 0.3)) {
            peel = 1
            deleting = true
        } completion: {
            delete()
        }
    }

    static func timecode(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func age(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "Just now" }
        if Date().timeIntervalSince(date) < 7 * 86400 {
            return date.formatted(.relative(presentation: .named))
        }
        let thisYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        return thisYear ? date.formatted(.dateTime.month(.abbreviated).day()) : date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
