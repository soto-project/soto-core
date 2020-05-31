//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO
import NIOHTTP1

public enum RetryStatus {
    case retry(wait: TimeAmount)
    case dontRetry
}

/// Protocol for Retry strategy. Has function returning amount of time before the next retry after an HTTP error
public protocol RetryPolicy {
    /// Returns whether we should retry (nil means don't) and how long we should wait before retrying
    /// - Parameters:
    ///   - error: Error returned by HTTP client
    ///   - attempt: retry attempt number
    func getRetryWaitTime(error: Error, attempt: Int) -> RetryStatus?
}

/// Retry controller that never returns a retry wait time
public struct NoRetry: RetryPolicy {
    public init() {}
    public func getRetryWaitTime(error: Error, attempt: Int) -> RetryStatus? {
        return .dontRetry
    }
}

/// Protocol for standard retry response. Will attempt to retry on 5xx errors, 429 (tooManyRequests).
public protocol StandardRetryPolicy: RetryPolicy {
    var maxRetries: Int { get }
    func calculateRetryWaitTime(attempt: Int) -> TimeAmount
}

public extension StandardRetryPolicy {
    /// default version of getRetryWaitTime for StandardRetryController
    func getRetryWaitTime(error: Error, attempt: Int) -> RetryStatus? {
        guard attempt < maxRetries else { return .dontRetry }
        
        switch error {
        // server error or too many requests
        case AWSClient.InternalError.httpResponseError(let response):
            if (500...).contains(response.status.code) || response.status.code == 429 {
                return .retry(wait: calculateRetryWaitTime(attempt: attempt))
            }
            return .dontRetry
        default:
            return .dontRetry
        }
    }
}

/// Retry with an exponentially increasing wait time between wait times
public struct ExponentialRetry: StandardRetryPolicy {
    public let base: TimeAmount
    public let maxRetries: Int
    
    public init(base: TimeAmount = .seconds(1), maxRetries: Int = 4) {
        self.base = base
        self.maxRetries = maxRetries
    }
    
    public func calculateRetryWaitTime(attempt: Int) -> TimeAmount {
        let exp = Int64(exp2(Double(attempt)))
        return .nanoseconds(base.nanoseconds * exp)
    }
    
}

/// Exponential jitter retry. Instead of returning an exponentially increasing retry time it returns a jittered version. In a heavy load situation
/// where a large number of clients all hit the servers at the same time, jitter helps to smooth out the server response. See
/// https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/ for details.
public struct JitterRetry: StandardRetryPolicy {
    public let base: TimeAmount
    public let maxRetries: Int
    
    public init(base: TimeAmount = .seconds(1), maxRetries: Int = 4) {
        self.base = base
        self.maxRetries = maxRetries
    }
    
    public func calculateRetryWaitTime(attempt: Int) -> TimeAmount {
        let exp = Int64(exp2(Double(attempt)))
        return .nanoseconds(Int64.random(in: (base.nanoseconds * exp / 2)..<(base.nanoseconds * exp)))
    }
}

