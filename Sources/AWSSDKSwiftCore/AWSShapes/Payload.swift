//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import struct Foundation.Data
import NIO
import NIOFoundationCompat

public enum AWSPayload {

    case byteBuffer(ByteBuffer)
    case stream(size: Int, closure: (EventLoop)->EventLoopFuture<ByteBuffer>)

    public static func data(_ data: Data) -> Self {
        var byteBuffer = ByteBufferAllocator().buffer(capacity: data.count)
        byteBuffer.writeBytes(data)
        return .byteBuffer(byteBuffer)
    }

    /// Construct a payload from a String
    public static func string(_ string: String) -> Self {
        var byteBuffer = ByteBufferAllocator().buffer(capacity: string.utf8.count)
        byteBuffer.writeString(string)
        return .byteBuffer(byteBuffer)
    }

    var size: Int {
        switch self {
        case .byteBuffer(let byteBuffer):
            return byteBuffer.readableBytes
        case .stream(let size, _):
            return size
        }
    }

    /// return payload as Data
    public func asData() -> Data? {
        switch self {
        case .byteBuffer(let byteBuffer):
            return byteBuffer.getData(at: byteBuffer.readerIndex, length: byteBuffer.readableBytes, byteTransferStrategy: .noCopy)
        default:
            return nil
        }
    }

    /// return payload as String
    public func asString() -> String? {
        switch self {
        case .byteBuffer(let byteBuffer):
            return byteBuffer.getString(at: byteBuffer.readerIndex, length: byteBuffer.readableBytes, encoding: .utf8)
        default:
            return nil
        }
    }

    /// return payload as ByteBuffer
    public func asByteBuffer() -> ByteBuffer? {
        switch self {
        case .byteBuffer(let byteBuffer):
            return byteBuffer
        default:
            return nil
        }
    }
}

extension AWSPayload: Decodable {

    // AWSPayload has to comform to Decodable so I can add it to AWSShape objects (which conform to Decodable). But we don't want the
    // Encoder/Decoder ever to process a AWSPayload
    public init(from decoder: Decoder) throws {
        preconditionFailure("Cannot decode an AWSPayload")
    }
}
