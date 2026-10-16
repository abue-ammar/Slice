//
//  DeviceTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/3/26.
//

import CoreImage
import CoreVideo
@testable import SliceCore
import XCTest

final class DeviceTests: XCTestCase {
    static let framesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("App/DeviceFrames")
    static let catalog = DeviceFrameCatalog(directory: framesDirectory)

    var catalog: DeviceFrameCatalog { Self.catalog }

    // MARK: - Catalog

    func testCatalogFindsModelsAndColoursFromFileNames() {
        XCTAssertTrue(catalog.models.contains("17 Pro"))
        XCTAssertTrue(catalog.models.contains("Air"))
        XCTAssertEqual(catalog.colors(for: "17 Pro"), [.cosmicOrange, .deepBlue, .silver])
        let folder = URL(fileURLWithPath: "/x/14 Pro Max")
        XCTAssertNil(DeviceFrameCatalog.color(of: folder.appendingPathComponent("14 Pro Max - Gold - Shadow.png"), model: "14 Pro Max"))
        XCTAssertNil(DeviceFrameCatalog.color(of: folder.appendingPathComponent("14 Pro Max - Gold.svg"), model: "14 Pro Max"))
        XCTAssertEqual(DeviceFrameCatalog.color(of: folder.appendingPathComponent("14 Pro Max - Deep Purple.png"), model: "14 Pro Max"),
                       DeviceColor("Deep Purple"))
    }

    func testMeasuredOpeningsMatchNativeDisplays() throws {
        for model in catalog.models {
            let device = try XCTUnwrap(DeviceRegistry.known.last { $0.frameName == model }, model)
            for color in catalog.colors(for: model) {
                let d = try XCTUnwrap(try catalog.definition(model: model, color: color))
                let r = d.screenRect
                let aspect = (r.width / r.height) / (device.screenPixels.width / device.screenPixels.height)
                XCTAssertEqual(aspect, 1, accuracy: 0.005, "\(model) \(color.rawValue)")
                if model != "Air" {
                    XCTAssertEqual(r.width, device.screenPixels.width, accuracy: 4, "\(model) \(color.rawValue)")
                    XCTAssertEqual(r.height, device.screenPixels.height, accuracy: 4, "\(model) \(color.rawValue)")
                }
                XCTAssertGreaterThan(r.minX, 50)
                XCTAssertGreaterThan(r.minY, 50)
                XCTAssertGreaterThan(d.screenCornerRadius, 100)
            }
        }
    }

    func testEveryKnownModelGetsAFrameOfTheSameScreenShape() throws {
        for device in DeviceRegistry.known {
            guard device.screenPixels.width > 800 else {
                XCTAssertNil(catalog.frame(for: device), device.name)
                continue
            }
            let pick = try XCTUnwrap(catalog.frame(for: device), device.name)
            XCTAssertEqual(pick.exact, catalog.frames[device.frameName] != nil, device.name)
            let color = try XCTUnwrap(catalog.colors(for: pick.model).first)
            let d = try XCTUnwrap(try catalog.definition(model: pick.model, color: color))
            let aspect = (d.screenRect.width / d.screenRect.height) / (device.screenPixels.width / device.screenPixels.height)
            XCTAssertEqual(aspect, 1, accuracy: 0.03, "\(device.name) → \(pick.model)")
        }
        let fifteenPro = try XCTUnwrap(DeviceRegistry.model(identifier: "iPhone16,1"))
        XCTAssertEqual(catalog.frame(for: fifteenPro)?.model, "16")
    }

    // MARK: - Registry

