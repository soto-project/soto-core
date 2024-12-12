//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) YEARS the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension String {

    package func addingPercentEncoding(utf8Buffer: some Collection<UInt8>, allowedCharacters: Set<UInt8>) -> String {
        let maxLength = utf8Buffer.count * 3
        let result = withUnsafeTemporaryAllocation(of: UInt8.self, capacity: maxLength + 1) { _buffer in
            var buffer = OutputBuffer(initializing: _buffer.baseAddress!, capacity: _buffer.count)
            for v in utf8Buffer {
                if allowedCharacters.contains(v) {
                    buffer.appendElement(v)
                } else {
                    buffer.appendElement(UInt8(ascii: "%"))
                    buffer.appendElement(hexToAscii(v >> 4))
                    buffer.appendElement(hexToAscii(v & 0xF))
                }
            }
            buffer.appendElement(0)  // NULL-terminated
            let initialized = buffer.relinquishBorrowedMemory()
            return String(cString: initialized.baseAddress!)
        }
        return result
    }

    private func hexToAscii(_ hex: UInt8) -> UInt8 {
        switch hex {
        case 0x0:
            return UInt8(ascii: "0")
        case 0x1:
            return UInt8(ascii: "1")
        case 0x2:
            return UInt8(ascii: "2")
        case 0x3:
            return UInt8(ascii: "3")
        case 0x4:
            return UInt8(ascii: "4")
        case 0x5:
            return UInt8(ascii: "5")
        case 0x6:
            return UInt8(ascii: "6")
        case 0x7:
            return UInt8(ascii: "7")
        case 0x8:
            return UInt8(ascii: "8")
        case 0x9:
            return UInt8(ascii: "9")
        case 0xA:
            return UInt8(ascii: "A")
        case 0xB:
            return UInt8(ascii: "B")
        case 0xC:
            return UInt8(ascii: "C")
        case 0xD:
            return UInt8(ascii: "D")
        case 0xE:
            return UInt8(ascii: "E")
        case 0xF:
            return UInt8(ascii: "F")
        default:
            fatalError("Invalid hex digit: \(hex)")
        }
    }

    private func asciiToHex(_ ascii: UInt8) -> UInt8? {
        switch ascii {
        case UInt8(ascii: "0"):
            return 0x0
        case UInt8(ascii: "1"):
            return 0x1
        case UInt8(ascii: "2"):
            return 0x2
        case UInt8(ascii: "3"):
            return 0x3
        case UInt8(ascii: "4"):
            return 0x4
        case UInt8(ascii: "5"):
            return 0x5
        case UInt8(ascii: "6"):
            return 0x6
        case UInt8(ascii: "7"):
            return 0x7
        case UInt8(ascii: "8"):
            return 0x8
        case UInt8(ascii: "9"):
            return 0x9
        case UInt8(ascii: "A"), UInt8(ascii: "a"):
            return 0xA
        case UInt8(ascii: "B"), UInt8(ascii: "b"):
            return 0xB
        case UInt8(ascii: "C"), UInt8(ascii: "c"):
            return 0xC
        case UInt8(ascii: "D"), UInt8(ascii: "d"):
            return 0xD
        case UInt8(ascii: "E"), UInt8(ascii: "e"):
            return 0xE
        case UInt8(ascii: "F"), UInt8(ascii: "f"):
            return 0xF
        default:
            return nil
        }
    }

    package func addingPercentEncoding(allowedCharacters: Set<UInt8>) -> String {
        let maybeResult = self.utf8.withContiguousStorageIfAvailable { utf8Buffer in
            return self.addingPercentEncoding(utf8Buffer: utf8Buffer, allowedCharacters: allowedCharacters)
        }
        if let result = maybeResult {
            return result
        }
        return addingPercentEncoding(allowedCharacters: allowedCharacters)
    }

    package func queryEncode() -> String {
        let result = addingPercentEncoding(allowedCharacters: String.queryAllowedCharacters)
        print("queryEncode: \(self) -> \(result)")
        return result
    }

    package func s3PathEncode() -> String {
        addingPercentEncoding(allowedCharacters: String.s3PathAllowedCharacters)
    }

    package func uriEncode() -> String {
        addingPercentEncoding(allowedCharacters: String.uriAllowedCharacters)
    }

    package func uriEncodeWithSlash() -> String {
        addingPercentEncoding(allowedCharacters: String.uriAllowedWithSlashCharacters)
    }

    package static let s3PathAllowedCharacters: Set<UInt8> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/!*'()".utf8)
    package static let uriAllowedWithSlashCharacters: Set<UInt8> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/".utf8)
    package static let uriAllowedCharacters: Set<UInt8> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)
    package static let queryAllowedCharacters: Set<UInt8> = Set(0 ... .max).subtracting("/;+".utf8)
}
