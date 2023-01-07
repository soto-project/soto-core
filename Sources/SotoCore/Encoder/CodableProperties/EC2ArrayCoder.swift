//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// MARK: EC2 Array Coder

// EC2 requires a special case array encoder as it flattens arrays on encode, while still expecting them to have array elements
// on decode. EC2 will use this Coder instead of the one in soto-core due to scoping rules.

/// Coder for encoding/decoding Arrays. This is extended to support encoding and decoding based on whether `Element` is `Encodable` or `Decodable`.
public struct EC2ArrayCoder<Properties: ArrayCoderProperties, Element: _SotoSendable>: CustomCoder {
    public typealias CodableValue = [Element]
}

public typealias EC2StandardArrayCoder<Element> = EC2ArrayCoder<StandardArrayCoderProperties, Element>

/// CodingKey used by Encoder property wrappers
private struct _EncodingWrapperKey: CodingKey {
    public var stringValue: String
    public var intValue: Int?

    public init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    public init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }

    public init(stringValue: String, intValue: Int?) {
        self.stringValue = stringValue
        self.intValue = intValue
    }
}

/// extend to support decoding
extension EC2ArrayCoder: CustomDecoder where Element: Decodable {
    public static func decode(from decoder: Decoder) throws -> CodableValue {
        let topLevelContainer = try decoder.container(keyedBy: _EncodingWrapperKey.self)
        var values: [Element] = []
        let memberKey = _EncodingWrapperKey(stringValue: Properties.member, intValue: nil)
        guard topLevelContainer.contains(memberKey) else { return values }

        var container = try topLevelContainer.nestedUnkeyedContainer(forKey: memberKey)
        while !container.isAtEnd {
            values.append(try container.decode(Element.self))
        }
        return values
    }
}

/// extend to support encoding (flatten the array)
extension EC2ArrayCoder: CustomEncoder where Element: Encodable {
    public static func encode(value: CodableValue, to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
