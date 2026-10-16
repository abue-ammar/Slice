//
//  Usbmux.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/9/26.
//

import Darwin
import Foundation

/// A minimal client for usbmuxd, the macOS system daemon that multiplexes connections to iOS devices over USB (it's
/// what Finder, Xcode and QuickTime sit on). It speaks usbmuxd's plist protocol over its Unix socket; no private
/// framework is linked. Used for three things only:
/// - attach/detach events, pushed by the daemon (no polling),
/// - whether the Mac holds a pairing record for a device (i.e. the user tapped Trust),
/// - opening a byte stream to a TCP port on the device (lockdown for the identity; an optional input agent).
public enum Usbmux {
    public static let socketPath = "/var/run/usbmuxd"

    public struct AttachedDevice: Equatable, Sendable {
        public let id: Int
        public let serial: String
        public let isUSB: Bool
    }

    public enum Event: Equatable, Sendable {
        case attached(AttachedDevice)
        case detached(id: Int)
        case paired(id: Int)
    }

    public enum Failure: Error, Equatable {
        case unavailable
        case refused(Int)
        case malformed
        case closed
    }

    // MARK: - Messages

    /// usbmuxd frames each plist with a 16-byte little-endian header: length (including the header), protocol
    /// version 1, message type 8 (plist), tag.
    static func frame(_ message: [String: Any], tag: UInt32 = 1) throws -> Data {
        var body: [String: Any] = ["ClientVersionString": "Slice", "ProgName": "Slice", "kLibUSBMuxVersion": 3]
        body.merge(message) { _, new in new }
        let plist = try PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
        var data = Data()
        for v in [UInt32(16 + plist.count), 1, 8, tag] { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        data.append(plist)
        return data
    }

    static func event(from message: [String: Any]) -> Event? {
        switch message["MessageType"] as? String {
        case "Attached":
            guard let id = message["DeviceID"] as? Int, let props = message["Properties"] as? [String: Any],
                  let serial = props["SerialNumber"] as? String else { return nil }
            return .attached(AttachedDevice(id: id, serial: serial, isUSB: (props["ConnectionType"] as? String) == "USB"))
        case "Detached":
            return (message["DeviceID"] as? Int).map { .detached(id: $0) }
        case "Paired":
            return (message["DeviceID"] as? Int).map { .paired(id: $0) }
        default:
            return nil
        }
    }

    /// The device's port in the byte order usbmuxd expects (network order, read as a little-endian integer).
    static func wirePort(_ port: UInt16) -> Int { Int(port.bigEndian) }

    // MARK: - Requests

    public static func listen(_ handler: @escaping @Sendable (Event) -> Void,
                              onEnd: @escaping @Sendable () -> Void) throws -> Listener {
        let socket = try UsbmuxSocket.open()
        try socket.write(frame(["MessageType": "Listen"]))
        let reply = try socket.readMessage()
        guard (reply["Number"] as? Int) == 0 else { throw Failure.refused(reply["Number"] as? Int ?? -1) }
        let listener = Listener(socket: socket)
        let thread = Thread {
            while let message = try? socket.readMessage() {
                if let event = event(from: message) { handler(event) }
            }
            if !listener.isCancelled { onEnd() }
        }
        thread.name = "usbmuxd events"
        thread.qualityOfService = .utility
        thread.start()
        return listener
    }

    public final class Listener: @unchecked Sendable {
        private let socket: UsbmuxSocket
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }

        init(socket: UsbmuxSocket) { self.socket = socket }

        public func cancel() {
            lock.withLock { cancelled = true }
            socket.close()
        }
    }

    /// usbmuxd normally answers at once; a timeout keeps a daemon that doesn't from hanging the caller for good.
    public static func hasPairRecord(serial: String, timeout: TimeInterval = 3) -> Bool {
        guard let socket = try? UsbmuxSocket.open(timeout: timeout) else { return false }
        defer { socket.close() }
        guard (try? socket.write(frame(["MessageType": "ReadPairRecord", "PairRecordID": serial]))) != nil,
              let reply = try? socket.readMessage() else { return false }
        return reply["PairRecordData"] is Data
    }

