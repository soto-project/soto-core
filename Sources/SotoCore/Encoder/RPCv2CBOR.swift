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

internal import CBOR
import NIOCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// CBOR encoding and decoding of shapes for the RPC v2 CBOR protocol.
///
/// A shape finds the request or response container in ``AWSCodingContext``, so the CBOR coders are
/// used as they are.
enum RPCv2CBOR {
    /// Encode a shape. `request` is what the shape's `encode(to:)` finds in ``AWSCodingContext/request``.
    static func encode<Input: Encodable>(
        _ input: Input,
        request: RequestEncodingContainer,
        allocator: ByteBufferAllocator
    ) throws -> ByteBuffer {
        let bytes = try AWSCodingContext.$request.withValue(request) {
            try CBOREncoder().encode(input)
        }
        return allocator.buffer(bytes: bytes)
    }

    /// Decode a shape. A missing body decodes as an empty structure.
    static func decode<Output: Decodable>(
        _ type: Output.Type,
        from buffer: ByteBuffer?,
        response: ResponseDecodingContainer,
        serviceProtocol: ServiceProtocol? = nil,
        errorMap: (any (AWSErrorType & Decodable).Type)? = nil
    ) throws -> Output {
        let bytes: [UInt8]
        if let buffer, buffer.readableBytes > 0 {
            bytes = Array(buffer.readableBytesView)
        } else {
            // an empty map
            bytes = [0xA0]
        }
        return try AWSCodingContext.$response.withValue(response) {
            try AWSCodingContext.$serviceProtocol.withValue(serviceProtocol) {
                try AWSCodingContext.$errorMap.withValue(errorMap) {
                    try CBORDecoder().decode(Output.self, from: bytes)
                }
            }
        }
    }
}
