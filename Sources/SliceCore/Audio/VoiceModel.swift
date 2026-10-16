//
//  VoiceModel.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/5/26.
//

import CryptoKit
import Foundation

public struct VoiceSettings: Codable, Equatable {
    public var enhance = false
    public var noiseReduction = VoiceSettings.fullReduction
    public var polish = true
    public var eq = true
    public var compress = true
    public var normalize = true

    public static let fullReduction = 100.0

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VoiceSettings()
        enhance = try c.decodeIfPresent(Bool.self, forKey: .enhance) ?? d.enhance
        noiseReduction = try c.decodeIfPresent(Double.self, forKey: .noiseReduction) ?? d.noiseReduction
        polish = try c.decodeIfPresent(Bool.self, forKey: .polish) ?? d.polish
        eq = try c.decodeIfPresent(Bool.self, forKey: .eq) ?? d.eq
        compress = try c.decodeIfPresent(Bool.self, forKey: .compress) ?? d.compress
        normalize = try c.decodeIfPresent(Bool.self, forKey: .normalize) ?? d.normalize
    }

    /// Names the voice file these settings make, so each combination is made once and a change finds its own file.
    /// Bump the version when the processing changes, so old files aren't reused.
    public var cacheKey: String {
        let nr = noiseReduction >= Self.fullReduction - 0.5 ? "full" : "\(Int(noiseReduction.rounded()))"
        let chain = polish ? [eq ? "eq" : nil, compress ? "comp" : nil, normalize ? "norm" : nil].compactMap { $0 } : []
        return (["v1", "nr\(nr)"] + (chain.isEmpty ? ["plain"] : chain)).joined(separator: "-")
    }
}

/// The DeepFilterNet3 noise-suppression model and its runtime, downloaded on request into Application Support.
///
/// DeepFilterNet3 is three ONNX networks (encoder, ERB and deep-filter decoders) wrapped in its own STFT/ERB signal
/// processing, so it can't run as a plain Core ML model. Its official runtime, `deep-filter` (Rust, libDF on the tract
/// inference engine), does all of it on the CPU; Slice runs that as a helper process over the microphone audio.
/// Both come from the DeepFilterNet project (Hendrik Schröter, MIT or Apache-2.0), pinned to exact files and
/// checked against their SHA-256 before use. Nothing is uploaded: they run entirely on this Mac.
public enum VoiceModel {
    public struct Asset: Sendable, Equatable {
        public let name: String
        public let url: URL
        public let sha256: String
        public let bytes: Int64
        public let executable: Bool
    }

    public enum Failure: LocalizedError, Equatable {
        case corrupt(String)
        case runtime(String)
        case notInstalled

        public var errorDescription: String? {
            switch self {
            case let .corrupt(name): "\(name) didn't match the verified file, so it wasn't installed. Try again."
            case let .runtime(m): "The voice model couldn't run on this Mac: \(m)"
            case .notInstalled: "The voice enhancement model isn't installed."
            }
        }
    }

    public static let displayName = "DeepFilterNet3"
    public static let runtimeVersion = "0.5.6"
    public static let license = "MIT or Apache 2.0"
    public static let sourceURL = URL(string: "https://github.com/Rikorose/DeepFilterNet")!

    public static let model = Asset(
        name: "DeepFilterNet3_onnx.tar.gz",
        url: URL(string: "https://raw.githubusercontent.com/Rikorose/DeepFilterNet/84d57ec2c08fe08e68a13fb32a58cd7092060a0f/models/DeepFilterNet3_onnx.tar.gz")!,
        sha256: "c94d91f70911001c946e0fabb4aa9adc37045f45a03b56008cb0c8244cb63616",
        bytes: 7_983_136, executable: false)

    public static let runtime: Asset = {
        let base = "https://github.com/Rikorose/DeepFilterNet/releases/download/v\(runtimeVersion)/deep-filter-\(runtimeVersion)-"
        #if arch(arm64)
            return Asset(name: "deep-filter", url: URL(string: base + "aarch64-apple-darwin")!,
                         sha256: "4601e7f4e4c03e59a4c5b5000216ef3add3e808799cfccd95e14e83ea4611081",
                         bytes: 27_877_081, executable: true)
        #else
            return Asset(name: "deep-filter", url: URL(string: base + "x86_64-apple-darwin")!,
                         sha256: "d3be84003acb7c23e738ad7f70a158ec779a8d233a82e7fa3e717d112eb5b50f",
                         bytes: 29_933_512, executable: true)
        #endif
    }()

    public static var assets: [Asset] { [model, runtime] }
    public static var downloadBytes: Int64 { assets.reduce(0) { $0 + $1.bytes } }