    func testRegistryResolvesIdentifierThenScreenSize() {
        XCTAssertEqual(DeviceRegistry.resolve(identifier: "iPhone18,1", streamPixels: nil, fallbackName: "x")?.name, "iPhone 17 Pro")
        let future = DeviceRegistry.resolve(identifier: "iPhone99,9", streamPixels: CGSize(width: 2622, height: 1206), fallbackName: "x")
        XCTAssertEqual(future?.name, "iPhone 17 Pro")
        XCTAssertEqual(future?.identifier, "iPhone99,9")
        let unknown = DeviceRegistry.resolve(identifier: nil, streamPixels: CGSize(width: 1000, height: 2000), fallbackName: "Sam's iPhone")
        XCTAssertEqual(unknown?.name, "Sam's iPhone")
        XCTAssertEqual(unknown?.pointScale, 3)
        XCTAssertNil(DeviceRegistry.resolve(identifier: nil, streamPixels: nil, fallbackName: "x"))
    }

    // MARK: - Layout and pointer mapping

    func seventeenPro() throws -> (DeviceFrameDefinition, DeviceModel) {
        let d = try XCTUnwrap(try catalog.definition(model: "17 Pro", color: .silver))
        return (d, DeviceRegistry.model(identifier: "iPhone18,1")!)
    }

    func testPortraitStreamFillsTheOpening() throws {
        let (frame, _) = try seventeenPro()
        let layout = DeviceLayout(frame: frame, streamSize: CGSize(width: 1206, height: 2622))
        XCTAssertFalse(layout.landscape)
        XCTAssertEqual(layout.streamCrop, CGRect(x: 0, y: 0, width: 1, height: 1))
        let s = frame.screenRect
        let p = try XCTUnwrap(layout.streamPixel(canvas: CGPoint(x: (s.minX + 603) / frame.canvasSize.width,
                                                                 y: (s.minY + 1311) / frame.canvasSize.height)))
        XCTAssertEqual(p.x, 603, accuracy: 0.01)
        XCTAssertEqual(p.y, 1311, accuracy: 0.01)
        XCTAssertNil(layout.streamPixel(canvas: CGPoint(x: (s.minX - 20) / frame.canvasSize.width, y: s.midY / frame.canvasSize.height)))
    }

    func testLandscapeTurnsTheFrameAndMapsThroughIt() throws {
        let (frame, _) = try seventeenPro()
        let layout = DeviceLayout(frame: frame, streamSize: CGSize(width: 2622, height: 1206))
        XCTAssertTrue(layout.landscape)
        XCTAssertEqual(layout.canvas, CGSize(width: frame.canvasSize.height, height: frame.canvasSize.width))
        let s = frame.screenRect
        let opening = CGRect(x: layout.screenRect.minX * layout.canvas.width, y: layout.screenRect.minY * layout.canvas.height,
                             width: layout.screenRect.width * layout.canvas.width, height: layout.screenRect.height * layout.canvas.height)
        XCTAssertEqual(opening.minX, s.minY, accuracy: 0.01)
        XCTAssertEqual(opening.minY, frame.canvasSize.width - s.maxX, accuracy: 0.01)
        XCTAssertEqual(opening.size.width, 2622, accuracy: 0.01)
        let p = try XCTUnwrap(layout.streamPixel(canvas: CGPoint(x: (opening.minX + 30) / layout.canvas.width,
                                                                 y: (opening.minY + 60) / layout.canvas.height)))
        XCTAssertEqual(p.x, 30, accuracy: 0.01)
        XCTAssertEqual(p.y, 60, accuracy: 0.01)
        XCTAssertEqual(layout.frameImagePoint(canvas: CGPoint(x: 0, y: 0)), CGPoint(x: 1, y: 0))
    }

    func testMismatchedStreamIsAspectFilled() throws {
        let (frame, _) = try seventeenPro()
        let opening = frame.screenRect
        let layout = DeviceLayout(frame: frame, streamSize: CGSize(width: opening.width * 2, height: opening.height))
        XCTAssertFalse(layout.landscape)
        XCTAssertEqual(layout.streamCrop.minX, 0.25, accuracy: 0.001)
        XCTAssertEqual(layout.streamCrop.width, 0.5, accuracy: 0.001)
    }

    // MARK: - Compositing

