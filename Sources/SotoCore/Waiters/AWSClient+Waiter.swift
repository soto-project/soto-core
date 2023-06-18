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

import Dispatch
import Foundation
import NIOCore

// MARK: Waiters

extension AWSClient {
    /// Waiter state
    public enum WaiterState: Sendable {
        case success
        case retry
        case failure
    }

    /// A waiter is a client side abstraction used to poll a resource until a desired state is reached
    public struct Waiter<Input: Sendable, Output: Sendable>: Sendable {
        /// An acceptor checks the result of a call and can change the waiter state based on that result
        public struct Acceptor: Sendable {
            public init(state: AWSClient.WaiterState, matcher: AWSWaiterMatcher) {
                self.state = state
                self.matcher = matcher
            }

            let state: WaiterState
            let matcher: AWSWaiterMatcher
        }

        public typealias WaiterCommand = @Sendable (Input, Logger) async throws -> Output

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
            command: @escaping WaiterCommand
        ) {
            self.acceptors = acceptors
            self.minDelayTime = minDelayTime
            self.maxDelayTime = maxDelayTime
            self.command = command
        }

        let acceptors: [Acceptor]
        let minDelayTime: TimeAmount
        let maxDelayTime: TimeAmount
        let command: WaiterCommand

        /// Calculate delay until next API call. This calculation comes from the AWS Smithy documentation
        /// https://awslabs.github.io/smithy/1.0/spec/waiters.html#waiter-retries
        ///
        /// - Parameters:
        ///   - attempt: Attempt number (assumes this starts at 1)
        ///   - remainingTime: Remaining time available
        /// - Returns: Calculate retry time
        func calculateRetryWaitTime(attempt: Int, remainingTime: TimeAmount) -> TimeAmount {
            assert(attempt >= 1, "Attempt number cannot be less than 1")
            let minDelay = Double(self.minDelayTime.nanoseconds) / 1_000_000_000
            let maxDelay = Double(self.maxDelayTime.nanoseconds) / 1_000_000_000
            let attemptCeiling = (log(maxDelay / minDelay) / log(2)) + 1

            let calculatedMaxDelay: Double
            if Double(attempt) > attemptCeiling {
                calculatedMaxDelay = maxDelay
            } else {
                calculatedMaxDelay = minDelay * Double(1 << (attempt - 1))
            }
            let delay = Double.random(in: minDelay...calculatedMaxDelay)
            let timeDelay = TimeAmount.nanoseconds(Int64(delay * 1_000_000_000))
            if remainingTime - timeDelay < self.minDelayTime {
                return remainingTime - self.minDelayTime
            }
            return timeDelay
        }
    }
}
