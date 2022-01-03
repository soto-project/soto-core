//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2021 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if compiler(>=5.5) && canImport(_Concurrency)

import NIOCore

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension AWSPayload {
    /// Construct a stream payload from an `AsynSequence` of `ByteBuffers`
    /// - Parameters:
    ///   - seq: AsyncSequence providing ByteBuffers
    ///   - size: total size of sequence in bytes
    public static func asyncSequence<AsyncSeq: AsyncSequence>(_ seq: AsyncSeq, size: Int?) -> Self where AsyncSeq.Element == ByteBuffer {
        func stream(_ eventLoop: EventLoop) -> EventLoopFuture<StreamReaderResult> {
            let promise = eventLoop.makePromise(of: StreamReaderResult.self)
            promise.completeWithTask {
                var iterator = seq.makeAsyncIterator()
                if let buffer = try await iterator.next() {
                    return .byteBuffer(buffer)
                } else {
                    return .end
                }
            }
            return promise.futureResult
        }
        return AWSPayload(
            payload: .stream(ChunkedStreamReader(size: size, read: stream))
        )
    }
}

#endif // compiler(>=5.5) && canImport(_Concurrency)