    public static var directory: URL {
        if let dir = ProcessInfo.processInfo.environment["SLICE_VOICE_MODEL_DIR"] { return URL(fileURLWithPath: dir) }
        return ProjectBundle.migrated(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
                                      "Screen Recorder", to: "Slice")
            .appendingPathComponent("Voice Enhancement").appendingPathComponent(displayName)
    }

    public static var modelURL: URL { directory.appendingPathComponent(model.name) }
    public static var runtimeURL: URL { directory.appendingPathComponent(runtime.name) }
    static var manifestURL: URL { directory.appendingPathComponent("manifest.json") }

    struct Manifest: Codable {
        var model: String
        var runtimeVersion: String
        var files: [String: String]
        var installedAt: Date
    }

    public static var isInstalled: Bool {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return false }
        return assets.allSatisfy { asset in
            manifest.files[asset.name] == asset.sha256 && size(of: directory.appendingPathComponent(asset.name)) == asset.bytes
        }
    }

    public static var installedBytes: Int64 {
        assets.reduce(0) { $0 + (size(of: directory.appendingPathComponent($1.name)) ?? 0) }
    }

    public static func install(progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        let fm = FileManager.default
        let parent = directory.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".\(displayName)-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let total = downloadBytes
        var done: Int64 = 0
        for asset in assets {
            let dest = staging.appendingPathComponent(asset.name)
            let before = done
            try await ModelDownload(destination: dest) { progress(before + min($0, asset.bytes), total) }.run(asset.url)
            try Task.checkCancellation()
            guard size(of: dest) == asset.bytes, try sha256(of: dest) == asset.sha256 else { throw Failure.corrupt(asset.name) }
            if asset.executable {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
                // Downloaded by the app itself, so normally unquarantined; cleared regardless, as the hash vouches for it.
                removexattr(dest.path, "com.apple.quarantine", 0)
            }
            done += asset.bytes
            progress(done, total)
        }

        try await selfTest(runtime: staging.appendingPathComponent(runtime.name), model: staging.appendingPathComponent(model.name))
        try Task.checkCancellation()

        let manifest = Manifest(model: displayName, runtimeVersion: runtimeVersion,
                                files: Dictionary(uniqueKeysWithValues: assets.map { ($0.name, $0.sha256) }), installedAt: Date())
        try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
        if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
        try fm.moveItem(at: staging, to: directory)
    }

    public static func remove() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    static func selfTest(runtime: URL, model: URL) async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("slice-voice-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        var seed: UInt32 = 1
        let noise = (0 ..< 48000).map { _ -> Float in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return (Float(seed >> 8) / Float(1 << 24) - 0.5) * 0.1
        }
        let input = work.appendingPathComponent("test.wav")
        try WAV.write(noise, to: input)
        let out = try await DeepFilter.run(runtime: runtime, model: model, input: input, outputDirectory: work.appendingPathComponent("out"))
        guard let samples = try? WAV.readMono(out), samples.count > 40000 else {
            throw Failure.runtime("it produced no audio")
        }
    }

    static func size(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    static func sha256(of url: URL) throws -> String { try ModelDownload.hash(of: url, using: SHA256()) }
}

enum DeepFilter {
    static func run(runtime: URL, model: URL, input: URL, outputDirectory: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let log = outputDirectory.appendingPathComponent("deep-filter.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: log)
        defer { try? logHandle.close() }

        let process = Process()
        process.executableURL = runtime
        process.arguments = ["--compensate-delay", "--model", model.path, "--output-dir", outputDirectory.path, input.path]
        // Logs go to a file rather than a pipe, which would stall the process if it filled up.
        process.standardOutput = logHandle
        process.standardError = logHandle
        process.environment = ["RUST_LOG": "warn"]
        process.qualityOfService = .utility
        let box = ProcessBox(process: process)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in c.resume() }
                do { try process.run() } catch {
                    process.terminationHandler = nil
                    c.resume(throwing: VoiceModel.Failure.runtime(error.localizedDescription))
                }
            }
        } onCancel: {
            if box.process.isRunning { box.process.terminate() }
        }
        try Task.checkCancellation()
        let output = outputDirectory.appendingPathComponent(input.lastPathComponent)
        guard process.terminationReason == .exit, process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: output.path) else {
            let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            let last = text.split(separator: "\n").last.map(String.init) ?? "exit status \(process.terminationStatus)"
            throw VoiceModel.Failure.runtime(last)
        }
        return output
    }

    private struct ProcessBox: @unchecked Sendable { let process: Process }
}
