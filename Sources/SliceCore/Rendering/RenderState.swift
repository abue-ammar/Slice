//
//  RenderState.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/8/26.
//

import CoreImage
import Foundation

public final class RenderState: @unchecked Sendable {
    private let lock = NSLock()
    private var project: Project
    private var cursor: CursorTrack
    private var options = FrameRenderer.Options()
    private var sceneCache: (size: CGSize, scene: RenderScene)?
    private var windows: [TransitionWindow]
    private var stills: [TransitionStill: CIImage] = [:]

    public init(project: Project, cursor: CursorTrack) {
        self.project = project
        self.cursor = cursor
        windows = project.transitionWindows
    }

    public func current() -> (project: Project, cursor: CursorTrack, options: FrameRenderer.Options) {
        lock.withLock { (project, cursor, options) }
    }

    public func update(project: Project, cursor: CursorTrack? = nil) {
        lock.withLock {
            self.project = project
            if let cursor { self.cursor = cursor }
            sceneCache = nil
            windows = project.transitionWindows
        }
    }

    public func update(options: FrameRenderer.Options) {
        lock.withLock {
            let bg = self.options.backgroundImage, captions = self.options.captions
            self.options = options
            self.options.backgroundImage = bg
            self.options.captions = captions
        }
    }

    public func add(stills: [TransitionStill: CIImage]) {
        lock.withLock { self.stills.merge(stills) { $1 } }
    }

    public func missing(_ stills: Set<TransitionStill>) -> Set<TransitionStill> {
        lock.withLock { stills.filter { self.stills[$0] == nil } }
    }

    public func transitionSources(at t: Double) -> TransitionSources? {
        lock.withLock {
            guard let w = windows.window(at: t) else { return nil }
            let held = w.held(at: t)
            guard project.clips.indices.contains(held.segment.clipIndex) else { return nil }
            let clip = project.clips[held.segment.clipIndex]
            guard let screen = stills[TransitionStill(clipID: clip.id, time: held.time, camera: false)] else { return nil }
            let camera = !clip.hasCamera(at: held.time) ? nil : stills[TransitionStill(clipID: clip.id, time: held.time, camera: true)]
            return TransitionSources(screen: screen, camera: camera, incoming: held.incoming)
        }
    }

    public func update(captions: [Caption]) {
        lock.withLock { options.captions = captions }
    }

    public func update(backgroundImage: CIImage?) {
        lock.withLock { options.backgroundImage = backgroundImage }
    }

    public func snapshot(size: CGSize) -> (RenderScene, FrameRenderer.Options) {
        lock.withLock {
            if let c = sceneCache, c.size == size { return (c.scene, options) }
            let scene = RenderScene(project: project, output: size, cursor: cursor)
            sceneCache = (size, scene)
            return (scene, options)
        }
    }
}
