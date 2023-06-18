//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2020-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import NIOCore
import NIOPosix

/// Holds a request or response payload.
///
/// A request payload can be in the form of either a ByteBuffer or a stream
/// function that will supply ByteBuffers to the HTTP client.
/// A response payload only comes in the form of a ByteBuffer
public struct AWSPayload {
    /// Internal enum
    enum Payload {
        case byteBuffer(ByteBuffer)
        case stream(StreamReader)
        case empty
    }

    internal let payload: Payload

    /// construct a payload from a ByteBuffer
    public static func byteBuffer(_ buffer: ByteBuffer) -> Self {
        return AWSPayload(payload: .byteBuffer(buffer))
    }

    /// construct a payload from a stream function. If you supply a size the stream function will be called repeated until you supply the number of bytes specified. If you
    /// don't supply a size the stream function will be called repeatedly until you supply an empty `ByteBuffer`
    public static func stream(
        size: Int? = nil,
        stream: @escaping StreamReadFunction
    ) -> Self {
        return AWSPayload(payload: .stream(ChunkedStreamReader(size: size, read: stream)))
    }

    /// construct an empty payload
    public static var empty: Self {
        return AWSPayload(payload: .empty)
    }

    /// Construct a payload from a Collection of UInt8
    public static func data<C: Collection>(_ data: C, byteBufferAllocator: ByteBufferAllocator = ByteBufferAllocator()) -> Self where C.Element == UInt8 {
        var byteBuffer = byteBufferAllocator.buffer(capacity: data.count)
        byteBuffer.writeBytes(data)
        return AWSPayload(payload: .byteBuffer(byteBuffer))
    }

    /// Construct a payload from a `String`
    public static func string(_ string: String, byteBufferAllocator: ByteBufferAllocator = ByteBufferAllocator()) -> Self {
        var byteBuffer = byteBufferAllocator.buffer(capacity: string.utf8.count)
        byteBuffer.writeString(string)
        return AWSPayload(payload: .byteBuffer(byteBuffer))
    }

    /// Construct a stream payload from a `NIOFileHandle`
    /// - Parameters:
    ///   - fileHandle: NIO file handle
    ///   - offset: optional offset into file. If not set it will use the current position in the file
    ///   - size: size of block to load from file
    ///   - fileIO: NonBlockingFileIO object
    ///   - byteBufferAllocator: ByteBufferAllocator used during request upload
    ///   - callback: Progress callback called during upload
    public static func fileHandle(
        _ fileHandle: NIOFileHandle,
        offset: Int? = nil,
        size: Int? = nil,
        fileIO: NonBlockingFileIO,
        byteBufferAllocator: ByteBufferAllocator = ByteBufferAllocator(),
        callback: @escaping (Int) throws -> Void = { _ in }
    ) -> Self {
        // use chunked reader buffer size to avoid allocating additional buffers when streaming data
        let blockSize = S3ChunkedStreamReader.bufferSize
        var leftToRead = size
        var readSoFar = 0
        let stream: StreamReadFunction = { eventLoop in
            // calculate how much data is left to read, if a file size was indicated
            var downloadSize = blockSize
            if let leftToRead2 = leftToRead {
                downloadSize = min(downloadSize, leftToRead2)
                leftToRead = leftToRead2 - downloadSize
            }
            do {
                try callback(readSoFar)
            } catch {
                return eventLoop.makeFailedFuture(error)
            }
            guard downloadSize > 0 else {
                return eventLoop.makeSucceededFuture(.end)
            }
            let futureByteBuffer: EventLoopFuture<ByteBuffer>
            // if file offset has been specified
            if let offset = offset {
                futureByteBuffer = fileIO.read(
                    fileHandle: fileHandle,
                    fromOffset: Int64(offset + readSoFar),
                    byteCount: downloadSize,
                    allocator: byteBufferAllocator,
                    eventLoop: eventLoop
                )
            } else {
                futureByteBuffer = fileIO.read(
                    fileHandle: fileHandle,
                    byteCount: downloadSize,
                    allocator: byteBufferAllocator,
                    eventLoop: eventLoop
                )
            }
            readSoFar += downloadSize
            return futureByteBuffer.map { byteBuffer in
                precondition(leftToRead == nil || byteBuffer.readableBytes == downloadSize, "File did not have enough data")
                if byteBuffer.readableBytes == 0 {
                    return .end
                } else {
                    return .byteBuffer(byteBuffer)
                }
            }
        }

        return AWSPayload(payload: .stream(ChunkedStreamReader(size: size.map { Int($0) }, read: stream)))
    }

    /// construct a payload from a stream reader object.
    internal static func streamReader(_ reader: StreamReader) -> Self {
        return AWSPayload(payload: .stream(reader))
    }

    /// Return the size of the payload. If the payload is a stream it is always possible to return a size
    public var size: Int? {
        switch self.payload {
        case .byteBuffer(let byteBuffer):
            return byteBuffer.readableBytes
        case .stream(let reader):
            return reader.size
        case .empty:
            return 0
        }
    }

    /// return payload as Data
    public func asData() -> Data? {
        switch self.payload {
        case .byteBuffer(let byteBuffer):
            return byteBuffer.getData(at: byteBuffer.readerIndex, length: byteBuffer.readableBytes, byteTransferStrategy: .noCopy)
        default:
            return nil
        }
    }

    /// return payload as String
    public func asString() -> String? {
        switch self.payload {
        case .byteBuffer(let byteBuffer):
            return byteBuffer.getString(at: byteBuffer.readerIndex, length: byteBuffer.readableBytes)
        default:
            return nil
        }
    }

    /// return payload as ByteBuffer
    public func asByteBuffer() -> ByteBuffer? {
        switch self.payload {
        case .byteBuffer(let byteBuffer):
            return byteBuffer
        default:
            return nil
        }
    }

    /// does payload consist of zero bytes
    public var isEmpty: Bool {
        switch self.payload {
        case .byteBuffer(let buffer):
            return buffer.readableBytes == 0
        case .stream:
            return false
        case .empty:
            return true
        }
    }
}

extension AWSPayload: Decodable {
    // AWSPayload has to conform to Decodable so I can add it to AWSShape objects (which conform to Decodable). But we don't want the
    // Encoder/Decoder ever to process a AWSPayload
    public init(from decoder: Decoder) throws {
        preconditionFailure("Cannot decode an AWSPayload")
    }
}

extension AWSPayload: Sendable {}
extension AWSPayload.Payload: Sendable {}
