//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
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
            _ = reader.streamChunks(on: eventLoop)
                .map { (byteBuffers)->() in
                    // if no amount was set and no byte buffers are supppied then this is assumed to mean
                    // there will be no more data
                    if amountLeft == nil && byteBuffers.count == 0 {
                        if let endChunk = reader.endChunk() {
                            _ = self.write(.byteBuffer(endChunk)).map { _ in
                                promise.succeed(())
                            }.cascadeFailure(to: promise)
                        } else {
                            promise.succeed(())
                        }
                        return
                    }
                    // calculate amount left to write
                    let newAmountLeft: Int?
                    if let amountLeft = amountLeft {
                        let bytesToWrite = byteBuffers.reduce(0) { $0 + $1.readableBytes }
                        newAmountLeft = amountLeft - bytesToWrite
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
                        _ = writeFuture.flatMap { ()->EventLoopFuture<Void> in
                            if let newAmountLeft = newAmountLeft {
                                if newAmountLeft == 0 {
                                    promise.succeed(())
                                } else if newAmountLeft < 0 {
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