    func testCompositesLiveScreenUnderFrameAtNativeResolution() throws {
        guard let compositor = DeviceCompositor() else { throw XCTSkip("No Metal device") }
        let (frame, _) = try seventeenPro()
        let textures = try compositor.textures(for: frame)
        let screen = try solidBuffer(width: 1206, height: 2622, bgra: (40, 200, 30, 255))
        let layout = DeviceLayout(frame: frame, streamSize: CGSize(width: 1206, height: 2622))
        let renderer = try XCTUnwrap(DeviceSurfaceRenderer(compositor: compositor, size: layout.canvas))
        XCTAssertEqual(renderer.size, frame.canvasSize)
        let out = try XCTUnwrap(renderer.renderNow(screen: screen, frame: textures, layout: layout))
        let s = frame.screenRect
        XCTAssertEqual(pixel(out, Int(s.midX), Int(s.midY)), [40, 200, 30, 255])
        XCTAssertEqual(pixel(out, Int(s.minX) + 2, Int(s.midY)), [40, 200, 30, 255])
        XCTAssertEqual(pixel(out, 3, 3), [0, 0, 0, 0])
        let bezel = pixel(out, Int(s.minX) - 20, Int(s.midY))
        XCTAssertEqual(bezel[3], 255)
        XCTAssertNotEqual(bezel, [40, 200, 30, 255])
        let corner = pixel(out, Int(s.minX) + 4, Int(s.minY) + 4)
        XCTAssertNotEqual(corner, [40, 200, 30, 255])
        XCTAssertEqual(CVBufferCopyAttachment(out, kCVImageBufferAlphaChannelModeKey, nil) as? String,
                       kCVImageBufferAlphaChannelMode_PremultipliedAlpha as String)
    }

    func testFramelessShowsTheWholeScreen() throws {
        guard let compositor = DeviceCompositor() else { throw XCTSkip("No Metal device") }
        let se = try XCTUnwrap(DeviceRegistry.model(identifier: "iPhone14,6"))
        let frame = DeviceFrameDefinition.frameless(for: se)
        let layout = DeviceLayout(frame: frame, streamSize: CGSize(width: 750, height: 1334))
        let renderer = try XCTUnwrap(DeviceSurfaceRenderer(compositor: compositor, size: layout.canvas))
        let screen = try solidBuffer(width: 750, height: 1334, bgra: (10, 20, 230, 255))
        let out = try XCTUnwrap(renderer.renderNow(screen: screen, frame: try compositor.textures(for: frame), layout: layout))
        XCTAssertEqual(pixel(out, 0, 0), [10, 20, 230, 255])
        XCTAssertEqual(pixel(out, 749, 1333), [10, 20, 230, 255])
    }

