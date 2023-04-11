//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension AWSPayload {
    /// Construct a stream payload from an `AsynSequence` of `ByteBuffers`
    /// - Parameters:
    ///   - seq: AsyncSequence providing ByteBuffers
    ///   - size: total size of sequence in bytes
    public static func asyncSequence<AsyncSeq: AsyncSequence & Sendable>(_ seq: AsyncSeq, size: Int?) -> Self where AsyncSeq.Element == ByteBuffer {
        // we can wrap the iterator in an unsafe transfer box because the stream function is only
        // ever called serially and will never be called concurrently
        let iteratorWrapper = UnsafeMutableTransferBox(seq.makeAsyncIterator())
        func stream(_ eventLoop: EventLoop) -> EventLoopFuture<StreamReaderResult> {
            let promise = eventLoop.makePromise(of: StreamReaderResult.self)
            promise.completeWithTask {
                try Task.checkCancellation()
                if let buffer = try await iteratorWrapper.wrappedValue.next() {
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
