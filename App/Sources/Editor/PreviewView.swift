//
//  PreviewView.swift
//  Slice
//
//  Created by rit3zh CX on 10/8/26.
//

import AVFoundation
import CoreImage
import Metal
import QuartzCore
import SliceCore
import SwiftUI

struct PreviewSurface: NSViewRepresentable {
    let driver: PreviewDriver
    var quality: Double = 1

    func makeNSView(context: Context) -> PreviewNSView { PreviewNSView(driver: driver) }

    func updateNSView(_ view: PreviewNSView, context: Context) { view.quality = quality }
}

enum PreviewQuality: Double, CaseIterable {
    case full = 1, balanced = 0.75, fast = 0.5

    var label: String {
        switch self {
        case .full: "Full (Retina)"
        case .balanced: "Balanced"
        case .fast: "Fast"
        }
    }
}

struct PreviewSourceFrame {
    let time: Double
    let screen: CIImage?
    let camera: CIImage?
}

final class PreviewDriver: @unchecked Sendable {
    let renderState: RenderState
    private let lock = NSLock()
    private var output: AVPlayerItemVideoOutput?
    private var packing: PreviewPacking?
    private var playing = false
    private var pausedTime = 0.0
    private var duration = 0.0
    private var version = 0
    /// Just after playback starts: the player's clock runs before its first new frame is decoded, so the pointer and
    /// zooms would set off ahead of a frozen picture. The preview stays on the paused moment until that frame arrives.
    private var holding = false
    /// A seek during playback: the output still hands out frames from before the jump, so they're skipped until it lands.
    private var seeking = false
    private var shown = 0.0

    var shownTime: Double { lock.withLock { shown } }

    init(renderState: RenderState) { self.renderState = renderState }

    func setSource(_ output: AVPlayerItemVideoOutput, packing: PreviewPacking?) {
        lock.withLock {
            self.output = output
            self.packing = packing
            version &+= 1
        }
    }

    func setPlayback(playing: Bool, seeking: Bool = false, time: Double, duration: Double) {
        lock.withLock {
            if playing, !self.playing || seeking || self.seeking { holding = true }
            self.seeking = playing && seeking
            if !playing { holding = false }
            self.playing = playing
            pausedTime = time
            self.duration = duration
            version &+= 1
        }
    }

    func invalidate() { lock.withLock { version &+= 1 } }

    func moment(atHostTime hostTime: CFTimeInterval) -> (time: Double, version: Int, frame: PreviewSourceFrame?) {
        let (output, packing, playing, paused, duration, version, holding, seeking) = lock.withLock {
            (self.output, self.packing, self.playing, pausedTime, self.duration, self.version, self.holding, self.seeking)
        }
        var time = paused
        var frame: PreviewSourceFrame?
        if let output, !seeking {
            let item = output.itemTime(forHostTime: hostTime)
            var shown = CMTime.invalid
            if item.isValid, output.hasNewPixelBuffer(forItemTime: item),
               let buffer = output.copyPixelBuffer(forItemTime: item, itemTimeForDisplay: &shown), let packing {
                let at = shown.isValid ? shown.seconds : item.seconds
                let project = renderState.current().project
                let clip = project.clipStarts.lastIndex { $0 <= at + 1e-6 } ?? 0
                let hasCamera = project.clips.indices.contains(clip) && project.clips[clip].cameraFile != nil
                    && packing.hasCamera(in: buffer)
                let sources = packing.unpack(CIImage(cvPixelBuffer: buffer), clip: clip, hasCamera: hasCamera)
                frame = PreviewSourceFrame(time: at, screen: sources.screen, camera: sources.camera)
            }
            if playing, item.isValid, item.seconds.isFinite, !holding || frame != nil {
                time = min(max(item.seconds, 0), duration)
            }
        }
        lock.withLock {
            if frame != nil, self.playing { self.holding = false }
            self.shown = time
        }
        return (time, version, frame)
    }
}

final class PreviewNSView: NSView, CAMetalDisplayLinkDelegate {
    var quality = 1.0 {
        didSet { if quality != oldValue { updateDrawableSize() } }
    }

    let driver: PreviewDriver
    private let metalLayer = CAMetalLayer()
    private let commandQueue: MTLCommandQueue?
    private let context: CIContext
    private let renderer: FrameRenderer
    private var link: CAMetalDisplayLink?
    private var renderThread: Thread?

    private var lastDrawn: DrawKey?
    private var lastStep: CFTimeInterval?
    private var spring = StyleSpring()
    private var source: PreviewSourceFrame?
    private var sourceCount = 0
    private let shotLock = NSLock()
    private var shot: (image: CIImage, size: CGSize)?
    private var drewOnce = false
    private(set) var hasDrawn = false
    private var drawnWaiters: [() -> Void] = []

    /// The editor's preview in the main window, for the screen hero to fly from and land on.
    static weak var current: PreviewNSView?

    var windowRect: CGRect { convert(bounds, to: nil) }

    private struct DrawKey: Equatable {
        var time: Double
        var version: Int
        var frames: Int
        var size: CGSize
    }

