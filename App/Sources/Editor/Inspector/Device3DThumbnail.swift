//
//  Device3DThumbnail.swift
//  Slice
//
//  Created by rit3zh CX on 10/15/26.
//

import SliceCore
import SwiftUI

/// A still of the 3D phone, drawn once off the main thread and kept.
struct Device3DThumbnail: View {
    let model: Device3DModel
    let finish: Device3DFinish
    let placement: Device3DPlacement
    let size: CGSize
    @Environment(\.displayScale) private var scale
    @State private var image: NSImage?

    private var key: String {
        "\(model.rawValue)|\(finish.rawValue)|\(placement.yaw)|\(placement.pitch)|\(placement.rotation)|\(size.width)x\(size.height)@\(scale)"
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(.smooth(duration: 0.25), value: image)
        .task(id: key) { image = await Device3DThumbnails.shared.image(key: key, model: model, finish: finish, placement: placement,
                                                                       pixels: CGSize(width: size.width * scale, height: size.height * scale),
                                                                       points: size) }
    }
}

@MainActor
final class Device3DThumbnails {
    static let shared = Device3DThumbnails()
    private var cache: [String: NSImage] = [:]

    func image(key: String, model: Device3DModel, finish: Device3DFinish, placement: Device3DPlacement, pixels: CGSize,
               points: CGSize) async -> NSImage? {
        if let cached = cache[key] { return cached }
        let cg = await Task.detached(priority: .userInitiated) {
            Device3DRenderer.shared.thumbnail(model: model, finish: finish, placement: placement, size: pixels)
        }.value
        guard let cg else { return nil }
        let image = NSImage(cgImage: cg, size: points)
        cache[key] = image
        return image
    }
}
