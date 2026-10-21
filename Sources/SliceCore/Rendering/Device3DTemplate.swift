//
//  Device3DTemplate.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/15/26.
//

import AppKit
import SceneKit
import simd

/// A model, loaded once and turned to face the camera: centred, one unit tall, display towards +z and top up, with
/// the display's texture coordinates laid flat across it so a recording maps on undistorted.
final class Device3DTemplate {
    let root: SCNNode
    let bounds: (min: SIMD3<Float>, max: SIMD3<Float>)
    /// The room the device can take up: its bounds, with all the places a laptop's lid swings through.
    let extent: (min: SIMD3<Float>, max: SIMD3<Float>)
    /// Where a laptop's lid turns, when it has one that can.
    let lidHinge: SIMD3<Float>?
    /// Radians the lid is modelled open: what the hinge turns from.
    let lidOpening: Float
    let displaySize: CGSize
    let hasDisplayMesh: Bool
    /// Body colours (linear light: the diffuse and the glow) by material name, for recolouring to another finish.
    let bodyColors: [String: (diffuse: SIMD3<Float>?, emission: SIMD3<Float>?)]
    /// The brightness of the colour the body is modelled in, which a finish's tint is measured against.
    let bodyLuminance: Float
    /// For a display mesh that also carries its bezel (a laptop's lid): where the screen lies on it (fractions, top-left
    /// origin) and a mask of where it shows, around the notch and rounded corners.
    let screenRegion: CGRect?
    let screenMask: CGImage?

    /// The shape (width over height) of what a recording fills: the screen within the display.
    var screenAspect: CGFloat {
        guard displaySize.height > 0 else { return 0 }
        let r = screenRegion ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        return displaySize.width * r.width / max(displaySize.height * r.height, 1e-6)
    }

    static let displayName = "Slice display"
    /// Glass is in its own category, which the studio lights leave out.
    static let glassCategory = 2
    /// How far the display sits in front of the layers modelled flush with it (and the cover glass in front of it), so
    /// none of them fight over the same depth.
    static let displayLift: Float = 0.0004

    var size: SIMD3<Float> { bounds.max - bounds.min }

    /// How far the device reaches from its middle, whichever way it's turned.
    var radius: Float { simd_length(simd_max(simd_abs(extent.min), simd_abs(extent.max))) }

