//
//  DeviceConnection.swift
//  Slice
//
//  Created by rit3zh CX on 10/13/26.
//

import AVFoundation
import SliceCore
import SwiftUI

@MainActor
final class DeviceConnection: ObservableObject, Identifiable {
    let id: String
    @Published private(set) var info: ConnectedDevice
    @Published private(set) var frame: DeviceFrameDefinition?
    @Published private(set) var frameIsExact = true
    @Published private(set) var frameRate = 0
    @Published var playsSound: Bool {
        didSet {
            stream?.playsSound = playsSound
            UserDefaults.standard.set(playsSound, forKey: "device.playsSound")
        }
    }

    private(set) var muxID: Int?
    private(set) var captureDevice: AVCaptureDevice?
    private(set) var stream: DeviceStream?
    let preview = PhonePreviewSource()

    private let catalog: DeviceFrameCatalog
    private(set) var serial: String?
    private var lockdown: LockdownInfo?
    private var paired: Bool?
    private var streamSize: CGSize?
    private var firstFrameWait: Task<Void, Never>?
    private var frameLoad = 0
    private var ticker: Timer?
    private var window: DeviceWindowController?

    init(id: String, catalog: DeviceFrameCatalog) {
        self.id = id
        self.catalog = catalog
        info = ConnectedDevice(id: id, identifier: "", name: "iPhone", deviceName: nil, model: nil, state: .waitingForStream)
        playsSound = UserDefaults.standard.object(forKey: "device.playsSound") as? Bool ?? true
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    // MARK: - USB (usbmuxd)

    func attachUSB(muxID: Int, serial: String) {
        self.muxID = muxID
        self.serial = serial
        Task {
            let (paired, lockdown) = await Task.detached {
                (Usbmux.hasPairRecord(serial: serial), try? LockdownInfo.query(deviceID: muxID))
            }.value
            guard self.muxID == muxID else { return }
            log.notice("\(serial, privacy: .public): paired \(paired), \(lockdown?.productType ?? "no identity", privacy: .public), \(lockdown?.deviceName ?? "", privacy: .public)")
            self.paired = paired
            if let lockdown { self.lockdown = lockdown }
            if captureDevice == nil { setState(paired ? .waitingForStream : .waitingForTrust) }
            resolveModel()
            DeviceManager.shared.identityChanged(self)
        }
    }

    func usbDetached() {
        muxID = nil
    }

    func trusted() {
        paired = true
        if info.state == .waitingForTrust { setState(.waitingForStream) }
        if let muxID { attachUSB(muxID: muxID, serial: serial ?? id) }
    }

    // MARK: - Screen (AVFoundation)

    func attachCapture(_ device: AVCaptureDevice) {
        guard captureDevice !== device else { return }
        log.notice("\(self.info.name, privacy: .public): attaching screen device \(device.uniqueID, privacy: .public)")
        stopStream()
        captureDevice = device
        paired = true
        setState(.connecting)
        resolveModel()
        Task {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: break
            case .notDetermined:
                guard await AVCaptureDevice.requestAccess(for: .video) else { return setState(.permissionDenied) }
            default:
                log.error("Camera access denied; can't open device screens")
                return setState(.permissionDenied)
            }
            guard captureDevice === device else { return }
            startStream(device)
        }
    }

    func detachCapture() {
        log.notice("\(self.info.name, privacy: .public): screen device gone")
        stopStream()
        captureDevice = nil
        setState(paired == false ? .waitingForTrust : .waitingForStream)
    }

    static let streamDidChange = Notification.Name("DeviceStreamDidChange")

