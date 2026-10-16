//
//  DeviceMorph.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/12/26.
//

import CoreGraphics
import Foundation
import Metal
import MetalPerformanceShaders

public struct DeviceLook {
    public let frame: DeviceFrameTextures
    public let layout: DeviceLayout

    public init(frame: DeviceFrameTextures, layout: DeviceLayout) {
        self.frame = frame
        self.layout = layout
    }
}

/// Draws a device changing from one look to another (another frame, colour or none) as a gooey morph rather than a
/// cut, after react-native-morph-view: both looks are drawn live, crossfaded, blurred together with a blur that peaks
/// halfway, and passed through a soft alpha threshold, so the outlines melt into each other and settle crisp.
/// One per renderer; keeps its working textures while the target size is unchanged.
public final class DeviceMorph {
    public static let duration: TimeInterval = 0.6
    static let peakBlur: CGFloat = 0.05

    private let compositor: DeviceCompositor
    private let combine: MTLComputePipelineState
    private let threshold: MTLRenderPipelineState
    private var textures: (from: MTLTexture, to: MTLTexture, mixed: MTLTexture, blurred: MTLTexture)?

    public init?(compositor: DeviceCompositor) {
        let library = compositor.library
        guard let kernel = library.makeFunction(name: "deviceMorphCombine"),
              let combine = try? compositor.device.makeComputePipelineState(function: kernel) else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "deviceMorphVertex")
        desc.fragmentFunction = library.makeFunction(name: "deviceMorphThreshold")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let threshold = try? compositor.device.makeRenderPipelineState(descriptor: desc) else { return nil }
        self.compositor = compositor
        self.combine = combine
        self.threshold = threshold
    }

    public static func eased(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }

    public func encode(into commands: MTLCommandBuffer, target: MTLTexture, from: DeviceLook, to: DeviceLook,
                       screen: MTLTexture?, progress: CGFloat) {
        guard let t = workingTextures(width: target.width, height: target.height) else { return }
        let size = CGSize(width: target.width, height: target.height)
        compositor.encode(into: commands, target: t.from, rect: from.layout.fitted(in: size), frame: from.frame,
                          layout: from.layout, screen: screen)
        let toRect = to.layout.fitted(in: size)
        compositor.encode(into: commands, target: t.to, rect: toRect, frame: to.frame, layout: to.layout, screen: screen)

        guard let compute = commands.makeComputeCommandEncoder() else { return }
        var p = Float(progress)
        compute.setComputePipelineState(combine)
        compute.setTexture(t.from, index: 0)
        compute.setTexture(t.to, index: 1)
        compute.setTexture(t.mixed, index: 2)
        compute.setBytes(&p, length: MemoryLayout<Float>.size, index: 0)
        let group = MTLSize(width: 16, height: 16, depth: 1)
        compute.dispatchThreads(MTLSize(width: target.width, height: target.height, depth: 1), threadsPerThreadgroup: group)
        compute.endEncoding()

        let swell = 1 - abs(progress * 2 - 1)
        let sigma = Float(swell * Self.peakBlur * toRect.width)
        var source = t.mixed
        if sigma > 0.5 {
            let blur = MPSImageGaussianBlur(device: compositor.device, sigma: sigma)
            blur.edgeMode = .zero
            blur.encode(commandBuffer: commands, sourceTexture: t.mixed, destinationTexture: t.blurred)
            source = t.blurred
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        var strength = Float(min(swell * 6, 1))
        encoder.setRenderPipelineState(threshold)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentBytes(&strength, length: MemoryLayout<Float>.size, index: 0)
        encoder.setFragmentSamplerState(compositor.sampler, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    private func workingTextures(width: Int, height: Int) -> (from: MTLTexture, to: MTLTexture, mixed: MTLTexture, blurred: MTLTexture)? {
        if let textures, textures.from.width == width, textures.from.height == height { return textures }
        func make(_ usage: MTLTextureUsage) -> MTLTexture? {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            desc.usage = usage
            desc.storageMode = .private
            return compositor.device.makeTexture(descriptor: desc)
        }
        guard let from = make([.renderTarget, .shaderRead]), let to = make([.renderTarget, .shaderRead]),
              let mixed = make([.shaderRead, .shaderWrite]), let blurred = make([.shaderRead, .shaderWrite]) else { return nil }
        textures = (from, to, mixed, blurred)
        return textures
    }

    public func purge() { textures = nil }
}
