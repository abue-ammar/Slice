//
//  GIFLZW.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/17/26.
//

import Foundation

/// GIF's variable-width LZW for 8-bit indices, packed into 255-byte sub-blocks.
final class GIFLZW {
    private static let clearCode = 256
    private static let endCode = 257
    private static let maxCode = 4096

    private let table = UnsafeMutablePointer<UInt16>.allocate(capacity: maxCode * 256)
    private let block = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)

    deinit {
        table.deallocate()
        block.deallocate()
    }

    func encode(_ indices: UnsafeBufferPointer<UInt8>, into out: inout Data) {
        out.append(8)
        guard let first = indices.first else { return out.append(0) }
        var bits: UInt32 = 0, bitCount = 0, length = 0
        var codeSize = 9, next = Self.endCode + 1

        func emit(_ code: Int) {
            bits |= UInt32(code) << UInt32(bitCount)
            bitCount += codeSize
            while bitCount >= 8 {
                put(UInt8(truncatingIfNeeded: bits))
                bits >>= 8
                bitCount -= 8
            }
        }
        func put(_ byte: UInt8) {
            block[length] = byte
            length += 1
            if length == 255 { flushBlock() }
        }
        func flushBlock() {
            guard length > 0 else { return }
            out.append(UInt8(length))
            out.append(block, count: length)
            length = 0
        }
        func clear() { table.update(repeating: 0, count: Self.maxCode * 256) }

        clear()
        emit(Self.clearCode)
        var prefix = Int(first)
        for k in indices.dropFirst() {
            let slot = prefix << 8 | Int(k)
            let code = table[slot]
            if code != 0 {
                prefix = Int(code)
                continue
            }
            emit(prefix)
            if next == Self.maxCode {
                emit(Self.clearCode)
                clear()
                next = Self.endCode + 1
                codeSize = 9
            } else {
                if next >= 1 << codeSize { codeSize += 1 }
                table[slot] = UInt16(next)
                next += 1
            }
            prefix = Int(k)
        }
        emit(prefix)
        emit(Self.endCode)
        if bitCount > 0 { put(UInt8(truncatingIfNeeded: bits)) }
        flushBlock()
        out.append(0)
    }
}