    init(url: URL, name: String, displayNode: String? = nil, bodyColor: SIMD3<Float>? = nil,
         bodyMaterials: Set<String>? = nil, laptop: Bool = false) throws {
        let source: SCNScene
        do {
            source = try SCNScene(url: url, options: [.checkConsistency: false])
        } catch {
            throw Device3DError.unreadable(name)
        }
        let model = SCNNode()
        for child in source.rootNode.childNodes { model.addChildNode(child) }
        let root = SCNNode()
        root.addChildNode(model)
        var meshes: [SCNNode] = []
        model.enumerateHierarchy { node, _ in if node.geometry != nil, !node.isHidden { meshes.append(node) } }
        guard !meshes.isEmpty else { throw Device3DError.unreadable(name) }

        let display = displayNode.flatMap { n in
            meshes.first { $0.name == n } ?? meshes.first { $0.geometry?.materials.contains { $0.name == n } == true }
        } ?? Self.findDisplay(meshes, in: model)
        // Some models come with a stage around the phone (a floor, a backdrop): anything reaching well beyond the
        // display's footprint isn't part of the phone. (A laptop's base reaches out in front of its screen.)
        if let display, !laptop {
            let d = Self.box([display], in: model)
            let reach = (d.max - d.min).max() * 0.18
            let region = (min: d.min - SIMD3(repeating: reach), max: d.max + SIMD3(repeating: reach))
            for mesh in meshes {
                let b = Self.box([mesh], in: model)
                if b.min.x < region.min.x || b.min.y < region.min.y || b.min.z < region.min.z
                    || b.max.x > region.max.x || b.max.y > region.max.y || b.max.z > region.max.z { mesh.isHidden = true }
            }
            meshes.removeAll { $0.isHidden }
        }

        let whole = Self.box(meshes, in: model)
        let centre = (whole.min + whole.max) / 2
        var facing = SIMD3<Float>(0, 0, 1), up = SIMD3<Float>(0, 1, 0)
        let lens = meshes.first { Self.name(of: $0).contains("lens") || Self.name(of: $0).contains("camera") }
        let lensCentre = lens.map { l -> SIMD3<Float> in let b = Self.box([l], in: model); return (b.min + b.max) / 2 }
        if let display, let points = Self.points(of: display, in: model), points.count >= 3 {
            // The display's own plane says which way the phone faces and stands, whichever way it's turned in its
            // file: its longest spread is up, its thinnest is out of the screen.
            let axes = Self.principalAxes(points)
            let mean = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
            let long = Self.longSide(of: points, across: axes[0], axes[1])
            if laptop {
                // A laptop's screen faces over its keyboard, and stands across its short side, above the base.
                facing = simd_dot(centre - mean, axes[2]) >= 0 ? axes[2] : -axes[2]
                up = simd_normalize(simd_cross(facing, long))
                if simd_dot(mean - centre, up) < 0 { up = -up }
            } else {
                facing = simd_dot(mean - centre, axes[2]) >= 0 ? axes[2] : -axes[2]
                up = long
                // The cameras are at the top; without them to go by, models stand the way their file has them.
                if let lensCentre { if simd_dot(lensCentre - centre, up) < 0 { up = -up } } else if up.y < 0 { up = -up }
            }
        } else {
            let reference = display.map { Self.box([$0], in: model) } ?? whole
            let wholeSize = whole.max - whole.min, referenceSize = reference.max - reference.min
            let normalAxis = (0 ..< 3).min { referenceSize[$0] < referenceSize[$1] }!
            let heightAxis = (0 ..< 3).filter { $0 != normalAxis }.max { wholeSize[$0] < wholeSize[$1] }!
            facing = .zero
            facing[normalAxis] = display == nil || (reference.min[normalAxis] + reference.max[normalAxis]) / 2 >= centre[normalAxis] ? 1 : -1
            up = .zero
            up[heightAxis] = 1
            if let lensCentre, lensCentre[heightAxis] < centre[heightAxis] { up = -up }
        }
        let right = simd_normalize(simd_cross(up, facing))
        up = simd_normalize(simd_cross(facing, right))
        let rotation = simd_float4x4(rows: [SIMD4(right, 0), SIMD4(up, 0), SIMD4(facing, 0), SIMD4(0, 0, 0, 1)])
        // Measured from the vertices once turned, so a model turned in its file isn't sized by a slanted box.
        model.simdTransform = rotation
        let turned = Self.bounds(of: meshes, in: root)
        let height = max(turned.max.y - turned.min.y, 1e-6)
        let middle = (turned.min + turned.max) / 2
        let move = simd_float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(-middle, 1)))
        model.simdTransform = simd_float4x4(diagonal: SIMD4(1 / height, 1 / height, 1 / height, 1)) * move * rotation

        var bounds = Self.bounds(of: meshes, in: root)
        var displaySize = CGSize(width: 0.9 * CGFloat(bounds.max.x - bounds.min.x), height: 0.94 * CGFloat(bounds.max.y - bounds.min.y))
        var mapped = false
        // Read before the display's texture coordinates are laid flat, as it goes by the model's own.
        let screen = laptop ? display.flatMap { Self.screenRegion(of: $0, in: root) } : nil
        if let display, let size = Self.mapDisplay(display, in: root) {
            displaySize = size
            mapped = true
        } else {
            // No display surface in the model (or one Slice can't read): a rounded screen laid on its front.
            let w = Float(displaySize.width), h = Float(displaySize.height)
            let node = SCNNode(geometry: Self.roundedRect(width: w, height: h, radius: w * 0.13))
            node.simdPosition = SIMD3(0, 0, bounds.max.z + 0.0005)
            node.name = Self.displayName
            root.addChildNode(node)
            if let display { display.isHidden = true }
        }
        // A laptop stands on its base, its lid as far open as it's modelled. Turned by its display alone, a lid modelled
        // leaning back stood upright and tipped the base towards the camera. (Its screen is laid out above while upright.)
        var lidOpening = Self.modelledLid
        if laptop, let display, let tilt = Self.baseTilt(meshes, display: display, in: root), abs(tilt) > 0.02 {
            model.simdTransform = simd_float4x4(simd_quatf(angle: tilt, axis: SIMD3(1, 0, 0))) * model.simdTransform
            let level = Self.bounds(of: meshes, in: root)
            let k = 1 / max(level.max.y - level.min.y, 1e-6), mid = (level.min + level.max) / 2
            let centre = simd_float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(-mid, 1)))
            model.simdTransform = simd_float4x4(diagonal: SIMD4(k, k, k, 1)) * centre * model.simdTransform
            bounds = Self.bounds(of: meshes, in: root)
            displaySize = CGSize(width: displaySize.width * CGFloat(k), height: displaySize.height * CGFloat(k))
            lidOpening -= tilt
        }

        let body = bodyColor ?? SIMD3(0.815, 0.195, 0.060)
        var bodyColors: [String: (diffuse: SIMD3<Float>?, emission: SIMD3<Float>?)] = [:]
        for mesh in meshes where mesh.name != Self.displayName {
            var glass = false
            // Only glass on the face of the phone is lifted with the display.
            let onFront = Self.bounds(of: [mesh], in: root).max.z >= bounds.max.z - (bounds.max.z - bounds.min.z) * 0.25
            for material in mesh.geometry?.materials ?? [] {
                // Some models have faces wound inside out (a back cover that vanishes seen from behind).
                material.isDoubleSided = true
                let name = (material.name ?? "").lowercased()
                if name.contains("black") || (Self.linear(material.diffuse.contents).map { $0.max() < 0.02 } ?? false) {
                    // The Dynamic Island and bezel: deep black with a faint gloss. Lit physically, SceneKit lays the
                    // studio's reflections over black as a grey sheen (or a mirror, on a metallic model).
                    material.lightingModel = .blinn
                    material.diffuse.contents = NSColor.black
                    material.specular.contents = NSColor(white: 0.16, alpha: 1)
                    material.shininess = 0.5
                    material.emission.contents = NSColor.black
                }
                // See-through glass says so: an opacity below one, or (on the face) a picture of where it's clear.
                let opacity = (material.transparent.contents as? NSNumber)?.doubleValue ?? 1
                let pictured = material.transparent.contents is NSImage || material.transparent.contents is URL
                let seeThrough = opacity < 0.999 || (onFront && pictured)
                if name.contains("glass"), !name.contains("lens"), !name.contains("back"), seeThrough {
                    // Clear glass (over the display, the cameras). SceneKit reads its USD opacity as a light grey veil,
                    // so it's drawn as what glass adds: reflections, never dimming what's under it. Solid "glass" (a
                    // frosted back, a tinted layer behind the display) is part of the phone, and stays as it is.
                    material.lightingModel = .physicallyBased
                    material.diffuse.contents = NSColor.black
                    material.transparent.contents = nil
                    material.metalness.contents = 0
                    material.roughness.contents = 0.06
                    material.blendMode = .add
                    material.writesToDepthBuffer = false
                    glass = true
                } else if let opacity = (material.transparent.contents as? NSNumber)?.doubleValue, opacity < 0.999 {
                    // A USD opacity arrives as a plain number, which SceneKit draws fully opaque (lens covers become
                    // grey discs): made the see-through amount it means.
                    material.transparent.contents = nil
                    material.transparency = CGFloat(max(opacity, 0.02))
                    material.writesToDepthBuffer = false
                }
                guard let key = material.name else { continue }
                let glow = Self.linear(material.emission.contents).flatMap { $0.max() > 0.001 ? $0 : nil }
                if let named = bodyMaterials {
                    // Named body parts: coloured ones are recoloured, pictured ones (a texture) tinted.
                    if named.contains(key) { bodyColors[key] = (Self.linear(material.diffuse.contents), glow) }
                } else if let c = Self.linear(material.diffuse.contents), Self.isBody(c, like: body) {
                    bodyColors[key] = (c, glow)
                }
            }
            if glass {
                // Glass reflects the room, not the studio lights: a light's sharp highlight on it washed out the
                // recording beneath as a white blob.
                mesh.categoryBitMask = Self.glassCategory
                if onFront, let parent = mesh.parent {
                    mesh.simdPosition += parent.simdConvertVector(SIMD3(0, 0, 2 * Self.displayLift), from: root)
                }
            }
        }

        let lid = laptop ? Self.rigLid(meshes, opening: lidOpening, in: root) : nil
        self.root = root
        self.bounds = bounds
        extent = lid.map { (simd_min(bounds.min, $0.swept.min), simd_max(bounds.max, $0.swept.max)) } ?? bounds
        lidHinge = lid?.hinge
        self.lidOpening = lidOpening
        self.displaySize = displaySize
        hasDisplayMesh = mapped
        screenRegion = screen?.rect
        screenMask = screen?.mask
        self.bodyColors = bodyColors
        bodyLuminance = max((body * SIMD3(0.2126, 0.7152, 0.0722)).sum(), 0.01)
    }

    static func name(of node: SCNNode) -> String {
        ((node.name ?? "") + " " + (node.geometry?.materials.compactMap(\.name).joined(separator: " ") ?? "")).lowercased()
    }

    static func findDisplay(_ meshes: [SCNNode], in space: SCNNode) -> SCNNode? {
        func face(_ n: SCNNode) -> Float {
            let b = box([n], in: space), e = b.max - b.min
            return e.x * e.y * e.z / max(e.min(), 1e-6)
        }
        let named = meshes.filter { n in
            let name = name(of: n)
            return (name.contains("screen") || name.contains("display")) && !name.contains("glass")
        }
        func flat(_ n: SCNNode) -> Bool {
            let b = box([n], in: space), e = b.max - b.min
            return e.min() < e.max() * 0.02
        }
        if let best = named.max(by: { (flat($0) ? 1 : 0, face($0)) < (flat($1) ? 1 : 0, face($1)) }) { return best }
        // Names that say nothing: the display is a flat sheet covering most of the phone's face, showing a picture
        // (the model's wallpaper).
        let whole = box(meshes, in: space), e = whole.max - whole.min
        let front = e.x * e.y * e.z / max(e.min(), 1e-6)
        return meshes.filter { n in
            let b = box([n], in: space), d = b.max - b.min
            let pictured = n.geometry?.materials.contains { $0.emission.contents is NSImage || $0.emission.contents is URL
                || $0.diffuse.contents is NSImage || $0.diffuse.contents is URL } ?? false
            return pictured && d.min() < e.max() * 0.01 && face(n) > front * 0.5
        }.max { face($0) < face($1) }
    }

    static let linearSpace = NSColorSpace(cgColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)!

    static func linear(_ contents: Any?) -> SIMD3<Float>? {
        guard let color = contents as? NSColor, let c = color.usingColorSpace(linearSpace) else { return nil }
        return SIMD3(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent))
    }

    /// The coloured body parts: colours of about the hue the body is modelled in, and not grey.
    static func isBody(_ c: SIMD3<Float>, like body: SIMD3<Float>) -> Bool {
        let chroma = c - SIMD3(repeating: c.sum() / 3), reference = body - SIMD3(repeating: body.sum() / 3)
        let length = simd_length(chroma), referenceLength = simd_length(reference)
        guard c.max() > 0.01, length > c.max() * 0.08, referenceLength > 1e-4 else { return false }
        return simd_dot(chroma, reference) / (length * referenceLength) > 0.85
    }
}
