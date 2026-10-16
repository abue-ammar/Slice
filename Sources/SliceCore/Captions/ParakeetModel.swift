//
//  ParakeetModel.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/16/26.
//

import CryptoKit
import FluidAudio
import Foundation

/// Parakeet Ultra, the speech model behind "Parakeet AI", downloaded on request into Application Support.
///
/// It's moondream's post-training of NVIDIA's Parakeet TDT 0.6B v3 (25 European languages), converted to Core ML by
/// FluidInference and run by their FluidAudio package on the Neural Engine. Both the model and its base are CC BY 4.0.
/// The files are pinned to one revision of the Hugging Face repo and each is checked against the size and hash
/// published there before use. Slice fetches them itself, so the byte counts shown are the bytes received; FluidAudio
/// then only ever loads them from disk.
public enum ParakeetModel {
    public struct File: Sendable, Equatable {
        public enum Digest: Sendable, Equatable {
            case sha256(String)
            /// Small files Hugging Face stores in git rather than LFS are identified by their git blob hash.
            case gitBlob(String)
        }

        public let path: String
        public let bytes: Int64
        public let digest: Digest

        init(_ path: String, _ bytes: Int64, _ digest: Digest) {
            self.path = path
            self.bytes = bytes
            self.digest = digest
        }
    }

    public enum Progress: Equatable, Sendable {
        case downloading(received: Int64, total: Int64)
        case verifying
    }

    public enum Failure: LocalizedError, Equatable {
        case corrupt(String)
        case diskFull(needed: Int64)

        public var errorDescription: String? {
            switch self {
            case let .corrupt(name): "\(name) didn't match the published file, so it wasn't installed. Try again."
            case let .diskFull(needed):
                "There isn't enough free space. Parakeet AI needs \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)) more."
            }
        }
    }

    public static let displayName = "Parakeet Ultra 0.6B"
    public static let credit = "moondream's Parakeet Ultra, based on NVIDIA Parakeet TDT 0.6B v3, converted by FluidInference"
    public static let license = "CC BY 4.0"
    public static let repo = "FluidInference/parakeet-ultra-coreml"
    public static let revision = "95eaa59a39d4394f047a4dc5cce480388a60d1b6"
    public static let sourceURL = URL(string: "https://huggingface.co/\(repo)")!
    /// FluidAudio finds the model by its own folder name for the repo.
    static var folderName: String { Repo.parakeetUltra.folderName }

    /// The languages Parakeet Ultra was trained on, as ISO 639-1 codes.
    public static let languages: Set<String> = [
        "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it",
        "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk",
    ]

    public static let files: [File] = [
        File("Decoder.mlmodelc/analytics/coremldata.bin", 243, .sha256("fe92b6cfaa012abd5248c0bc877832f19807015abffc60d87b8ccc8ccb48b3b5")),
        File("Decoder.mlmodelc/coremldata.bin", 560, .sha256("3b06e66768f0df7e21795f50e2b29300e33eeb1a2579dc42c695279c2d308497")),
        File("Decoder.mlmodelc/model.mil", 13110, .gitBlob("36dcd5cbb71d13f42a177427ddbab7539e0d167e")),
        File("Decoder.mlmodelc/weights/weight.bin", 23_604_992, .sha256("02a0d219f281b9665bc10c8768649403b2eebbbf4b44c627041d948e0de11bb4")),
        File("Encoder.mlmodelc/analytics/coremldata.bin", 243, .sha256("d87101d824d6723cf95304da33755c3c60e762663b9ef2b0c4bd0aa166a09a0d")),
        File("Encoder.mlmodelc/coremldata.bin", 514, .sha256("397a84a4062f563cbc5f56077c674f09a61d85be5090f61d2f1932afb92ac0fe")),
        File("Encoder.mlmodelc/model.mil", 1_002_653, .gitBlob("8c5c9915fc71bb7e9b0be1e7b55e38ec6a007e7f")),
        File("Encoder.mlmodelc/weights/weight.bin", 594_211_328, .sha256("315ba01f33cadbf601d43ac7f5c86208b7aa75fdaa34705c9869d5abe3521c9b")),
        File("JointDecisionv3.mlmodelc/analytics/coremldata.bin", 243, .sha256("68d38ca646aebafa7a9329e2efda50f5767c49e89fdb5f77f212072bb66f97c4")),
        File("JointDecisionv3.mlmodelc/coremldata.bin", 592, .sha256("5e3af5a4ce686f6c237cadbd9284e10d333bc0e1546633cd0e430e6194044bc4")),
        File("JointDecisionv3.mlmodelc/model.mil", 11777, .gitBlob("be552d46f98f9dc9b242b0d1659833db60aa3f83")),
        File("JointDecisionv3.mlmodelc/weights/weight.bin", 12_642_764, .sha256("3f310b85b82341c53ec383025ab094a4e462ee1c592e1ad7c6bfe39cff66ca25")),
        File("Preprocessor.mlmodelc/analytics/coremldata.bin", 243, .sha256("c9beeb989c8d66f8be11df59bc6df277ec76cee404f6865b46243835ef562f6d")),
        File("Preprocessor.mlmodelc/coremldata.bin", 486, .sha256("dbde3f2300842c1fd51ef3ff948a0bcffe65ffd2dca10707f2509f32c1d65b1d")),
        File("Preprocessor.mlmodelc/metadata.json", 2841, .gitBlob("06162c58cf2f5343a0e60f36f843bcdf3cc58527")),
        File("Preprocessor.mlmodelc/model.mil", 28181, .gitBlob("f987e2479228436c49189aa47edb376db74dcff5")),
        File("Preprocessor.mlmodelc/weights/weight.bin", 491_072, .sha256("129b76e3aeafa8afa3ea76d995b964b145fe83700d579f6ff42c4c38fa0968ea")),
        File("parakeet_vocab.json", 151_122, .gitBlob("c684822ec3b671ebc449c433a7012398d39b8bb0")),
    ]

