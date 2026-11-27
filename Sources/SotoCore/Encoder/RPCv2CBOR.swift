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
/// The CBOR coders do not carry `userInfo`, but a root shape reads the request or response container
/// from it. Shapes are therefore coded through a wrapper that hands the shape a coder with the
/// `userInfo` it expects. Only the root shape sees it, which is enough because RPC v2 sends every
/// other member in the body.
enum RPCv2CBOR {
    /// What a root shape may read from `userInfo` while it is decoded.
    struct DecodingContext: Sendable {
        var response: ResponseDecodingContainer?
        var serviceProtocol: ServiceProtocol?
        var errorMap: (any (AWSErrorType & Decodable).Type)?

        var userInfo: [CodingUserInfoKey: Any] {
            var userInfo: [CodingUserInfoKey: Any] = [:]
            userInfo[.awsResponse] = self.response
            userInfo[.awsProtocol] = self.serviceProtocol
            userInfo[.awsErrorMap] = self.errorMap
            return userInfo
        }
    }

    @TaskLocal private static var decodingContext = DecodingContext()

    /// Encode a shape. `request` is what the shape's `encode(to:)` finds in `userInfo[.awsRequest]`.
    static func encode<Input: Encodable>(
        _ input: Input,
        request: RequestEncodingContainer,
        allocator: ByteBufferAllocator
    ) throws -> ByteBuffer {
        let bytes = try CBOREncoder().encode(EncodingBox(value: input, request: request))
        return allocator.buffer(bytes: bytes)
    }

    /// Decode a shape. A missing body decodes as an empty structure.
    static func decode<Output: Decodable>(
        _ type: Output.Type,
        from buffer: ByteBuffer?,
        context: DecodingContext
    ) throws -> Output {
        let bytes: [UInt8]
        if let buffer, buffer.readableBytes > 0 {
            bytes = Array(buffer.readableBytesView)
        } else {
            // an empty map
            bytes = [0xA0]
        }
        return try Self.$decodingContext.withValue(context) {
            try CBORDecoder().decode(DecodingBox<Output>.self, from: bytes).value
        }
    }

    private struct EncodingBox<Value: Encodable>: Encodable {
        let value: Value
        let request: RequestEncodingContainer

        func encode(to encoder: any Encoder) throws {
            try self.value.encode(to: UserInfoEncoder(base: encoder, userInfo: [.awsRequest: self.request]))
        }
    }

    private struct DecodingBox<Value: Decodable>: Decodable {
        let value: Value

        init(from decoder: any Decoder) throws {
            self.value = try Value(from: UserInfoDecoder(base: decoder, userInfo: RPCv2CBOR.decodingContext.userInfo))
        }
    }

    private struct UserInfoEncoder: Encoder {
        let base: any Encoder
        let userInfo: [CodingUserInfoKey: Any]
        var codingPath: [any CodingKey] { self.base.codingPath }

        func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
            self.base.container(keyedBy: type)
        }
        func unkeyedContainer() -> any UnkeyedEncodingContainer {
            self.base.unkeyedContainer()
        }
        func singleValueContainer() -> any SingleValueEncodingContainer {
            self.base.singleValueContainer()
        }
    }

    private struct UserInfoDecoder: Decoder {
        let base: any Decoder
        let userInfo: [CodingUserInfoKey: Any]
        var codingPath: [any CodingKey] { self.base.codingPath }

        func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
            try self.base.container(keyedBy: type)
        }
        func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
            try self.base.unkeyedContainer()
        }
        func singleValueContainer() throws -> any SingleValueDecodingContainer {
            UserInfoSingleValueContainer(base: try self.base.singleValueContainer())
        }
    }

    /// Single value container that decodes a nested shape through a `DecodingBox`, so the nested
    /// shape also finds the `userInfo`. Errors are decoded this way: a service error asks the root
    /// decoder for a single value container and decodes an `AWSResponseError` from it.
    private struct UserInfoSingleValueContainer: SingleValueDecodingContainer {
        let base: any SingleValueDecodingContainer
        var codingPath: [any CodingKey] { self.base.codingPath }

        func decodeNil() -> Bool { self.base.decodeNil() }
        func decode(_ type: Bool.Type) throws -> Bool { try self.base.decode(type) }
        func decode(_ type: String.Type) throws -> String { try self.base.decode(type) }
        func decode(_ type: Double.Type) throws -> Double { try self.base.decode(type) }
        func decode(_ type: Float.Type) throws -> Float { try self.base.decode(type) }
        func decode(_ type: Int.Type) throws -> Int { try self.base.decode(type) }
        func decode(_ type: Int8.Type) throws -> Int8 { try self.base.decode(type) }
        func decode(_ type: Int16.Type) throws -> Int16 { try self.base.decode(type) }
        func decode(_ type: Int32.Type) throws -> Int32 { try self.base.decode(type) }
        func decode(_ type: Int64.Type) throws -> Int64 { try self.base.decode(type) }
        func decode(_ type: UInt.Type) throws -> UInt { try self.base.decode(type) }
        func decode(_ type: UInt8.Type) throws -> UInt8 { try self.base.decode(type) }
        func decode(_ type: UInt16.Type) throws -> UInt16 { try self.base.decode(type) }
        func decode(_ type: UInt32.Type) throws -> UInt32 { try self.base.decode(type) }
        func decode(_ type: UInt64.Type) throws -> UInt64 { try self.base.decode(type) }

        func decode<T: Decodable>(_ type: T.Type) throws -> T {
            // the CBOR decoder reads Data and Date itself, so they are not wrapped
            if type == Data.self || type == Date.self {
                return try self.base.decode(type)
            }
            return try self.base.decode(DecodingBox<T>.self).value
        }
    }
}