    func testAnalysingAFrameIsQuick() throws {
        let url = try XCTUnwrap(catalog.frames["17 Pro Max"]?[.silver])
        let start = Date()
        _ = try DeviceFrameImage.load(url)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5)
    }

    func testNoScreenYetShowsADarkDisplayNotTransparency() throws {
        guard let compositor = DeviceCompositor() else { throw XCTSkip("No Metal device") }
        let (frame, _) = try seventeenPro()
        let layout = DeviceLayout(frame: frame, streamSize: nil)
        let renderer = try XCTUnwrap(DeviceSurfaceRenderer(compositor: compositor, size: layout.canvas))
        let out = try XCTUnwrap(renderer.renderNow(screen: nil, frame: try compositor.textures(for: frame), layout: layout))
        XCTAssertEqual(pixel(out, Int(frame.screenRect.midX), Int(frame.screenRect.midY)), [0, 0, 0, 255])
    }

    // MARK: - Morph

    func testMorphStartsAndEndsOnThePlainPicture() throws {
        guard let compositor = DeviceCompositor(), let morph = DeviceMorph(compositor: compositor) else {
            throw XCTSkip("No Metal device")
        }
        let stream = CGSize(width: 1206, height: 2622)
        let screen = try solidBuffer(width: 1206, height: 2622, bgra: (40, 200, 30, 255))
        func look(_ model: String, _ color: DeviceColor) throws -> DeviceLook {
            let d = try XCTUnwrap(try catalog.definition(model: model, color: color))
            return DeviceLook(frame: try compositor.textures(for: d), layout: DeviceLayout(frame: d, streamSize: stream))
        }
        let from = try look("17 Pro", .silver), to = try look("Air", DeviceColor("Sky Blue"))
        let size = CGSize(width: 704, height: 1412)
        func render(_ progress: CGFloat?, _ plain: DeviceLook? = nil) throws -> CVPixelBuffer {
            let out = try solidBuffer(width: Int(size.width), height: Int(size.height), bgra: (0, 0, 0, 0))
            let (target, cv) = try XCTUnwrap(compositor.texture(for: out))
            let (source, sourceCV) = try XCTUnwrap(compositor.texture(for: screen))
            let commands = try XCTUnwrap(compositor.commandQueue.makeCommandBuffer())
            if let plain {
                compositor.encode(into: commands, target: target, rect: plain.layout.fitted(in: size), frame: plain.frame,
                                  layout: plain.layout, screen: source)
            } else {
                morph.encode(into: commands, target: target, from: from, to: to, screen: source, progress: progress ?? 0)
            }
            commands.commit()
            commands.waitUntilCompleted()
            withExtendedLifetime((cv, sourceCV)) {}
            return out
        }
        let plainFrom = try render(nil, from), plainTo = try render(nil, to)
        let start = try render(0), end = try render(1), middle = try render(0.5)
        let points = stride(from: 4, to: Int(size.height), by: 37).flatMap { y in
            stride(from: 4, to: Int(size.width), by: 23).map { (x: $0, y: y) }
        }
        func differences(_ a: CVPixelBuffer, _ b: CVPixelBuffer) -> Int {
            points.filter { p in zip(pixel(a, p.x, p.y), pixel(b, p.x, p.y)).contains { abs(Int($0) - Int($1)) > 2 } }.count
        }
        XCTAssertEqual(differences(start, plainFrom), 0)
        XCTAssertEqual(differences(end, plainTo), 0)
        XCTAssertGreaterThan(differences(middle, plainFrom), 0)
        XCTAssertGreaterThan(differences(middle, plainTo), 0)
        let soft = points.filter { p in (20 ... 235).contains(pixel(middle, p.x, p.y)[3]) }.count
        XCTAssertLessThan(Double(soft), Double(points.count) * 0.02)

        // Frames to look at: MORPH_FRAMES=<folder> swift test --filter testMorph
        if let folder = ProcessInfo.processInfo.environment["MORPH_FRAMES"] {
            for (i, p) in [0, 0.15, 0.3, 0.45, 0.5, 0.6, 0.75, 0.9, 1].enumerated() {
                let image = CIImage(cvPixelBuffer: try render(CGFloat(p)))
                try CIContext().writePNGRepresentation(of: image, to: URL(fileURLWithPath: "\(folder)/morph-\(i).png"),
                                                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            }
        }
    }

    func solidBuffer(width: Int, height: Int, bgra: (UInt8, UInt8, UInt8, UInt8)) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [
            kCVPixelBufferIOSurfacePropertiesKey: [String: Any](), kCVPixelBufferMetalCompatibilityKey: true,
        ] as CFDictionary, &buffer)
        let b = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(b, [])
        let base = CVPixelBufferGetBaseAddress(b)!.assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRow(b)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let p = base + y * row + x * 4
                (p[0], p[1], p[2], p[3]) = bgra
            }
        }
        CVPixelBufferUnlockBaseAddress(b, [])
        return b
    }

    func pixel(_ b: CVPixelBuffer, _ x: Int, _ y: Int) -> [UInt8] {
        CVPixelBufferLockBaseAddress(b, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(b, .readOnly) }
        let p = CVPixelBufferGetBaseAddress(b)!.assumingMemoryBound(to: UInt8.self) + y * CVPixelBufferGetBytesPerRow(b) + x * 4
        return [p[0], p[1], p[2], p[3]]
    }

    // MARK: - Editing device takes

    func testDeviceTakeIsShapedByItsOwnOutline() throws {
        var project = Project(name: "Phone")
        project.style.padding = 0.08
        var clip = Clip(screenFile: "s.mov", duration: 5, screenPixelSize: CGSize(width: 400, height: 800), captureRect: .zero)
        clip.device = RecordedDevice(name: "iPhone 17 Pro", identifier: "iPhone18,1", frame: "17 Pro", color: "Silver")
        project.clips = [clip]
        let out = CGSize(width: 1080, height: 1920)
        let scene = RenderScene(project: project, output: out, cursor: CursorTrack(project: project, logs: [:]))
        let canvas = CGRect(x: 0, y: 0, width: 400, height: 800)
        let screen = CIImage(color: .red).cropped(to: canvas.insetBy(dx: 60, dy: 60))
            .composited(over: CIImage(color: .clear).cropped(to: canvas))
        let renderer = FrameRenderer()
        let framed = renderer.render(scene: scene, time: 1, screen: screen, camera: nil)
        let empty = renderer.render(scene: scene, time: 1, screen: nil, camera: nil)
        let content = scene.geometry(at: 1).contentRect
        func px(_ image: CIImage, _ x: CGFloat, _ y: CGFloat) throws -> [UInt8] {
            var p = [UInt8](repeating: 0, count: 4)
            renderer.context.render(image, toBitmap: &p, rowBytes: 4, bounds: CGRect(x: x, y: out.height - y - 1, width: 1, height: 1),
                                    format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return p
        }
        let corner = try px(framed, content.minX + 3, content.minY + 3)
        let background = try px(empty, content.minX + 3, content.minY + 3)
        for i in 0 ..< 3 { XCTAssertEqual(Int(corner[i]), Int(background[i]), accuracy: 6) }
        XCTAssertEqual(try px(framed, content.midX, content.midY), [255, 0, 0, 255])
    }

    // MARK: - Transport

    func testUsbmuxFramingAndEvents() throws {
        let data = try Usbmux.frame(["MessageType": "Listen"], tag: 7)
        let header = data.prefix(16).withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }.map { UInt32(littleEndian: $0) }
        XCTAssertEqual(header, [UInt32(data.count), 1, 8, 7])
        let body = try XCTUnwrap(PropertyListSerialization.propertyList(from: data.dropFirst(16), format: nil) as? [String: Any])
        XCTAssertEqual(body["MessageType"] as? String, "Listen")
        XCTAssertEqual(Usbmux.wirePort(62078), 32498)

        let attached = Usbmux.event(from: ["MessageType": "Attached", "DeviceID": 4,
                                           "Properties": ["SerialNumber": "00008140-001A", "ConnectionType": "USB"]])
        XCTAssertEqual(attached, .attached(.init(id: 4, serial: "00008140-001A", isUSB: true)))
        XCTAssertEqual(Usbmux.event(from: ["MessageType": "Detached", "DeviceID": 4]), .detached(id: 4))
        XCTAssertEqual(Usbmux.event(from: ["MessageType": "Paired", "DeviceID": 4]), .paired(id: 4))
        XCTAssertNil(Usbmux.event(from: ["MessageType": "Result", "Number": 0]))
    }

    func testListensToTheSystemUsbmuxd() throws {
        guard FileManager.default.fileExists(atPath: Usbmux.socketPath) else { throw XCTSkip("No usbmuxd") }
        let listener = try Usbmux.listen({ _ in }, onEnd: {})
        listener.cancel()
        XCTAssertFalse(Usbmux.hasPairRecord(serial: "00000000-0000000000000000"))
    }

    func testLockdownValues() {
        let info = LockdownInfo(values: ["ProductType": "iPhone18,1", "DeviceName": "Sam's iPhone", "DeviceClass": "iPhone"])
        XCTAssertEqual(info, LockdownInfo(productType: "iPhone18,1", deviceName: "Sam's iPhone", deviceClass: "iPhone"))
    }
}
