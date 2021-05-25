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

import Dispatch
import Foundation
import NIO

extension AWSClient {
    public enum WaiterState {
        case success
        case retry
        case failure
    }

    public struct Waiter<Input, Output> {
        public struct Acceptor {
            public init(state: AWSClient.WaiterState, matcher: AWSMatcher) {
                self.state = state
                self.matcher = matcher
            }
            
            let state: WaiterState
            let matcher: AWSMatcher
        }
        
        public init(
            acceptors: [AWSClient.Waiter<Input, Output>.Acceptor],
            minDelayTime: TimeAmount = .seconds(2),
            maxDelayTime: TimeAmount = .seconds(120),
            maxRetryAttempts: Int,
            command: @escaping (Input, Logger, EventLoop?
        ) -> EventLoopFuture<Output>) {
            self.acceptors = acceptors
            self.minDelayTime = minDelayTime
            self.maxDelayTime = maxDelayTime
            self.maxRetryAttempts = maxRetryAttempts
            self.command = command
        }
        
        let acceptors: [Acceptor]
        let minDelayTime: TimeAmount
        let maxDelayTime: TimeAmount
        let maxRetryAttempts: Int
        let command: (Input, Logger, EventLoop?) -> EventLoopFuture<Output>
                
        func calculateRetryWaitTime(attempt: Int, remainingTime: TimeAmount) -> TimeAmount {
            let minDelay: Double = Double(self.minDelayTime.nanoseconds) / 1_000_000_000
            let maxDelay: Double = Double(self.maxDelayTime.nanoseconds) / 1_000_000_000
            let attemptCeiling = (log(maxDelay / minDelay) / log(2)) + 1

            let calculatedMaxDelay: Double
            if Double(attempt) > attemptCeiling {
                calculatedMaxDelay = maxDelay
            } else {
                calculatedMaxDelay = minDelay * Double(1<<(attempt-1))
            }
            let delay = Double.random(in: minDelay...calculatedMaxDelay)
            let timeDelay = TimeAmount.nanoseconds(Int64(delay * 1_000_000_000))
            if remainingTime - timeDelay < minDelayTime {
                return remainingTime - minDelayTime
            }
            return timeDelay
        }
    }

    public func wait<Input, Output>(
        _ input: Input,
        waiter: Waiter<Input, Output>,
        maxWaitTime: TimeAmount,
        logger: Logger = AWSClient.loggingDisabled,
        on eventLoop: EventLoop? = nil
    ) -> EventLoopFuture<Void> {
        let deadline: NIODeadline = .now() + maxWaitTime
        let eventLoop = eventLoop ?? eventLoopGroup.next()
        let promise = eventLoop.makePromise(of: Void.self)

        func attempt(number: Int) {
            waiter.command(input, logger, eventLoop)
                .whenComplete { result in
                    var state: WaiterState? = nil
                    for acceptor in waiter.acceptors {
                        if acceptor.matcher.match(result: result.map { $0 }) {
                            state = acceptor.state
                            break
                        }
                    }
                    print(state)
                    switch state {
                    case .success:
                        promise.succeed(())
                    case .failure:
                        if case .failure(let error) = result {
                            promise.fail(error)
                        } else {
                            promise.fail(ClientError.waiterFailed)
                        }
                    case .retry:
                        let wait = waiter.calculateRetryWaitTime(attempt: number, remainingTime: deadline - .now())
                        logger.info("Wait \(wait.nanoseconds / 1_000_000)ms")
                        eventLoop.scheduleTask(in: wait) { attempt(number: number + 1) }
                    case .none:
                        if case .failure(let error) = result {
                            promise.fail(error)
                        } else {
                            let wait = waiter.calculateRetryWaitTime(attempt: number, remainingTime: deadline - .now())
                            logger.info("Wait \(wait.nanoseconds / 1_000_000)ms")
                            eventLoop.scheduleTask(in: wait) { attempt(number: number + 1) }
                        }
                    }
                }
        }
        attempt(number: 1)
        return promise.futureResult
    }

}
