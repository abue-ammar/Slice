//
//  ProjectPreviews.swift
//  Slice
//
//  Created by rit3zh CX on 10/2/26.
//

import AVFoundation
import CryptoKit
import ImageIO
import SliceCore
import SwiftUI
import UniformTypeIdentifiers

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

/// Each card shows the frame the editor was on when the project was last closed, and the editor opens on that same
/// frame, so the picture that flies between them never changes. A project not closed since gets a frame rendered
/// at the moment the editor will open on.
@MainActor
final class ProjectPreviews {
    static let shared = ProjectPreviews()
    private var cache: [URL: ProjectPreview] = [:]
    /// Full-size frames kept as projects close, for the picture flying back in.
    private var frames: [URL: CGImage] = [:]
    private let renderer = FrameRenderer()

    private static let cardWidth = 960
    private static let playheads = "projects.playheads"

    func preview(for bundle: ProjectBundle) async -> ProjectPreview? {
        let modified = bundle.lastModified
        if let cached = cache[bundle.url], cached.modified == modified { return cached }
        let renderer = renderer
        guard let made = await Task.detached(priority: .utility, operation: {
            await Self.make(bundle, modified: modified, renderer: renderer)
        }).value else { return nil }
        cache[bundle.url] = made
        return made
    }

    /// Whatever is cached, without checking it's current: the card shows it at once, then checks.
    func cached(_ url: URL) -> ProjectPreview? { cache[url] }

    /// The editor's last frame, as it closes: the card and the next open both show exactly this.
    func keep(_ frame: CGImage?, at time: Double, project: Project, bundle: ProjectBundle) {
        Self.setPlayhead(time, for: bundle.url)
        guard let frame else { return }
        frames[bundle.url] = frame
        if frames.count > 6, let old = frames.keys.first(where: { $0 != bundle.url }) { frames[old] = nil }
        cache[bundle.url] = ProjectPreview(image: Self.scaled(frame, width: Self.cardWidth) ?? frame,
                                           aspect: CGFloat(frame.width) / CGFloat(max(frame.height, 1)),
                                           duration: project.duration, takes: project.clips.count, modified: bundle.lastModified)
        let file = Self.frameFile(for: bundle.url)
        Task.detached(priority: .utility) { Self.write(frame, to: file) }
    }

    /// The sharpest picture of the card there is, for the flight into the editor.
    func frame(for bundle: ProjectBundle) -> CGImage? {
        if let frame = frames[bundle.url] { return frame }
        guard let source = Self.freshFrame(for: bundle, modified: bundle.lastModified) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Where the editor opens: where it was left, or a little way in for a project never opened.
    nonisolated static func openingTime(for bundle: ProjectBundle, project: Project) -> Double {
        let saved = (UserDefaults.standard.dictionary(forKey: playheads)?[bundle.url.standardizedFileURL.path] as? Double)
        let t = saved ?? min(project.duration * 0.15, 2)
        return min(max(t, 0), max(project.duration - 0.05, 0))
    }

    private static func setPlayhead(_ time: Double, for url: URL) {
        var all = UserDefaults.standard.dictionary(forKey: playheads) ?? [:]
        all[url.standardizedFileURL.path] = time
        UserDefaults.standard.set(all, forKey: playheads)
    }

    // MARK: Making

    private nonisolated static func make(_ bundle: ProjectBundle, modified: Date, renderer: FrameRenderer) async -> ProjectPreview? {
        guard let project = try? bundle.load() else { return nil }
        let size = project.outputSize(shortSide: 400)
        var preview = ProjectPreview(image: nil, aspect: size.width / max(size.height, 1), duration: project.duration,
                                     takes: project.clips.count, modified: modified)
        if let source = freshFrame(for: bundle, modified: modified) {
            let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: cardWidth,
                           kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
            if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
                preview.image = image
                preview.aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
                return preview
            }
        }
        preview.image = await render(bundle, project: project, size: size, renderer: renderer)
        return preview
    }

    private nonisolated static func render(_ bundle: ProjectBundle, project: Project, size: CGSize, renderer: FrameRenderer) async -> CGImage? {
        let t = openingTime(for: bundle, project: project)
        guard let segment = project.segments.last(where: { $0.editedStart <= t }) ?? project.segments.first else { return nil }
        let clip = project.clips[segment.clipIndex]
        let local = CMTime(seconds: segment.local(at: t), preferredTimescale: 600)
        guard let screen = await still(bundle.file(clip.screenFile), at: local) else { return nil }
        var camera: CGImage?
        if let file = clip.cameraFile { camera = await still(bundle.file(file), at: local) }
        let scene = RenderScene(project: project, output: size,
                                cursor: CursorTrack(project: project, logs: bundle.loadCursorLogs(for: project)))
        let image = renderer.render(scene: scene, time: t, screen: CIImage(cgImage: screen), camera: camera.map { CIImage(cgImage: $0) },
                                    options: .init(backgroundImage: bundle.backgroundImage(for: project)))
        return renderer.context.createCGImage(image, from: CGRect(origin: .zero, size: size))
    }

    private nonisolated static func still(_ url: URL, at time: CMTime) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 1200)
        let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        return try? await generator.image(at: time).image
    }

    // MARK: Frames on disk

    private nonisolated static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Slice").appendingPathComponent("Last Frames")
    }

    private nonisolated static func frameFile(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(digest).appendingPathExtension("jpg")
    }

    /// The kept frame, unless the project has changed since it was kept.
    private nonisolated static func freshFrame(for bundle: ProjectBundle, modified: Date) -> CGImageSource? {
        let file = frameFile(for: bundle.url)
        guard let kept = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              kept >= modified else { return nil }
        return CGImageSourceCreateWithURL(file as CFURL, nil)
    }

    private nonisolated static func write(_ image: CGImage, to file: URL) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let out = CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(out, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        CGImageDestinationFinalize(out)
    }

    private static func scaled(_ image: CGImage, width: Int) -> CGImage? {
        guard image.width > width else { return image }
        let height = Int((CGFloat(image.height) * CGFloat(width) / CGFloat(image.width)).rounded())
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