    public static var downloadBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }

    /// The folder holding the model's own folder, as FluidAudio expects.
    public static var parent: URL {
        if let dir = ProcessInfo.processInfo.environment["SLICE_PARAKEET_MODEL_DIR"] { return URL(fileURLWithPath: dir) }
        return ProjectBundle.migrated(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
                                      "Screen Recorder", to: "Slice")
            .appendingPathComponent("Transcription").appendingPathComponent("Parakeet")
    }

    public static var directory: URL { parent.appendingPathComponent(folderName) }
    static var staging: URL { parent.appendingPathComponent(".\(folderName).download") }
    static var manifestURL: URL { directory.appendingPathComponent("slice-manifest.json") }

    struct Manifest: Codable {
        var repo: String
        var revision: String
        var installedAt: Date
    }

    public static var isInstalled: Bool {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.repo == repo, manifest.revision == revision else { return false }
        return files.allSatisfy { ModelDownload.size(of: directory.appendingPathComponent($0.path)) == $0.bytes }
    }

    public static var installedBytes: Int64 { bytes(in: directory) }

    /// Bytes of an unfinished download kept for the next try.
    public static var stagedBytes: Int64 { bytes(in: staging) }

    public static func install(progress: @escaping @Sendable (Progress) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let total = downloadBytes
        var kept: [String: Bool] = [:]
        for file in files { kept[file.path] = try verified(file, at: staging.appendingPathComponent(file.path), sizeOnly: true) }
        let needed = files.filter { kept[$0.path] != true }.reduce(0) { $0 + $1.bytes }
        if let free = try? parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, free < needed + 50_000_000 {
            throw Failure.diskFull(needed: needed + 50_000_000 - free)
        }

        var done = total - needed
        progress(.downloading(received: done, total: total))
        for file in files where kept[file.path] != true {
            let dest = staging.appendingPathComponent(file.path)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let before = done
            try await ModelDownload(destination: dest) { progress(.downloading(received: before + min($0, file.bytes), total: total)) }
                .run(url(for: file))
            try Task.checkCancellation()
            done += file.bytes
            progress(.downloading(received: done, total: total))
        }

        progress(.verifying)
        for file in files {
            try Task.checkCancellation()
            let url = staging.appendingPathComponent(file.path)
            guard try verified(file, at: url, sizeOnly: false) else {
                try? fm.removeItem(at: url)
                throw Failure.corrupt(file.path)
            }
        }
        let manifest = Manifest(repo: repo, revision: revision, installedAt: Date())
        try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("slice-manifest.json"), options: .atomic)
        if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
        try fm.moveItem(at: staging, to: directory)
    }

    public static func remove() throws {
        let fm = FileManager.default
        for url in [directory, staging] where fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    }

    static func url(for file: File) -> URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(file.path)")!
    }

    static func verified(_ file: File, at url: URL, sizeOnly: Bool) throws -> Bool {
        guard ModelDownload.size(of: url) == file.bytes else { return false }
        if sizeOnly { return true }
        switch file.digest {
        case let .sha256(hex):
            return try ModelDownload.hash(of: url, using: SHA256()) == hex
        case let .gitBlob(hex):
            return try ModelDownload.hash(of: url, using: Insecure.SHA1(), prefix: Data("blob \(file.bytes)\0".utf8)) == hex
        }
    }

    static func bytes(in folder: URL) -> Int64 {
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var sum: Int64 = 0
        for case let url as URL in items { sum += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return sum
    }
}
