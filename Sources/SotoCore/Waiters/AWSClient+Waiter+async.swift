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

import Logging
import NIOCore

extension AWSClient {
    /// Returns when waiter polling returns a success state
    /// or returns an error if the polling returns an error or timesout
    ///
    /// - Parameters:
    ///   - input: Input parameters
    ///   - waiter: Waiter to wait on
    ///   - maxWaitTime: Maximum amount of time to wait
    ///   - logger: Logger used to provide output
    ///   - eventLoop: EventLoop to run API calls on
    /// - Returns: EventLoopFuture that will be fulfilled once waiter has completed
    public func waitUntil<Input, Output>(
        _ input: Input,
        waiter: Waiter<Input, Output>,
        maxWaitTime: TimeAmount? = nil,
        logger: Logger = AWSClient.loggingDisabled,
        on eventLoop: EventLoop? = nil
    ) async throws {
        let maxWaitTime = maxWaitTime ?? waiter.maxDelayTime
        let deadline: NIODeadline = .now() + maxWaitTime

        var attempt = 0
        while true {
            attempt += 1
            let result: Result<Output, Error>
            do {
                result = try .success(await waiter.command(input, logger))
            } catch {
                result = .failure(error)
            }
            var acceptorState: WaiterState?
            for acceptor in waiter.acceptors {
                if acceptor.matcher.match(result: result.map { $0 }) {
                    acceptorState = acceptor.state
                    break
                }
            }
            // if state has not been set then set it based on return of API call
            let waiterState: WaiterState
            if let state = acceptorState {
                waiterState = state
            } else if case .failure = result {
                waiterState = .failure
            } else {
                waiterState = .retry
            }
            // based on state succeed, fail promise or retry
            switch waiterState {
            case .success:
                return
            case .failure:
                if case .failure(let error) = result {
                    throw error
                } else {
                    throw ClientError.waiterFailed
                }
            case .retry:
                let wait = waiter.calculateRetryWaitTime(attempt: attempt, remainingTime: deadline - .now())
                if wait < .seconds(0) {
                    throw ClientError.waiterTimeout
                } else {
                    logger.trace("Wait \(wait.nanoseconds / 1_000_000)ms")
                    try await Task.sleep(nanoseconds: UInt64(wait.nanoseconds))
                }
            }
        }
    }
}
