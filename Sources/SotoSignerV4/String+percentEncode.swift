//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// MARK: - Encoding Extensions

extension StringProtocol {

    fileprivate static func hexToAscii(_ hex: UInt8) -> UInt8 {
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

    package func addingAWSPercentEncoding(forURLComponent component: AWSURLComponentSet) -> String {
        let fastResult = utf8.withContiguousStorageIfAvailable {
            Self.addingAWSPercentEncoding(utf8Buffer: $0, component: component)
        }
        if let fastResult {
            return fastResult
        } else {
            return Self.addingAWSPercentEncoding(utf8Buffer: utf8, component: component)
        }
    }

    fileprivate static func addingAWSPercentEncoding(utf8Buffer: some Collection<UInt8>, component: AWSURLComponentSet) -> String {
        let maxLength = utf8Buffer.count * 3
        let percent = UInt8(ascii: "%")
        let result = withUnsafeTemporaryAllocation(of: UInt8.self, capacity: maxLength) { buffer in
            var i = 0
            for byte in utf8Buffer {
                if byte.isAllowedIn(component) {
                    buffer[i] = byte
                    i += 1
                } else {
                    buffer[i] = percent
                    buffer[i + 1] = hexToAscii(byte >> 4)
                    buffer[i + 2] = hexToAscii(byte & 0xF)
                    i += 3
                }
            }
            return String(decoding: buffer[..<i], as: UTF8.self)
        }
        return result
    }

    fileprivate static func asciiToHex(_ ascii: UInt8) -> UInt8? {
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

    package func removingURLPercentEncoding(excluding: Set<UInt8> = []) -> String? {
        let fastResult = utf8.withContiguousStorageIfAvailable {
            Self.removingURLPercentEncoding(utf8Buffer: $0, excluding: excluding)
        }
        if let fastResult {
            return fastResult
        } else {
            return Self.removingURLPercentEncoding(utf8Buffer: utf8, excluding: excluding)
        }
    }

    package static func removingURLPercentEncoding(utf8Buffer: some Collection<UInt8>, excluding: Set<UInt8> = []) -> String? {
        let result: String? = withUnsafeTemporaryAllocation(of: UInt8.self, capacity: utf8Buffer.count) { buffer -> String? in
            var i = 0
            var byte: UInt8 = 0
            var hexDigitsRequired = 0
            for v in utf8Buffer {
                if v == UInt8(ascii: "%") {
                    guard hexDigitsRequired == 0 else {
                        return nil
                    }
                    hexDigitsRequired = 2
                } else if hexDigitsRequired > 0 {
                    guard let hex = asciiToHex(v) else {
                        return nil
                    }
                    if hexDigitsRequired == 2 {
                        byte = hex << 4
                    } else if hexDigitsRequired == 1 {
                        byte += hex
                        if excluding.contains(byte) {
                            // Keep the original percent-encoding for this byte
                            i = buffer[i...i + 2].initialize(fromContentsOf: [UInt8(ascii: "%"), hexToAscii(byte >> 4), v])
                        } else {
                            buffer[i] = byte
                            i += 1
                            byte = 0
                        }
                    }
                    hexDigitsRequired -= 1
                } else {
                    buffer[i] = v
                    i += 1
                }
            }
            guard hexDigitsRequired == 0 else {
                return nil
            }
            return String(decoding: buffer[..<i], as: UTF8.self)
        }
        return result
    }
}

// MARK: - Validation Extensions

package struct AWSURLComponentSet: OptionSet {
    package let rawValue: UInt8
    package init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    static var path: AWSURLComponentSet { .init(rawValue: 1 << 0) }
    static var s3Path: AWSURLComponentSet { .init(rawValue: 1 << 1) }
    static var query: AWSURLComponentSet { .init(rawValue: 1 << 2) }
    static var queryItem: AWSURLComponentSet { .init(rawValue: 1 << 3) }
    //static let s3PathAllowedCharacters = CharacterSet.urlPathAllowed.subtracting(.init(charactersIn: "+@()&$=:,'!*"))
    //static let uriAllowedWithSlashCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/")
    //static let uriAllowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    //static let queryAllowedCharacters = CharacterSet(charactersIn: "/;+").inverted
}

extension UTF8.CodeUnit {
    fileprivate func isAllowedIn(_ component: AWSURLComponentSet) -> Bool {
        allowedURLComponents & component.rawValue != 0
    }

    // ===------------------------------------------------------------------------------------=== //
    // Grammar from RFC 3986:
    //
    // let alpha       = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    // let digit       = "0123456789"
    // let pct-encoded = DIGIT + "ABCDEFabcdef"
    // let gen_delims  = ":/?#[]@"
    // let sub_delims  = "!$&'()*+,;="
    // let unreserved  = ALPHA + DIGIT + "-._~"
    // let reserved    = gen_delims + sub_delims
    //
    // let pchar = unreserved + pct-encoded + sub-delims + ":" + "@" + "%"
    // let path = pchar + "/"
    // let query = pchar + "/" + "?"
    // let query_item = query - "=" - "&"
    //
    // ===------------------------------------------------------------------------------------=== //
    fileprivate var allowedURLComponents: AWSURLComponentSet.RawValue {
        switch self {
        case UInt8(ascii: "!"):
            return 0b00001111
        case UInt8(ascii: "$"):
            return 0b00001111
        case UInt8(ascii: "&"):
            return 0b00000111
        case UInt8(ascii: "'"):
            return 0b00001111
        case UInt8(ascii: "("):
            return 0b00001111
        case UInt8(ascii: ")"):
            return 0b00001111
        case UInt8(ascii: "*"):
            return 0b00001111
        case UInt8(ascii: "+"):
            return 0b00001101
        case UInt8(ascii: ","):
            return 0b00001111
        case UInt8(ascii: "-"):
            return 0b00001111
        case UInt8(ascii: "."):
            return 0b00001111
        case UInt8(ascii: "/"):
            return 0b00001111
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            return 0b00001111
        case UInt8(ascii: ":"):
            return 0b00000000
        case UInt8(ascii: ";"):
            return 0b00001111
        case UInt8(ascii: "="):
            return 0b00000111
        case UInt8(ascii: "?"):
            return 0b00001100
        case UInt8(ascii: "@"):
            return 0b00001111
        case UInt8(ascii: "A")...UInt8(ascii: "Z"):
            return 0b00001111
        case UInt8(ascii: "_"):
            return 0b00001111
        case UInt8(ascii: "a")...UInt8(ascii: "z"):
            return 0b00001111
        case UInt8(ascii: "~"):
            return 0b00001111
        default:
            return 0
        }
    }
}
