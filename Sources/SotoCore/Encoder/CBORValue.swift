//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// Errors thrown by ``CBORDecoder`` when the input is not well formed CBOR.
public enum CBORError: Error, Equatable {
    /// The input ended before a complete data item was read.
    case truncatedInput
    /// Arrays, maps or tags are nested deeper than the decoder allows.
    case nestingTooDeep
    /// Bytes remain after the top level data item.
    case trailingData
    /// The input is not valid CBOR, or uses a feature this implementation does not support.
    case malformed(String)
}

/// A decoded CBOR data item.
///
/// Tags other than tag 1 (epoch based date) are dropped while parsing, so only the
/// tagged content is represented here.
indirect enum CBORValue {
    /// Major type 0
    case unsigned(UInt64)
    /// Major type 1. The represented integer is `-1 - value`.
    case negative(UInt64)
    /// Major type 2
    case bytes([UInt8])
    /// Major type 3
    case text(String)
    /// Major type 4
    case array([CBORValue])
    /// Major type 5, in wire order
    case map([(key: CBORValue, value: CBORValue)])
    case bool(Bool)
    case null
    /// Half, single or double precision float, widened to `Double`
    case double(Double)
    /// A single precision float, only produced when encoding
    case float(Float)
    /// Tag 1: seconds since the unix epoch
    case date(Double)
}

enum CBORMajorType {
    static let unsigned: UInt8 = 0
    static let negative: UInt8 = 1
    static let bytes: UInt8 = 2
    static let text: UInt8 = 3
    static let array: UInt8 = 4
    static let map: UInt8 = 5
    static let tag: UInt8 = 6
    static let simple: UInt8 = 7
}
