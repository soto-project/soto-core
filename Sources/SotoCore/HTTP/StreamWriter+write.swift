//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
import NIO

extension AsyncHTTPClient.HTTPClient.Body.StreamWriter {
    /// write stream to StreamWriter
    func write(
        reader: StreamReader,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Void> {
        let promise = eventLoop.makePromise(of: Void.self)

        func _write(_ amountLeft: Int?) {
            // get byte buffer from closure, write to StreamWriter, if there are still bytes to write then call
            // _writeToStreamWriter again.
            reader.streamChunks(on: eventLoop)
                .map { byteBuffers -> Void in
                    // if no amount was set and no byte buffers are supppied then this is assumed to mean
                    // there will be no more data
                    if amountLeft == nil, byteBuffers.count == 0 {
                        promise.succeed(())
                        return
                    }
                    // calculate amount left to write
                    let newAmountLeft: Int?
                    if let amountLeft = amountLeft {
                        guard byteBuffers.count > 0 else {
                            promise.fail(AWSClient.ClientError.notEnoughData)
                            return
                        }
                        let bytesToWrite = byteBuffers.reduce(0) { $0 + $1.readableBytes }
                        newAmountLeft = amountLeft - bytesToWrite
                        guard newAmountLeft! >= 0 else {
                            promise.fail(AWSClient.ClientError.tooMuchData)
                            return
                        }
                    } else {
                        newAmountLeft = nil
                    }

                    // write all the chunks but the last.
                    byteBuffers.dropLast().forEach {
                        _ = self.write(.byteBuffer($0))
                    }
                    if let lastBuffer = byteBuffers.last {
                        // store EventLoopFuture of last byteBuffer
                        let writeFuture: EventLoopFuture<Void> = self.write(.byteBuffer(lastBuffer))
                        writeFuture.flatMap { () -> EventLoopFuture<Void> in
                            if let newAmountLeft = newAmountLeft {
                                if newAmountLeft == 0 {
                                    promise.succeed(())
                                } else if newAmountLeft < 0 {
                                    // should never reach here as HTTPClient throws HTTPClientError.bodyLengthMismatch
                                    promise.fail(AWSClient.ClientError.tooMuchData)
                                } else {
                                    _write(newAmountLeft)
                                }
                            } else {
                                _write(nil)
                            }
                            return promise.futureResult
                        }.cascadeFailure(to: promise)
                    } else {
                        _write(newAmountLeft)
                    }
                }.cascadeFailure(to: promise)
        }
        _write(reader.contentSize)

        return promise.futureResult
    }
}
