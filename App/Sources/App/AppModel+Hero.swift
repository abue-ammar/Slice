//
//  AppModel+Hero.swift
//  Slice
//
//  Created by rit3zh CX on 10/18/26.
//

import AppKit
import SliceCore
import SwiftUI

/// Where each project card's picture sits and where the editor puts its preview, so opening a project flies from
/// one to the other and going back flies home, landing exactly where the picture will be.
@MainActor
final class ProjectFaces: ObservableObject {
    static let shared = ProjectFaces()

    struct Face {
        var rect: CGRect = .zero
        var image: CGImage?
        var aspect: CGFloat = 16 / 10
        var ready = false
    }

    /// The card whose picture is in flight; it stays blank until the picture lands.
    @Published private(set) var hidden: URL?
    var busy = false
    var gridAtTop = true
    private var live: [URL: Face] = [:]
    private var remembered: [URL: CGRect] = [:]
    private var waiters: [URL: [() -> Void]] = [:]
    /// The first card's picture with the grid at the top, and the window size it was measured in.
    private var firstSlot: (rect: CGRect, window: CGSize)?
    /// The room the editor fits its preview into, as insets from the window's edges (top, left, bottom, right).
    private var previewInsets = UserDefaults.standard.array(forKey: "hero.previewInsets") as? [CGFloat]

    func face(_ url: URL) -> Face? { live[url] }

    func hide(_ url: URL?) {
        if hidden != url { hidden = url }
    }

    /// `rect` is the card picture's frame in SwiftUI's global space.
    func moved(_ url: URL, to rect: CGRect) {
        live[url, default: Face()].rect = rect
        remembered[url] = rect
    }

    func loaded(_ url: URL, image: CGImage?, aspect: CGFloat) {
        live[url, default: Face()].image = image
        live[url]?.aspect = aspect
        live[url]?.ready = true
        waiters.removeValue(forKey: url)?.forEach { $0() }
    }

    func gone(_ url: URL) { live[url] = nil }

    func whenReady(_ url: URL, _ body: @escaping () -> Void) {
        if live[url]?.ready == true { body() } else { waiters[url, default: []].append(body) }
    }

    func measuredFirstCard(_ rect: CGRect) {
        guard let size = AppModel.mainWindow?.contentView?.bounds.size else { return }
        firstSlot = (rect, size)
    }

    func measuredPreviewArea(_ rect: CGRect) {
        guard let size = AppModel.mainWindow?.contentView?.bounds.size, rect.width > 0, rect.height > 0 else { return }
        let insets = [rect.minY, rect.minX, size.height - rect.maxY, size.width - rect.maxX].map { $0.rounded() }
        guard insets != previewInsets else { return }
        previewInsets = insets
        UserDefaults.standard.set(insets, forKey: "hero.previewInsets")
    }

    /// Where the editor will put a preview of this shape, in SwiftUI's global space.
    func previewGuess(in size: CGSize, aspect: CGFloat) -> CGRect {
        let i = previewInsets ?? [104, 40, 402, 446]
        let area = CGRect(x: i[1], y: i[0], width: max(size.width - i[1] - i[3], 120), height: max(size.height - i[0] - i[2], 80))
        let w = min(area.width, area.height * aspect), h = w / aspect
        return CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
    }

    /// Where this project's card will be once the grid is back. A project just closed was just saved, so it's the
    /// newest: the first card, with the grid at the top.
    func cardGuess(_ url: URL, in size: CGSize) -> CGRect? {
        if let firstSlot, firstSlot.window == size { return firstSlot.rect }
        return remembered[url]
    }
}

extension AppModel {
    private static let cover = 0.16

    /// The card's picture grows into the editor's preview while the editor is built underneath it; the editor fades
    /// in around the picture as it lands. False when there's no card to fly from.
    func heroOpen(_ bundle: ProjectBundle) -> Bool {
        let faces = ProjectFaces.shared
        guard !faces.busy, case .home = screen, let window = Self.mainWindow, window.isVisible,
              let face = faces.face(bundle.url), face.ready, let from = window.rect(fromSwiftUI: face.rect),
              window.showsMostOf(from), let size = window.contentView?.bounds.size
        else { return false }
        faces.busy = true
        let image = ProjectPreviews.shared.frame(for: bundle) ?? face.image
        let hero = ScreenHero(over: window, image: image, at: from, fills: face.aspect >= 1.3, shadowed: false,
                              zoomed: ProjectCard.hoverZoom)
        faces.hide(bundle.url)
        hero.backdrop(to: 1, duration: Self.cover)
        hero.shadow(to: 0.45, duration: 0.45)
        if let to = window.rect(fromSwiftUI: faces.previewGuess(in: size, aspect: face.aspect)) { hero.move(to: to) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cover + 0.01) { [weak self] in
            guard let self else { return }
            guard let next = editorScreen(for: bundle) else {
                hero.move(to: from)
                hero.shadow(to: 0, duration: 0.3)
                hero.backdrop(to: 0, duration: 0.3)
                hero.finish(delay: 0.4)
                faces.hide(nil)
                faces.busy = false
                return
            }
            show(next, animated: false)
            DispatchQueue.main.async { self.landInEditor(hero, in: window) }
        }
        return true
    }

