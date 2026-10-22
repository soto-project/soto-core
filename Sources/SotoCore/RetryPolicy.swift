//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2020-2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
import HTTPTypes
import NIOCore
import NIOPosix  // Needed for NIOConnectionError

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Return value for `RetryPolicy.getRetryWaitTime`. Either retry after time amount or don't retry
public enum RetryStatus {
    /// retry after `wait` time amount
    case retry(wait: TimeAmount)
    /// do not retry
    case dontRetry
}

/// Protocol for Retry strategy. Has function returning amount of time before the next retry after an HTTP error
public protocol RetryPolicy: Sendable {
    /// Returns whether we should retry and how long we should wait before retrying
    /// - Parameters:
    ///   - error: Error returned by HTTP client
    ///   - attempt: retry attempt number
    func getRetryWaitTime(error: any Error, attempt: Int) -> RetryStatus?
}

/// Retry controller that never returns a retry wait time
public struct NoRetry: RetryPolicy {
    init() {}
    public func getRetryWaitTime(error: any Error, attempt: Int) -> RetryStatus? {
        .dontRetry
    }
}

extension RetryPolicy where Self == NoRetry {
    /// Retry controller that never returns a retry wait time
    public static var noRetry: NoRetry { NoRetry() }
}

/// Protocol for standard retry response. Will attempt to retry on 5xx errors, 429 (tooManyRequests).
protocol StandardRetryPolicy: RetryPolicy {
    var maxRetries: Int { get }
    func calculateRetryWaitTime(attempt: Int) -> TimeAmount
}

extension StandardRetryPolicy {
    /// default version of getRetryWaitTime for StandardRetryController
    public func getRetryWaitTime(error: any Error, attempt: Int) -> RetryStatus? {
        guard attempt < maxRetries else { return .dontRetry }

        switch error {
        case let error as any AWSErrorType:
            if let context = error.context {
                // if response has a "Retry-After" header then use that
                if let retryAfterString = context.response.headerFields[.retryAfter], let retryAfter = Int64(retryAfterString) {
                    return .retry(wait: .seconds(retryAfter))
                }
                // server error or too many requests
                if (500...).contains(context.response.status.code) || context.response.status == .tooManyRequests
                    || error.errorCode == AWSClientError.throttling.errorCode
                {
                    return .retry(wait: calculateRetryWaitTime(attempt: attempt))
                }
            }
            return .dontRetry
        case let httpClientError as HTTPClientError where httpClientError == .remoteConnectionClosed:
            return .retry(wait: calculateRetryWaitTime(attempt: attempt))
        case let channelError as ChannelError where channelError == .ioOnClosedChannel:
            return .retry(wait: calculateRetryWaitTime(attempt: attempt))
        default:
            return .dontRetry
        }
    }
}

/// Retry with an exponentially increasing wait time between wait times
public struct ExponentialRetry: StandardRetryPolicy {
    let base: TimeAmount
    let maxRetries: Int

    init(base: TimeAmount = .seconds(1), maxRetries: Int = 4) {
        self.base = base
        self.maxRetries = maxRetries
    }

    public func calculateRetryWaitTime(attempt: Int) -> TimeAmount {
        let exp = Int64(exp2(Double(attempt)))
        return .nanoseconds(self.base.nanoseconds * exp)
    }
}

extension RetryPolicy where Self == ExponentialRetry {
    /// Retry with an exponentially increasing wait time between wait times
    public static func exponential(base: TimeAmount = .seconds(1), maxRetries: Int = 4) -> ExponentialRetry {
        ExponentialRetry(base: base, maxRetries: maxRetries)
    }
}

/// Exponential jitter retry. Instead of returning an exponentially increasing retry time it returns a jittered version. In a heavy load situation
/// where a large number of clients all hit the servers at the same time, jitter helps to smooth out the server response. See
/// https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/ for details.
public struct JitterRetry: StandardRetryPolicy {
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

extension RetryPolicy where Self == JitterRetry {
    /// Exponential jitter retry. Instead of returning an exponentially increasing retry time it returns a jittered version. In a heavy load situation
    /// where a large number of clients all hit the servers at the same time, jitter helps to smooth out the server response. See
    /// https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/ for details.
    public static func jitter(base: TimeAmount = .seconds(1), maxRetries: Int = 4) -> JitterRetry {
        JitterRetry(base: base, maxRetries: maxRetries)
    }

    /// Default retry policy is to use exponential jitter retry. Instead of returning an exponentially increasing retry time it returns a jittered
    /// version. In a heavy load situation where a large number of clients all hit the servers at the same time, jitter helps to smooth out the server
    /// response. See https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/ for details.
    public static var `default`: JitterRetry {
        .jitter()
    }
}
