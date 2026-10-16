//
//  ModelDownload.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/5/26.
//

import CryptoKit
import Foundation

/// One file downloaded to a set place, reporting the bytes actually received as they arrive.
final class ModelDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    enum Failure: LocalizedError, Equatable {
        case server(Int)
        case network(String)

        var errorDescription: String? {
            switch self {
            case let .server(code): "The download didn't finish: the server answered \(code)."
            case let .network(m): "The download didn't finish: \(m)"
            }
        }
    }

    private let destination: URL
    private let onBytes: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var failure: Error?

    init(destination: URL, onBytes: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.onBytes = onBytes
    }

    func run(_ url: URL) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                lock.withLock { continuation = c }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onBytes(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file is gone once this returns, so it's moved now.
        if let http = downloadTask.response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            lock.withLock { failure = Failure.server(http.statusCode) }
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            lock.withLock { failure = error }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let c = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { continuation = nil }
            return continuation
        }
        if let error = error as? URLError, error.code == .cancelled {
            c?.resume(throwing: CancellationError())
        } else if let error {
            c?.resume(throwing: Failure.network(error.localizedDescription))
        } else if let failure = lock.withLock({ failure }) {
            c?.resume(throwing: failure)
        } else {
            c?.resume()
        }
    }

    static func hash<H: HashFunction>(of url: URL, using initial: H, prefix: Data = Data()) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = initial
        hasher.update(data: prefix)
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func size(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }
}
