//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
import Foundation
#if compiler(>=5.6)
@preconcurrency import NIOCore
#else
import NIOCore
#endif
import NIOHTTP1
import NIOPosix // Needed for NIOConnectionError

/// Creates a RetryPolicy for AWSClient to use
public struct RetryPolicyFactory {
    public let retryPolicy: RetryPolicy

    /// The default RetryPolicy returned by RetryPolicyFactory
    public static var `default`: RetryPolicyFactory { return .jitter() }

    /// Retry controller that never returns a retry wait time
    public static var noRetry: RetryPolicyFactory { return .init(retryPolicy: NoRetry()) }

    /// Retry with an exponentially increasing wait time between wait times
    public static func exponential(base: TimeAmount = .seconds(1), maxRetries: Int = 4) -> RetryPolicyFactory {
        return .init(retryPolicy: ExponentialRetry(base: base, maxRetries: maxRetries))
    }

    /// Exponential jitter retry. Instead of returning an exponentially increasing retry time it returns a jittered version. In a heavy load situation
    /// where a large number of clients all hit the servers at the same time, jitter helps to smooth out the server response. See
    /// https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/ for details.
    public static func jitter(base: TimeAmount = .seconds(1), maxRetries: Int = 4) -> RetryPolicyFactory {
        return .init(retryPolicy: JitterRetry(base: base, maxRetries: maxRetries))
    }
}

/// Return value for `RetryPolicy.getRetryWaitTime`. Either retry after time amount or don't retry
public enum RetryStatus {
    /// retry after `wait` time amount
    case retry(wait: TimeAmount)
    /// do not retry
    case dontRetry
}

/// Protocol for Retry strategy. Has function returning amount of time before the next retry after an HTTP error
public protocol RetryPolicy: _SotoSendableProtocol {
    /// Returns whether we should retry and how long we should wait before retrying
    /// - Parameters:
    ///   - error: Error returned by HTTP client
    ///   - attempt: retry attempt number
    func getRetryWaitTime(error: Error, attempt: Int) -> RetryStatus?
}

/// Retry controller that never returns a retry wait time
private struct NoRetry: RetryPolicy {
    init() {}
    func getRetryWaitTime(error: Error, attempt: Int) -> RetryStatus? {
        return .dontRetry
    }
}

/// Protocol for standard retry response. Will attempt to retry on 5xx errors, 429 (tooManyRequests).
protocol StandardRetryPolicy: RetryPolicy {
    var maxRetries: Int { get }
    func calculateRetryWaitTime(attempt: Int) -> TimeAmount
}

extension StandardRetryPolicy {
    /// default version of getRetryWaitTime for StandardRetryController
    func getRetryWaitTime(error: Error, attempt: Int) -> RetryStatus? {
        guard attempt < maxRetries else { return .dontRetry }

        switch error {
        case let error as AWSErrorType:
            if let context = error.context {
                // if response has a "Retry-After" header then use that
                if let retryAfterString = context.headers["Retry-After"].first, let retryAfter = Int64(retryAfterString) {
                    return .retry(wait: .seconds(retryAfter))
                }
                // server error or too many requests
                if (500...).contains(context.responseCode.code) ||
                    context.responseCode.code == 429 ||
                    error.errorCode == AWSClientError.throttling.errorCode
                {
                    return .retry(wait: calculateRetryWaitTime(attempt: attempt))
                }
            }
            return .dontRetry
        #if DEBUG
        case let httpClientError as HTTPClientError where httpClientError == .remoteConnectionClosed:
            return .retry(wait: calculateRetryWaitTime(attempt: attempt))
        #endif
        default:
            return .dontRetry
        }
    }
}

/// Retry with an exponentially increasing wait time between wait times
struct ExponentialRetry: StandardRetryPolicy {
    let base: TimeAmount
    let maxRetries: Int

    init(base: TimeAmount = .seconds(1), maxRetries: Int = 4) {
        self.base = base
        self.maxRetries = maxRetries
    }

    func calculateRetryWaitTime(attempt: Int) -> TimeAmount {
        let exp = Int64(exp2(Double(attempt)))
        return .nanoseconds(self.base.nanoseconds * exp)
    }
}

/// Exponential jitter retry. Instead of returning an exponentially increasing retry time it returns a jittered version. In a heavy load situation
/// where a large number of clients all hit the servers at the same time, jitter helps to smooth out the server response. See
/// https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/ for details.
struct JitterRetry: StandardRetryPolicy {
    let base: TimeAmount
    let maxRetries: Int

    init(base: TimeAmount = .seconds(1), maxRetries: Int = 4) {
        self.base = base
        self.maxRetries = maxRetries
    }

    func calculateRetryWaitTime(attempt: Int) -> TimeAmount {
        let exp = Int64(exp2(Double(attempt)))
        return .nanoseconds(Int64.random(in: (self.base.nanoseconds * exp / 2)..<(self.base.nanoseconds * exp)))
    }
}
