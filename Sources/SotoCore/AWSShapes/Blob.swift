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

import Foundation
#if compiler(>=5.6)
@preconcurrency import NIOCore
#else
import NIOCore
#endif

public struct AWSBlob: _SotoSendable, Codable, Equatable {
    let buffer: ByteBuffer

    /// Initialise AWSBlob
    /// - Parameter buffer: buffer to wrap
    private init(buffer: ByteBuffer) {
        self.buffer = buffer
    }

    /// construct a blob from `ByteBuffer`
    public static func byteBuffer(_ byteBuffer: ByteBuffer) -> Self {
        return .init(buffer: byteBuffer)
    }

    /// Construct a blob from `Data`
    public static func data(_ data: Data, byteBufferAllocator: ByteBufferAllocator = ByteBufferAllocator()) -> Self {
        var byteBuffer = byteBufferAllocator.buffer(capacity: data.count)
        byteBuffer.writeBytes(data)
        return .init(buffer: byteBuffer)
    }

    /// Construct a blob from a `String`
    public static func string(_ string: String, byteBufferAllocator: ByteBufferAllocator = ByteBufferAllocator()) -> Self {
        var byteBuffer = byteBufferAllocator.buffer(capacity: string.utf8.count)
        byteBuffer.writeString(string)
        return .init(buffer: byteBuffer)
    }

    /// Codable decode
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let base64 = try container.decode(String.self)
        let data = try base64.base64decoded()
        var byteBuffer = ByteBufferAllocator().buffer(capacity: data.count)
        byteBuffer.writeBytes(data)
        self.buffer = byteBuffer
    }

    /// Codable encode
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let byteBufferView = self.buffer.readableBytesView
        let base64 = String(base64Encoding: byteBufferView)
        try container.encode(base64)
    }

    /// return blob as Data
    public func asData() -> Data? {
        return self.buffer.getData(at: self.buffer.readerIndex, length: self.buffer.readableBytes, byteTransferStrategy: .noCopy)
    }

    /// return blob as String
    public func asString() -> String? {
        return self.buffer.getString(at: self.buffer.readerIndex, length: self.buffer.readableBytes)
    }

    /// return blob as ByteBuffer
    public func asByteBuffer() -> ByteBuffer {
        return self.buffer
    }

    /// does blob consist of zero bytes
    public var isEmpty: Bool {
        return self.buffer.readableBytes == 0
    }
}
