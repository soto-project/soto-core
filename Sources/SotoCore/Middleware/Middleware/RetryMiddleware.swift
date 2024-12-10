//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Logging
import NIOHTTP1
import SotoSignerV4

/// Middleware that performs retries of the next middleware whenever it throws errors based on a retry policy
struct RetryMiddleware: AWSMiddlewareProtocol {
    @usableFromInline
    let retryPolicy: RetryPolicy

    @inlinable
    func handle(_ request: AWSHTTPRequest, context: AWSMiddlewareContext, next: AWSMiddlewareNextHandler) async throws -> AWSHTTPResponse {
        var attempt = 0
        while true {
            do {
                try Task.checkCancellation()
                return try await next(request, context)
            } catch {
                // If request is streaming then do not allow a retry
                if request.body.isStreaming {
                    throw error
                }
                // If I get a retry wait time for this error then attempt to retry request
                if case .retry(let retryTime) = self.retryPolicy.getRetryWaitTime(error: error, attempt: attempt) {
                    context.logger.trace(
                        "Retrying request",
                        metadata: [
                            "aws-retry-time": "\(Double(retryTime.nanoseconds) / 1_000_000_000)"
                        ]
                    )
                    try await Task.sleep(nanoseconds: UInt64(retryTime.nanoseconds))
                } else {
                    throw error
                }
            }
            attempt += 1
        }
    }
}
