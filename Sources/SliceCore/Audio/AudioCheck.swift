//
//  AudioCheck.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/2/26.
//

import AVFoundation
import Foundation

public enum AudioCheck {
    public static func peak(of url: URL) -> Float? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let chunk: AVAudioFrameCount = 48000
        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else { return nil }
        var peak: Float = 0
        while file.framePosition < file.length {
            guard (try? file.read(into: buf, frameCount: chunk)) != nil, buf.frameLength > 0 else { break }
            for c in 0 ..< Int(buf.format.channelCount) {
                let d = buf.floatChannelData![c]
                for i in 0 ..< Int(buf.frameLength) { peak = max(peak, abs(d[i])) }
            }
        }
        return peak
    }

    public static func isSilent(_ url: URL) -> Bool {
        guard let p = peak(of: url) else { return false }
        return p < 0.001
    }
}