    private func startStream(_ device: AVCaptureDevice) {
        let stream = DeviceStream(device: device)
        stream.onFirstFrame = { [weak self, weak stream] in
            Task { @MainActor in
                guard let self, self.stream === stream else { return }
                log.notice("\(self.info.name, privacy: .public): first frame")
                self.firstFrame()
            }
        }
        stream.onSizeChange = { [weak self, weak stream] size in
            Task { @MainActor in
                guard let self, self.stream === stream else { return }
                self.streamResized(size)
            }
        }
        stream.onFailure = { [weak self, weak stream] reason in
            Task { @MainActor in
                guard let self, self.stream === stream else { return }
                log.error("Stream runtime error: \(reason, privacy: .public)")
                self.setState(.unavailable(reason))
            }
        }
        self.stream = stream
        let sound = playsSound
        Task {
            do {
                // startRunning blocks; keep it off the main thread.
                try await Task.detached { try stream.start(playsSound: sound) }.value
            } catch {
                guard self.stream === stream else { return }
                log.error("Stream failed to start: \(error, privacy: .public)")
                setState(.unavailable(error.localizedDescription))
                return
            }
            guard self.stream === stream else { return stream.stop() }
            preview.update(stream: stream)
            NotificationCenter.default.post(name: Self.streamDidChange, object: self)
        }
        firstFrameWait = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, self.stream === stream, info.state == .connecting else { return }
            setState(.screenAsleep)
        }
    }

    private func stopStream() {
        firstFrameWait?.cancel()
        if let stream { Task.detached { stream.stop() } }
        let had = stream != nil
        stream = nil
        streamSize = nil
        preview.update(stream: nil)
        if had { NotificationCenter.default.post(name: Self.streamDidChange, object: self) }
    }

    private func firstFrame() {
        firstFrameWait?.cancel()
        setState(.streaming)
        fitWindow()
    }

    private func streamResized(_ size: CGSize) {
        if info.state == .screenAsleep || info.state == .connecting { setState(.streaming) }
        let turned = streamSize.map { ($0.width > $0.height) != (size.width > size.height) } ?? true
        streamSize = size
        resolveModel()
        if turned { fitWindow() }
    }

    private func tick() {
        frameRate = stream?.measuredFrameRate ?? 0
    }

    // MARK: - Identity and frame

    private var deviceName: String? { lockdown?.deviceName ?? captureDevice?.localizedName }

    private func resolveModel() {
        let model = DeviceRegistry.resolve(identifier: lockdown?.productType, streamPixels: streamSize,
                                           fallbackName: deviceName ?? "iPhone")
        let changed = model != info.model
        info.model = model
        info.identifier = lockdown?.productType ?? ""
        info.deviceName = deviceName
        info.name = model?.name ?? deviceName ?? "iPhone"
        window?.updateTitle()
        if changed { chooseFrame() }
    }

    private var frameKey: String { "deviceFrame.\(id)" }

    private func chooseFrame() {
        guard let model = info.model else { return }
        let saved = UserDefaults.standard.string(forKey: frameKey)
        if saved == "none" {
            load(.frameless(for: model), exact: false)
            return
        }
        if let parts = saved?.split(separator: "|", maxSplits: 1).map(String.init), parts.count == 2,
           catalog.frames[parts[0]]?[DeviceColor(parts[1])] != nil {
            load(model: parts[0], color: DeviceColor(parts[1]), exact: parts[0] == model.frameName)
            return
        }
        guard let pick = catalog.frame(for: model) else {
            load(.frameless(for: model), exact: false)
            return
        }
        let colors = catalog.colors(for: pick.model)
        let last = UserDefaults.standard.string(forKey: "deviceFrame.color.\(pick.model)").map { DeviceColor($0) }
        guard let color = last.flatMap({ colors.contains($0) ? $0 : nil }) ?? colors.first else { return }
        load(model: pick.model, color: color, exact: pick.exact)
    }

    func useFrame(model: String?, color: DeviceColor? = nil) {
        switch (model, color) {
        case (nil, _): UserDefaults.standard.removeObject(forKey: frameKey)
        case ("", _): UserDefaults.standard.set("none", forKey: frameKey)
        case let (m?, c?):
            UserDefaults.standard.set("\(m)|\(c.rawValue)", forKey: frameKey)
            UserDefaults.standard.set(c.rawValue, forKey: "deviceFrame.color.\(m)")
        case let (m?, nil):
            let colors = catalog.colors(for: m)
            let last = UserDefaults.standard.string(forKey: "deviceFrame.color.\(m)").map { DeviceColor($0) }
            guard let c = last.flatMap({ colors.contains($0) ? $0 : nil }) ?? colors.first else { return }
            UserDefaults.standard.set("\(m)|\(c.rawValue)", forKey: frameKey)
        }
        chooseFrame()
    }

    func useColor(_ color: DeviceColor) {
        guard let frame, !frame.isFrameless else { return }
        guard frameChoiceIsAutomatic else { return useFrame(model: frame.model, color: color) }
        UserDefaults.standard.set(color.rawValue, forKey: "deviceFrame.color.\(frame.model)")
        chooseFrame()
    }

    var frameChoiceIsAutomatic: Bool { UserDefaults.standard.string(forKey: frameKey) == nil }

    private func load(model: String, color: DeviceColor, exact: Bool) {
        frameLoad += 1
        let generation = frameLoad
        let catalog = catalog
        Task {
            let definition = await Task.detached { try? catalog.definition(model: model, color: color) }.value
            guard generation == frameLoad, let definition else { return }
            load(definition, exact: exact, generation: generation)
        }
    }

    private func load(_ definition: DeviceFrameDefinition, exact: Bool, generation: Int? = nil) {
        if generation == nil { frameLoad += 1 }
        let current = generation ?? frameLoad
        Task {
            let textures = await Task.detached { try? DeviceCompositor.shared?.textures(for: definition) }.value
            guard current == frameLoad, let textures else { return }
            let morphs = frame.map { $0 != definition } ?? false
            frame = definition
            frameIsExact = exact
            preview.update(frame: textures, model: info.model)
            fitWindow(animated: morphs)
        }
    }

    var layout: DeviceLayout? { frame.map { DeviceLayout(frame: $0, streamSize: streamSize) } }

    var recordedDevice: RecordedDevice {
        RecordedDevice(name: info.name, identifier: info.identifier, frame: frame?.isFrameless == false ? frame?.model : nil,
                       color: frame?.isFrameless == false ? frame?.color.rawValue : nil, screen: layout?.screenRect,
                       cutout: layout?.cutoutRect, opensIn3D: UserDefaults.standard.bool(forKey: Self.opensIn3DKey) ? true : nil)
    }

    /// Set in the iPhone panel: takes recorded from a device open in the editor on the 3D phone.
    static let opensIn3DKey = "device.opensIn3D"

    // MARK: - Window

    func showWindow() {
        if window == nil { window = DeviceWindowController(connection: self) }
        window?.showWindow(nil)
        fitWindow()
        NotificationCenter.default.post(name: DeviceWindowController.windowsDidChange, object: self)
    }

    var isWindowVisible: Bool { window?.window?.isVisible ?? false }

    func setWindowScale(_ fraction: CGFloat) {
        showWindow()
        window?.setScale(fraction)
    }

    func setFloatsOnTop(_ floats: Bool) {
        if let window { window.floatsOnTop = floats } else { UserDefaults.standard.set(floats, forKey: "device.floatsOnTop") }
    }

    func windowMenu() -> NSMenu? { window?.makeMenu() }

    func deviceWindowRect(layout: DeviceLayout) -> CGRect? { window?.canvasRectOnScreen(layout: layout) }

    // MARK: - Pointer

    private let mirroring = IPhoneMirroring()

    func pointerMapping() -> CursorLogger.Mapping {
        { [weak self] p in MainActor.assumeIsolated { self?.canvasPoint(p) ?? CGPoint(x: -1, y: -1) } }
    }

    private func canvasPoint(_ p: NSPoint) -> CGPoint {
        guard let layout else { return CGPoint(x: -1, y: -1) }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let g = CGPoint(x: p.x, y: primaryHeight - p.y)
        let screen = layout.screenRect
        let aspect = screen.width * layout.canvas.width / max(screen.height * layout.canvas.height, 1)
        if let mirrored = mirroring.screenRect(aspect: aspect), mirrored.contains(g) {
            let u = (g.x - mirrored.minX) / mirrored.width, v = (g.y - mirrored.minY) / mirrored.height
            return CGPoint(x: screen.minX + u * screen.width, y: screen.minY + v * screen.height)
        }
        guard let canvas = window?.canvasRectOnScreen(layout: layout) else { return CGPoint(x: -1, y: -1) }
        return CGPoint(x: (g.x - canvas.minX) / canvas.width, y: (g.y - canvas.minY) / canvas.height)
    }

    private func fitWindow(animated: Bool = false) {
        guard let layout else { return }
        window?.fit(canvas: layout.canvas, animated: animated)
        let wait = animated ? DeviceMorph.duration + 0.05 : 0.15
        Task {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            window?.window?.invalidateShadow()
        }
    }

    // MARK: - Teardown

    func disconnect() {
        stopStream()
        captureDevice = nil
        muxID = nil
        ticker?.invalidate()
        ticker = nil
        setState(.unavailable("Device disconnected"))
        window?.close()
        window = nil
        NotificationCenter.default.post(name: DeviceWindowController.windowsDidChange, object: self)
        NotificationCenter.default.post(name: Self.streamDidChange, object: self)
    }

    private func setState(_ state: DeviceState) {
        guard info.state != state else { return }
        log.notice("\(self.info.name, privacy: .public): \(state.title, privacy: .public)")
        info.state = state
    }
}