    public static func connect(deviceID: Int, port: UInt16, timeout: TimeInterval = 5) throws -> UsbmuxSocket {
        let socket = try UsbmuxSocket.open(timeout: timeout)
        do {
            try socket.write(frame(["MessageType": "Connect", "DeviceID": deviceID, "PortNumber": wirePort(port)]))
            let reply = try socket.readMessage()
            let code = reply["Number"] as? Int ?? -1
            guard code == 0 else { throw Failure.refused(code) }
            return socket
        } catch {
            socket.close()
            throw error
        }
    }
}

public struct LockdownInfo: Equatable, Sendable {
    public var productType: String?
    public var deviceName: String?
    public var deviceClass: String?
    public var productVersion: String?

    public init(productType: String? = nil, deviceName: String? = nil, deviceClass: String? = nil, productVersion: String? = nil) {
        self.productType = productType
        self.deviceName = deviceName
        self.deviceClass = deviceClass
        self.productVersion = productVersion
    }

    init(values: [String: Any]) {
        productType = values["ProductType"] as? String
        deviceName = values["DeviceName"] as? String
        deviceClass = values["DeviceClass"] as? String
        productVersion = values["ProductVersion"] as? String
    }

    static let port: UInt16 = 62078

    public static func query(deviceID: Int) throws -> LockdownInfo {
        let socket = try Usbmux.connect(deviceID: deviceID, port: port)
        defer { socket.close() }
        // Lockdown frames each plist with a 4-byte big-endian length.
        let request = try PropertyListSerialization.data(fromPropertyList: ["Label": "Slice", "Request": "GetValue"],
                                                         format: .xml, options: 0)
        var data = Data()
        withUnsafeBytes(of: UInt32(request.count).bigEndian) { data.append(contentsOf: $0) }
        data.append(request)
        try socket.write(data)
        let header = try socket.read(exactly: 4)
        let length = header.reduce(0) { $0 << 8 | Int($1) }
        guard length > 0, length < 1 << 20 else { throw Usbmux.Failure.malformed }
        let body = try socket.read(exactly: length)
        guard let reply = try PropertyListSerialization.propertyList(from: body, format: nil) as? [String: Any],
              let values = reply["Value"] as? [String: Any] else { throw Usbmux.Failure.malformed }
        return LockdownInfo(values: values)
    }
}

public final class UsbmuxSocket: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var closed = false

    private init(fd: Int32) { self.fd = fd }

    deinit { close() }

    static func open(timeout: TimeInterval = 0) throws -> UsbmuxSocket {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Usbmux.Failure.unavailable }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        if timeout > 0 {
            var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Array(Usbmux.socketPath.utf8CString)
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            path.withUnsafeBytes { dst.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(dst.count))) }
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0 else {
            Darwin.close(fd)
            throw Usbmux.Failure.unavailable
        }
        return UsbmuxSocket(fd: fd)
    }

    public func write(_ data: Data) throws {
        try data.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let n = Darwin.write(fd, buffer.baseAddress! + sent, buffer.count - sent)
                guard n > 0 else { throw Usbmux.Failure.closed }
                sent += n
            }
        }
    }

    public func read(exactly count: Int) throws -> Data {
        var data = Data(count: count)
        var got = 0
        try data.withUnsafeMutableBytes { buffer in
            while got < count {
                let n = Darwin.read(fd, buffer.baseAddress! + got, count - got)
                guard n > 0 else { throw Usbmux.Failure.closed }
                got += n
            }
        }
        return data
    }

    public func read(upTo max: Int) throws -> Data {
        var data = Data(count: max)
        let n = data.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, max) }
        guard n >= 0 else { throw Usbmux.Failure.closed }
        return data.prefix(n)
    }

    func readMessage() throws -> [String: Any] {
        let header = try read(exactly: 16)
        let length = header.prefix(4).enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
        guard length >= 16, length < 1 << 24 else { throw Usbmux.Failure.malformed }
        let body = try read(exactly: length - 16)
        guard let plist = try PropertyListSerialization.propertyList(from: body, format: nil) as? [String: Any] else {
            throw Usbmux.Failure.malformed
        }
        return plist
    }

    public func close() {
        lock.withLock {
            guard !closed else { return }
            closed = true
            shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
    }
}
