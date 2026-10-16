//
//  DeviceRegistry.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/15/26.
//

import CoreGraphics
import Foundation

public struct DeviceModel: Equatable, Hashable, Sendable {
    public let identifier: String
    public let name: String
    public let screenPixels: CGSize
    public let pointScale: CGFloat

    public init(identifier: String, name: String, screenPixels: CGSize, pointScale: CGFloat) {
        self.identifier = identifier
        self.name = name
        self.screenPixels = screenPixels
        self.pointScale = pointScale
    }

    public var frameName: String {
        name.hasPrefix("iPhone ") ? String(name.dropFirst("iPhone ".count)) : name
    }

    public var screenPoints: CGSize {
        CGSize(width: screenPixels.width / pointScale, height: screenPixels.height / pointScale)
    }

    public static func unidentified(name: String, screenPixels: CGSize) -> DeviceModel {
        let portrait = CGSize(width: min(screenPixels.width, screenPixels.height), height: max(screenPixels.width, screenPixels.height))
        return DeviceModel(identifier: "", name: name, screenPixels: portrait, pointScale: portrait.width < 800 ? 2 : 3)
    }
}

public enum DeviceRegistry {
    public static let known: [DeviceModel] = [
        m("iPhone12,8", "iPhone SE (2nd generation)", 750, 1334, 2),
        m("iPhone13,1", "iPhone 12 mini", 1080, 2340),
        m("iPhone13,2", "iPhone 12", 1170, 2532),
        m("iPhone13,3", "iPhone 12 Pro", 1170, 2532),
        m("iPhone13,4", "iPhone 12 Pro Max", 1284, 2778),
        m("iPhone14,4", "iPhone 13 mini", 1080, 2340),
        m("iPhone14,5", "iPhone 13", 1170, 2532),
        m("iPhone14,2", "iPhone 13 Pro", 1170, 2532),
        m("iPhone14,3", "iPhone 13 Pro Max", 1284, 2778),
        m("iPhone14,6", "iPhone SE (3rd generation)", 750, 1334, 2),
        m("iPhone14,7", "iPhone 14", 1170, 2532),
        m("iPhone14,8", "iPhone 14 Plus", 1284, 2778),
        m("iPhone15,2", "iPhone 14 Pro", 1179, 2556),
        m("iPhone15,3", "iPhone 14 Pro Max", 1290, 2796),
        m("iPhone15,4", "iPhone 15", 1179, 2556),
        m("iPhone15,5", "iPhone 15 Plus", 1290, 2796),
        m("iPhone16,1", "iPhone 15 Pro", 1179, 2556),
        m("iPhone16,2", "iPhone 15 Pro Max", 1290, 2796),
        m("iPhone17,3", "iPhone 16", 1179, 2556),
        m("iPhone17,4", "iPhone 16 Plus", 1290, 2796),
        m("iPhone17,1", "iPhone 16 Pro", 1206, 2622),
        m("iPhone17,2", "iPhone 16 Pro Max", 1320, 2868),
        m("iPhone17,5", "iPhone 16e", 1170, 2532),
        m("iPhone18,3", "iPhone 17", 1206, 2622),
        m("iPhone18,4", "iPhone Air", 1260, 2736),
        m("iPhone18,1", "iPhone 17 Pro", 1206, 2622),
        m("iPhone18,2", "iPhone 17 Pro Max", 1320, 2868),
    ]

    private static func m(_ id: String, _ name: String, _ w: CGFloat, _ h: CGFloat, _ scale: CGFloat = 3) -> DeviceModel {
        DeviceModel(identifier: id, name: name, screenPixels: CGSize(width: w, height: h), pointScale: scale)
    }

    private static let byIdentifier = Dictionary(known.map { ($0.identifier, $0) }, uniquingKeysWith: { a, _ in a })

    public static func model(identifier: String) -> DeviceModel? { byIdentifier[identifier] }

    public static func resolve(identifier: String?, streamPixels: CGSize?, fallbackName: String) -> DeviceModel? {
        if let identifier, let model = model(identifier: identifier) { return model }
        guard let pixels = streamPixels, pixels.width > 0, pixels.height > 0 else { return nil }
        let portrait = CGSize(width: min(pixels.width, pixels.height), height: max(pixels.width, pixels.height))
        if let match = known.last(where: { $0.screenPixels == portrait }) {
            return identifier.map { DeviceModel(identifier: $0, name: match.name, screenPixels: match.screenPixels,
                                                pointScale: match.pointScale) } ?? match
        }
        return .unidentified(name: fallbackName, screenPixels: portrait)
    }
}
