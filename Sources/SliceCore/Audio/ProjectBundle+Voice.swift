//
//  ProjectBundle+Voice.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/3/26.
//

import Foundation

extension ProjectBundle {
    public func voiceFolder(for clip: Clip) -> String? {
        guard let mic = clip.micFile else { return nil }
        let dir = (mic as NSString).deletingLastPathComponent
        return dir.isEmpty ? "voice" : "\(dir)/voice"
    }

    public func denoisedVoiceFile(for clip: Clip) -> String? { voiceFolder(for: clip).map { "\($0)/denoised-dfn3.m4a" } }

    public func enhancedVoiceFile(for clip: Clip, settings: VoiceSettings) -> String? {
        voiceFolder(for: clip).map { "\($0)/enhanced-\(settings.cacheKey).m4a" }
    }

    public func voiceFile(for clip: Clip, settings: VoiceSettings) -> String? {
        guard settings.enhance, let file = enhancedVoiceFile(for: clip, settings: settings),
              FileManager.default.fileExists(atPath: self.file(file).path) else { return clip.micFile }
        return file
    }

    public func hasVoice(for clip: Clip, settings: VoiceSettings) -> Bool {
        guard let file = enhancedVoiceFile(for: clip, settings: settings) else { return true }
        return FileManager.default.fileExists(atPath: self.file(file).path)
    }

    public func removeOtherVoices(for clip: Clip, keeping settings: VoiceSettings) {
        guard let folder = voiceFolder(for: clip), let keep = enhancedVoiceFile(for: clip, settings: settings) else { return }
        let keepName = (keep as NSString).lastPathComponent
        for name in (try? FileManager.default.contentsOfDirectory(atPath: file(folder).path)) ?? []
            where name.hasPrefix("enhanced-") && name != keepName {
            try? FileManager.default.removeItem(at: file("\(folder)/\(name)"))
        }
    }
}