    private func landInEditor(_ hero: ScreenHero, in window: NSWindow) {
        let faces = ProjectFaces.shared
        let preview = PreviewNSView.current.flatMap { $0.window === window ? $0 : nil }
        if let preview, preview.windowRect != hero.target { hero.move(to: preview.windowRect) }
        // The real preview's shadow fades in with the editor, so the picture's own hands over to it.
        let reveal = max(0, 0.3 - hero.age)
        hero.backdrop(to: 0, duration: 0.3, delay: reveal)
        hero.shadow(to: 0, duration: 0.3, delay: reveal)
        var done = false
        let handoff = {
            guard !done else { return }
            done = true
            hero.finish(fade: 0.12, delay: max(0, ScreenHero.settled - hero.age))
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, ScreenHero.settled - hero.age) + 0.14) {
                faces.hide(nil)
                faces.busy = false
            }
        }
        preview?.whenDrawn { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: handoff) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: handoff)
    }

    /// The editor's preview flies back into its project's card while the grid fades in around it. False when there's
    /// no preview to fly from.
    func heroClose() -> Bool {
        let faces = ProjectFaces.shared
        guard !faces.busy, let editor = openEditor, let window = Self.mainWindow, window.isVisible,
              let preview = PreviewNSView.current, preview.window === window, let size = window.contentView?.bounds.size
        else { return false }
        faces.busy = true
        let url = editor.bundle.url
        let from = preview.windowRect
        let image = ProjectPreviews.shared.frame(for: editor.bundle) ?? preview.snapshot()
        let hero = ScreenHero(over: window, image: image, at: from, fills: from.width / max(from.height, 1) >= 1.3,
                              shadowed: true)
        faces.hide(url)
        // The real preview would stay behind as a second picture while the editor fades.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.layer?.opacity = 0
        CATransaction.commit()
        hero.backdrop(to: 1, duration: Self.cover)
        hero.shadow(to: 0, duration: 0.4)
        if let to = faces.cardGuess(url, in: size).flatMap(window.rect(fromSwiftUI:)) { hero.move(to: to) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cover + 0.01) { [weak self] in
            guard let self else { return }
            // Sorted before the grid is made, so it doesn't re-sort (and slide) under the landing picture.
            reloadProjects()
            show(.home, animated: false)
            DispatchQueue.main.async { self.landOnCard(hero, url: url, in: window) }
        }
        return true
    }

    private func landOnCard(_ hero: ScreenHero, url: URL, in window: NSWindow) {
        let faces = ProjectFaces.shared
        guard let face = faces.face(url), let rect = window.rect(fromSwiftUI: face.rect), window.showsMostOf(rect) else {
            // The card is out of sight: the picture sinks away where it is.
            let t = hero.target
            hero.move(to: t.insetBy(dx: t.width * 0.06, dy: t.height * 0.06))
            hero.backdrop(to: 0, duration: 0.3)
            hero.finish(fade: 0.24, delay: 0.04)
            faces.hide(nil)
            faces.busy = false
            return
        }
        if rect != hero.target { hero.move(to: rect) }
        hero.backdrop(to: 0, duration: 0.3)
        var done = false
        let handoff = {
            guard !done else { return }
            done = true
            let wait = max(0, ScreenHero.settled - hero.age)
            // The card is shown first and the picture only fades once it's drawn underneath; fading on the same
            // beat left a frame of half a picture over an empty slot.
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                faces.hide(nil)
                hero.finish(fade: 0.1, delay: 0.08)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { faces.busy = false }
            }
        }
        faces.whenReady(url, handoff)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: handoff)
    }
}

private extension NSWindow {
    /// A rect from SwiftUI's global space (top-left origin) in window coordinates.
    func rect(fromSwiftUI r: CGRect) -> CGRect? {
        guard let view = contentView, r.width > 0, r.height > 0 else { return nil }
        let local = view.isFlipped ? r : CGRect(x: r.minX, y: view.bounds.height - r.maxY, width: r.width, height: r.height)
        return view.convert(local, to: nil)
    }

    func showsMostOf(_ rect: CGRect) -> Bool {
        guard let view = contentView else { return false }
        let seen = view.convert(view.bounds, to: nil).intersection(rect)
        return !seen.isNull && seen.height >= rect.height * 0.5 && seen.width >= rect.width * 0.5
    }
}
