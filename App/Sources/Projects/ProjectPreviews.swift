//
//  ProjectPreviews.swift
//  Slice
//
//  Created by rit3zh CX on 10/2/26.
//

import AVFoundation
import SliceCore
import SwiftUI

extension ProjectBundle {
    var displayName: String { url.deletingPathExtension().lastPathComponent }

    var lastModified: Date {
        (try? projectURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

struct ProjectPreview {
    var image: CGImage?
    var aspect: CGFloat
    var duration: Double
    var takes: Int
    var modified: Date
}

@MainActor
final class ProjectPreviews {
    static let shared = ProjectPreviews()
    private var cache: [URL: ProjectPreview] = [:]
    private let renderer = FrameRenderer()

    func preview(for bundle: ProjectBundle) async -> ProjectPreview? {
        let modified = bundle.lastModified
        if let cached = cache[bundle.url], cached.modified == modified { return cached }
        let renderer = renderer
        guard let made = await Task.detached(priority: .utility, operation: {
            await Self.render(bundle, modified: modified, renderer: renderer)
        }).value else { return nil }
        cache[bundle.url] = made
        return made
    }

    private nonisolated static func render(_ bundle: ProjectBundle, modified: Date, renderer: FrameRenderer) async -> ProjectPreview? {
        guard let project = try? bundle.load() else { return nil }
        let size = project.outputSize(shortSide: 400)
        var preview = ProjectPreview(image: nil, aspect: size.width / max(size.height, 1), duration: project.duration,
                                     takes: project.clips.count, modified: modified)
        let t = min(project.duration * 0.15, 2)
        guard let segment = project.segments.last(where: { $0.editedStart <= t }) ?? project.segments.first else { return preview }
        let clip = project.clips[segment.clipIndex]
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: bundle.file(clip.screenFile)))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 1200)
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let local = segment.local(at: t)
        guard let frame = try? await generator.image(at: CMTime(seconds: local, preferredTimescale: 600)).image else { return preview }
        let scene = RenderScene(project: project, output: size,
                                cursor: CursorTrack(project: project, logs: bundle.loadCursorLogs(for: project)))
        let image = renderer.render(scene: scene, time: t, screen: CIImage(cgImage: frame), camera: nil,
                                    options: .init(ignoreZoom: true, hideCamera: true,
                                                   backgroundImage: bundle.backgroundImage(for: project)))
        preview.image = renderer.context.createCGImage(image, from: CGRect(origin: .zero, size: size))
        return preview
    }
}
