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
        return try await self.waitUntil(input, waiter: waiter, maxWaitTime: maxWaitTime, logger: logger, on: eventLoop).get()
    }
}
