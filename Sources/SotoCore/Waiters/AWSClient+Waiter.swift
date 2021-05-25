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

// MARK: Waiters

extension AWSClient {
    /// Waiter state
    public enum WaiterState {
        case success
        case retry
        case failure
    }

    /// A waiter is a client side abstraction used to poll a resource until a desired state is reached
    public struct Waiter<Input, Output> {
        /// An acceptor checks the result of a call and can change the waiter state based on that result
        public struct Acceptor {
            public init(state: AWSClient.WaiterState, matcher: AWSWaiterMatcher) {
                self.state = state
                self.matcher = matcher
            }
            
            let state: WaiterState
            let matcher: AWSWaiterMatcher
        }

        /// Initialize an waiter
        /// - Parameters:
        ///   - acceptors: List of acceptors
        ///   - minDelayTime: minimum amount of time to wait between API calls
        ///   - maxDelayTime: maximum amount of time to wait between API calls
        ///   - command: API call
        public init(
            acceptors: [AWSClient.Waiter<Input, Output>.Acceptor],
            minDelayTime: TimeAmount = .seconds(2),
            maxDelayTime: TimeAmount = .seconds(120),
            command: @escaping (Input, Logger, EventLoop?
        ) -> EventLoopFuture<Output>) {
            self.acceptors = acceptors
            self.minDelayTime = minDelayTime
            self.maxDelayTime = maxDelayTime
            self.command = command
        }
        
        let acceptors: [Acceptor]
        let minDelayTime: TimeAmount
        let maxDelayTime: TimeAmount
        let command: (Input, Logger, EventLoop?) -> EventLoopFuture<Output>

        /// calculate delay until next API call
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

    /// Return EventLoopFuture that will by fulfilled once waiter is done
    /// - Parameters:
    ///   - input: Input parameters
    ///   - waiter: Waiter to wait on
    ///   - maxWaitTime: Maximum amount of time to wait
    ///   - logger: Logger used to provide output
    ///   - eventLoop: EventLoop to run API calls on
    /// - Returns: EventLoopFuture that will be fulfilled once waiter has completed
    public func wait<Input, Output>(
        _ input: Input,
        waiter: Waiter<Input, Output>,
        maxWaitTime: TimeAmount = .seconds(120),
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
                    // if state has not been set then set it based on return of API call
                    let solidState: WaiterState
                    if let state = state {
                        solidState = state
                    } else if case .failure = result {
                        solidState = .failure
                    } else {
                        solidState = .retry
                    }
                    // based on state succeed, fail promise or retry
                    switch solidState {
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
                        if wait < .seconds(0) {
                            promise.fail(ClientError.waiterTimeout)
                        } else {
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
