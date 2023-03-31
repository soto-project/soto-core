//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// Holds request or response data that is encoded as base64 during transit
public struct AWSBase64Data: Sendable, Codable, Equatable {
    let base64String: String

    /// Initialise AWSBase64Data
    /// - Parameter base64String: base64 encoded data
    private init(base64String: String) {
        self.base64String = base64String
    }

    /// construct `AWSBase64Data` from raw data
    public static func data<C: Collection>(_ data: C) -> Self where C.Element == UInt8 {
        return .init(base64String: String(base64Encoding: data))
    }

    /// construct `AWSBase64Data` from base64 encoded data
    public static func base64(_ base64String: String) -> Self {
        return .init(base64String: base64String)
    }

    /// Codable decode
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.base64String = try container.decode(String.self)
    }

    /// Codable encode
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.base64String)
    }

    /// size of base64 data
    public var base64count: Int {
        return self.base64String.count
    }

    /// return blob as Data
    public func decoded() -> [UInt8]? {
        return try? self.base64String.base64decoded()
    }
}