    init(driver: PreviewDriver) {
        self.driver = driver
        let device = MTLCreateSystemDefaultDevice()
        let queue = device?.makeCommandQueue()
        commandQueue = queue
        // Cached intermediates let the parts that don't change between frames (background, shadow, masks) be reused,
        // which takes a frame from ~10 ms to ~2 ms of GPU time at Retina size.
        context = queue.map { CIContext(mtlCommandQueue: $0, options: [.cacheIntermediates: true]) } ?? CIContext()
        renderer = FrameRenderer(context: context)
        super.init(frame: .zero)
        DispatchQueue.global(qos: .utility).async { [renderer] in renderer.warmUpTransitions() }
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.framebufferOnly = false
        metalLayer.maximumDrawableCount = 3
        metalLayer.isOpaque = true
        metalLayer.backgroundColor = NSColor.black.cgColor
        layer = metalLayer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit { link?.invalidate() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Invalidating the link removes the render thread's only run loop source, which ends the thread.
        link?.invalidate()
        link = nil
        renderThread = nil
        guard window != nil else {
            if Self.current === self { Self.current = nil }
            return
        }
        Self.current = self
        updateDrawableSize()
        let l = CAMetalDisplayLink(metalLayer: metalLayer)
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        l.preferredFrameLatency = 1
        l.delegate = self
        link = l
        let thread = Thread {
            l.add(to: .current, forMode: .default)
            while !Thread.current.isCancelled, RunLoop.current.run(mode: .default, before: .distantFuture) {}
        }
        thread.name = "Preview render"
        thread.qualityOfService = .userInteractive
        thread.start()
        renderThread = thread
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    /// The last frame shown, at most `width` pixels wide.
    func snapshot(width: CGFloat = 1600) -> CGImage? {
        guard let (image, size) = shotLock.withLock({ shot }), size.width > 0 else { return nil }
        let k = min(1, width / size.width)
        let out = CGRect(x: 0, y: 0, width: (size.width * k).rounded(), height: (size.height * k).rounded())
        return context.createCGImage(image.cropped(to: CGRect(origin: .zero, size: size))
            .transformed(by: CGAffineTransform(scaleX: k, y: k)), from: out,
                                     format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    /// Runs `body` once the preview has put its first picture on screen.
    func whenDrawn(_ body: @escaping () -> Void) {
        if hasDrawn { body() } else { drawnWaiters.append(body) }
    }

    private func markDrawn() {
        hasDrawn = true
        let waiters = drawnWaiters
        drawnWaiters = []
        waiters.forEach { $0() }
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        let pixels = scale * CGFloat(min(max(quality, 0.25), 1))
        var w = bounds.width * pixels, h = bounds.height * pixels
        let cap = 3840 / max(w, h, 1)
        if cap < 1 { w *= cap; h *= cap }
        let size = CGSize(width: max(w.rounded(), 2), height: max(h.rounded(), 2))
        if metalLayer.drawableSize != size { metalLayer.drawableSize = size }
    }

    // MARK: - Render thread

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        let host = update.targetPresentationTimestamp
        let moment = driver.moment(atHostTime: host)
        if let frame = moment.frame {
            source = frame
            sourceCount &+= 1
        }
        let dt = lastStep.map { min(max(host - $0, 0), 1.0 / 20) } ?? 1.0 / 60
        lastStep = host
        let inputs = driver.renderState.current()
        let (style, moving) = spring.step(toward: inputs.project.style, dt: dt)
        let drawable = update.drawable
        let size = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        let key = DrawKey(time: moment.time, version: moment.version, frames: sourceCount, size: size)
        guard moving || key != lastDrawn else { return }
        guard source != nil || inputs.project.clips.isEmpty else { return }
        lastDrawn = key

        let scene: RenderScene
        let options: FrameRenderer.Options
        if moving {
            var project = inputs.project
            project.style = style
            scene = RenderScene(project: project, output: size, cursor: inputs.cursor)
            options = inputs.options
        } else {
            (scene, options) = driver.renderState.snapshot(size: size)
        }
        autoreleasepool {
            let other = driver.renderState.transitionSources(at: source?.time ?? moment.time)
            let image = renderer.render(scene: scene, time: moment.time, screen: source?.screen, camera: source?.camera,
                                        other: other, options: options)
            guard let commands = commandQueue?.makeCommandBuffer() else { return }
            let destination = CIRenderDestination(mtlTexture: drawable.texture, commandBuffer: commands)
            // Metal textures are top-down; Core Image is bottom-up.
            destination.isFlipped = true
            destination.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            _ = try? context.startTask(toRender: image, to: destination)
            commands.present(drawable)
            commands.commit()
            shotLock.withLock { shot = (image, size) }
            if !drewOnce {
                drewOnce = true
                DispatchQueue.main.async { [weak self] in self?.markDrawn() }
            }
        }
    }
}

struct StyleSpring {
    private var value: [Double] = []
    private var velocity: [Double] = []
    private let omega = 2 * Double.pi / 0.32

    private static func values(_ s: FrameStyle) -> [Double] {
        [s.padding, s.screenCornerRadius, s.shadow, s.cameraCornerRadius]
    }

    mutating func step(toward target: FrameStyle, dt: Double) -> (FrameStyle, Bool) {
        let goal = Self.values(target)
        guard value.count == goal.count else {
            value = goal
            velocity = goal.map { _ in 0 }
            return (target, false)
        }
        let n = max(Int((dt * 480).rounded(.up)), 1), h = dt / Double(n)
        var moving = false
        for i in value.indices {
            for _ in 0 ..< n {
                velocity[i] += (-omega * omega * (value[i] - goal[i]) - 2 * omega * velocity[i]) * h
                value[i] += velocity[i] * h
            }
            if abs(value[i] - goal[i]) < 1e-5, abs(velocity[i]) < 1e-4 {
                value[i] = goal[i]
                velocity[i] = 0
            } else {
                moving = true
            }
        }
        var style = target
        style.padding = value[0]
        style.screenCornerRadius = value[1]
        style.shadow = value[2]
        style.cameraCornerRadius = value[3]
        return (style, moving)
    }
}
