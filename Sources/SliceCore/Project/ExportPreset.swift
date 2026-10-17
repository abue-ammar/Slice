//
//  ExportPreset.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/17/26.
//

import CoreGraphics
import Foundation

/// Ready-made export settings for where a video is going. Picking one sets the fields; changing any of them after
/// makes it Custom again.
public enum ExportPreset: String, CaseIterable, Identifiable {
    case custom, youtube, x, linkedin, discord, email

    public var id: Self { self }

    public var label: String {
        switch self {
        case .custom: "Custom"
        case .youtube: "YouTube"
        case .x: "X"
        case .linkedin: "LinkedIn"
        case .discord: "Discord"
        case .email: "Email & Slack"
        }
    }

    public var detail: String {
        switch self {
        case .custom: "Your own settings"
        case .youtube: "4K · 60 fps · H.264"
        case .x: "1080p · 60 fps · under 512 MB"
        case .linkedin: "1080p · 30 fps · H.264"
        case .discord: "Under 10 MB"
        case .email: "Under 25 MB"
        }
    }

    public var symbol: String {
        switch self {
        case .custom: "slider.horizontal.3"
        case .youtube: "play.rectangle"
        case .x: "bubble.left"
        case .linkedin: "briefcase"
        case .discord: "gamecontroller"
        case .email: "envelope"
        }
    }

    public func apply(to s: inout ExportSettings) {
        guard self != .custom else { return }
        s.format = .video
        s.quality = .high
        s.hevc = false
        switch self {
        case .custom: break
        case .youtube: (s.resolution, s.fps, s.sizeLimitMB) = (.p2160, 60, nil)
        case .x: (s.resolution, s.fps, s.sizeLimitMB) = (.p1080, 60, 512)
        case .linkedin: (s.resolution, s.fps, s.sizeLimitMB) = (.p1080, 30, nil)
        case .discord: (s.resolution, s.fps, s.sizeLimitMB) = (.p1080, 30, 10)
        case .email: (s.resolution, s.fps, s.sizeLimitMB) = (.p1080, 30, 25)
        }
    }

    public static func matching(_ s: ExportSettings) -> ExportPreset {
        allCases.dropFirst().first { preset in
            var applied = s
            preset.apply(to: &applied)
            return applied == s
        } ?? .custom
    }
}

extension ExportSettings {
    /// What's left for the picture once the sound is paid for, a little under the limit for the file's own overhead.
    func videoBudget(duration: Double) -> Int? {
        guard let mb = sizeLimitMB, duration > 0 else { return nil }
        let bits = Double(mb) * 8_000_000 * 0.92 - Double(audioBitRate) * duration
        return max(Int(bits / duration), 100_000)
    }

    public var audioBitRate: Int { sizeLimitMB == nil ? 256_000 : 128_000 }

    public func bitRate(for size: CGSize, duration: Double) -> Int {
        let natural = bitRate(for: size)
        return videoBudget(duration: duration).map { min($0, natural) } ?? natural
    }

    static let fittedSides = [2160, 1440, 1080, 720, 540, 360]
}

extension Project {
    /// The chosen resolution, or under a size limit the largest one that still gets enough bits per pixel to look clean.
    var renderShortSide: Int {
        let full = export.resolution.rawValue
        guard let budget = export.videoBudget(duration: duration) else { return full }
        let floor = export.hevc ? 0.02 : 0.03
        for side in ExportSettings.fittedSides where side <= full {
            let s = outputSize(shortSide: side)
            if Double(budget) / (Double(s.width * s.height) * Double(export.fps)) >= floor { return side }
        }
        return ExportSettings.fittedSides.last!
    }

    public var exportBitRate: Int { export.bitRate(for: renderSize, duration: duration) }

    /// The limit in bytes, when there is one.
    public var exportByteLimit: Int64? { export.sizeLimitMB.map { Int64($0) * 1_000_000 } }
}
