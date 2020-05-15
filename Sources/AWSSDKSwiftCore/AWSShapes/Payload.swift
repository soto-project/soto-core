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

/// Holds a request or response payload. A request payload can be in the form of either a ByteBuffer or a stream function that will supply ByteBuffers to the HTTP client.
/// A response payload only comes in the form of a ByteBuffer
public struct AWSPayload {
    
    /// Internal enum
    enum Payload {
        case byteBuffer(ByteBuffer)
        case stream(size: Int?, stream: (EventLoop)->EventLoopFuture<ByteBuffer>)
    }
    
    internal let payload: Payload
    
    /// construct a payload from a ByteBuffer
    public static func byteBuffer(_ buffer: ByteBuffer) -> Self {
        return AWSPayload(payload: .byteBuffer(buffer))
    }
    
    /// construct a payload from a stream function
    public static func stream(size: Int? = nil, stream: @escaping (EventLoop)->EventLoopFuture<ByteBuffer>) -> Self {
        return AWSPayload(payload: .stream(size: size, stream: stream))
    }
    
    /// Construct a payload from `Data`
    public static func data(_ data: Data) -> Self {
        var byteBuffer = ByteBufferAllocator().buffer(capacity: data.count)
        byteBuffer.writeBytes(data)
        return AWSPayload(payload: .byteBuffer(byteBuffer))
    }

    /// Construct a payload from a `String`
    public static func string(_ string: String) -> Self {
        var byteBuffer = ByteBufferAllocator().buffer(capacity: string.utf8.count)
        byteBuffer.writeString(string)
        return AWSPayload(payload: .byteBuffer(byteBuffer))
    }

    /// Construct a stream payload from a `NIOFileHandle`
    public static func fileHandle(_ fileHandle: NIOFileHandle, size: Int? = nil, fileIO: NonBlockingFileIO, byteBufferAllocator: ByteBufferAllocator = ByteBufferAllocator()) -> Self {
        let blockSize = 64*1024
        var leftToRead = size
        func stream(_ eventLoop: EventLoop) -> EventLoopFuture<ByteBuffer> {
            // calculate how much data is left to read, if a file size was indicated
            var blockSize = blockSize
            if let leftToRead2 = leftToRead {
                blockSize = min(blockSize, leftToRead2)
                leftToRead = leftToRead2 - blockSize
            }
            let futureByteBuffer = fileIO.read(fileHandle: fileHandle, byteCount: blockSize, allocator: byteBufferAllocator, eventLoop: eventLoop)
            
            if leftToRead != nil {
                return futureByteBuffer.map { byteBuffer in
                        precondition(byteBuffer.readableBytes == blockSize, "File did not have enough data")
                        return byteBuffer
                }
            }
            return futureByteBuffer
        }
        
        return AWSPayload(payload: .stream(size: size, stream: stream))
    }
    
    /// Return the size of the payload. If the payload is a stream it is always possible to return a size
    var size: Int? {
        switch payload {
        case .byteBuffer(let byteBuffer):
            return byteBuffer.readableBytes
        case .stream(let size, _):
            return size
        }
    }

    /// return payload as Data
    public func asData() -> Data? {
        switch payload {
        case .byteBuffer(let byteBuffer):
            return byteBuffer.getData(at: byteBuffer.readerIndex, length: byteBuffer.readableBytes, byteTransferStrategy: .noCopy)
        default:
            return nil
        }
    }

    /// return payload as String
    public func asString() -> String? {
        switch payload {
        case .byteBuffer(let byteBuffer):
            return byteBuffer.getString(at: byteBuffer.readerIndex, length: byteBuffer.readableBytes)
        default:
            return nil
        }
    }

    /// return payload as ByteBuffer
    public func asByteBuffer() -> ByteBuffer? {
        switch payload {
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
