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

/// Event payload type. To aid encoding and decoding
public struct AWSEventPayload: Sendable, Codable, Equatable {
    public let buffer: ByteBuffer

    /// Initialise AWSEventPayload
    /// - Parameter payload: Event Payload
    private init(buffer: ByteBuffer) {
        self.buffer = buffer
    }

    /// Codable decode
    public init(from decoder: Decoder) throws {
        let response = decoder.userInfo[.awsEvent]! as! EventDecodingContainer
        self.buffer = response.decodePayload()
    }

    /// Codable encode
    public func encode(to encoder: Encoder) throws {
        preconditionFailure("Event encoding is not supported yet")
    }
}
