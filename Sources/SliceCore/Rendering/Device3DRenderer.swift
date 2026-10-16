//
//  Device3DRenderer.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/15/26.
//

import AppKit
import CoreImage
import Metal
import SceneKit

public enum Device3DError: LocalizedError, Equatable {
    case missingModel(String)
    case unreadable(String)
    case noGPU

    public var errorDescription: String? {
        switch self {
        case let .missingModel(name): "The \(name) model is missing from the app."
        case let .unreadable(name): "The \(name) model couldn't be read."
        case .noGPU: "This Mac's graphics can't draw the 3D phone."
        }
    }
}

public enum Device3DStatus: Equatable {
    case ready(hasDisplayMesh: Bool)
    case failed(Device3DError)
}

/// One frame of the 3D phone.
struct Device3DRequest {
    /// The frame's size in pixels.
    var output: CGSize
    /// The part of the unzoomed frame this frame shows, in its pixels with a top-left origin.
    var view: CGRect
    /// Where the phone sits unposed at scale 1, in the unzoomed frame.
    var fit: CGRect
    var pose: Device3DPose
    var settings: Device3DSettings
    var landscape: Bool
    /// What's on the display: upright, portrait, at the model's display shape, origin at zero. Nil is a dark display.
    var display: CIImage?
}

// MARK: - Pool

/// The 3D phones Slice draws with, shared by the preview and export. A handful of stages let frames being exported
/// in parallel draw at once; each frame borrows one, draws and hands it back.
public final class Device3DRenderer: @unchecked Sendable {
    public static let shared = Device3DRenderer()

    private let lock = NSLock()
    private var templates: [Device3DModel: Result<Device3DTemplate, Device3DError>] = [:]
    private var idle: [Device3DStage] = []
    private let available = DispatchSemaphore(value: Device3DRenderer.stages)
    private let device = MTLCreateSystemDefaultDevice()

    static let stages = 2

    /// Whether `model` loads, and whether it has a display surface of its own. Loads it the first time.
    public func status(for model: Device3DModel) -> Device3DStatus {
        switch template(for: model) {
        case let .success(t): .ready(hasDisplayMesh: t.hasDisplayMesh)
        case let .failure(e): .failed(e)
        }
    }

    /// The model's display shape (width over height), once it has loaded.
    func displayAspect(for model: Device3DModel) -> CGFloat? {
        guard case let .success(t) = template(for: model), t.displaySize.height > 0 else { return nil }
        return t.displaySize.width / t.displaySize.height
    }

    /// Loads the model and draws a frame off screen, so the first real frame doesn't pay for shader compilation.
    public func warmUp(_ model: Device3DModel) {
        var settings = Device3DSettings()
        settings.model = model
        let size = CGSize(width: 256, height: 256)
        _ = render(Device3DRequest(output: size, view: CGRect(origin: .zero, size: size), fit: CGRect(origin: .zero, size: size),
                                   pose: settings.pose(at: 0), settings: settings, landscape: false, display: nil))
    }

    private let thumbnailContext = CIContext(options: [.cacheIntermediates: false])

    /// What thumbnails show on the display.
    private static let previewScreen: CIImage? = Bundle.module.url(forResource: "preview-model", withExtension: "jpg", subdirectory: "Models")
        .flatMap { CIImage(contentsOf: $0) }

    /// A still of `model` in `finish` posed as `placement` (centred), `size` pixels, with the preview wallpaper on its
    /// display and a clear background: for pickers.
    public func thumbnail(model: Device3DModel, finish: Device3DFinish, placement: Device3DPlacement = .standard,
                          size: CGSize) -> CGImage? {
        var settings = Device3DSettings()
        settings.model = model
        settings.finish = finish
        settings.placement = placement
        settings.position = .zero
        settings.perspective = 0.45
        guard let aspect = displayAspect(for: model), size.width >= 8, size.height >= 8 else { return nil }
        let g = Self.previewScreen.map { image -> CIImage in
            // Filled to the display's shape, centred.
            let e = image.extent, source = e.width / e.height
            let crop = source > aspect ? CGRect(x: e.midX - e.height * aspect / 2, y: e.minY, width: e.height * aspect, height: e.height)
                : CGRect(x: e.minX, y: e.midY - e.width / aspect / 2, width: e.width, height: e.width / aspect)
            return image.cropped(to: crop.integral)
        }
        let whole = CGRect(origin: .zero, size: size)
        let request = Device3DRequest(output: size, view: whole, fit: whole.insetBy(dx: size.width * 0.08, dy: size.height * 0.06),
                                      pose: settings.pose(at: 0), settings: settings, landscape: false, display: g)
        guard let image = render(request) else { return nil }
        return thumbnailContext.createCGImage(image, from: whole, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    func render(_ request: Device3DRequest) -> CIImage? {
        guard device != nil, case .success = template(for: request.settings.model) else { return nil }
        available.wait()
        defer { available.signal() }
        guard let stage = borrow(request.settings.model) else { return nil }
        defer { lock.withLock { idle.append(stage) } }
        return autoreleasepool { stage.render(request) }
    }

    private func borrow(_ model: Device3DModel) -> Device3DStage? {
        if let stage = lock.withLock({ () -> Device3DStage? in
            guard let i = idle.lastIndex(where: { $0.model == model }) else {
                // A stage for another model makes room for this one.
                if let j = idle.indices.first { idle.remove(at: j) }
                return nil
            }
            return idle.remove(at: i)
        }) { return stage }
        guard let device, case let .success(template) = template(for: model) else { return nil }
        return Device3DStage(model: model, template: template, device: device)
    }

    private func template(for model: Device3DModel) -> Result<Device3DTemplate, Device3DError> {
        lock.lock()
        defer { lock.unlock() }
        if let cached = templates[model] { return cached }
        let result: Result<Device3DTemplate, Device3DError>
        if device == nil {
            result = .failure(.noGPU)
        } else if let url = Bundle.module.url(forResource: model.resource, withExtension: "usdz", subdirectory: "Models") {
            do {
                result = .success(try Device3DTemplate(url: url, name: model.label, displayNode: model.displayNode,
                                                       bodyColor: model.bodyColor, bodyMaterials: model.bodyMaterials))
            } catch let error as Device3DError {
                result = .failure(error)
            } catch {
                result = .failure(.unreadable(model.label))
            }
        } else {
            result = .failure(.missingModel(model.label))
        }
        if case let .failure(error) = result { NSLog("3D model \(model.label) unavailable: \(error.localizedDescription)") }
        templates[model] = result
        return result
    }
}
