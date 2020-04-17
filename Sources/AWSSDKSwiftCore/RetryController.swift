import NIO
import NIOHTTP1

/// Protocol for Retry controller. Returns amount of time before the next retry after an HTTP error
public protocol RetryController {
    /// Returns whether we should retry (nil means don't) and how long we should wait before retrying
    /// - Parameters:
    ///   - error: Error returned by HTTP client
    ///   - attempt: retry attempt number
    func getRetryWaitTime(error: Error, attempt: Int) -> TimeAmount?
}

/// Retry controller that never returns a retry wait time
public struct NoRetry: RetryController {
    public init() {}
    public func getRetryWaitTime(error: Error, attempt: Int) -> TimeAmount? {
        return nil
    }
}

/// Protocol for standard retry response. Will attempt to retry on 5xx errors, 429 (tooManyRequests).
public protocol StandardRetryController: RetryController {
    var maxRetries: Int { get }
    func calculateRetryWaitTime(attempt: Int) -> TimeAmount
}

public extension StandardRetryController {
    /// default version of getRetryWaitTime for StandardRetryController
    func getRetryWaitTime(error: Error, attempt: Int) -> TimeAmount? {
        guard attempt < maxRetries else { return nil }
        
        switch error {
        // server error or too many requests
        case AWSClient.InternalError.httpResponseError(let response):
            if (500...).contains(response.status.code) || response.status.code == 429 {
                return calculateRetryWaitTime(attempt: attempt)
            }
            return nil
        default:
            return nil
        }
    }
}

/// Retry with an exponentially increasing wait time between wait times
public struct ExponentialRetry: StandardRetryController {
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
public struct JitterRetry: StandardRetryController {
    public let base: TimeAmount
    public let maxRetries: Int
    
    public init(base: TimeAmount = .seconds(1), maxRetries: Int = 4) {
        self.base = base
        self.maxRetries = maxRetries
    }
    
    public func calculateRetryWaitTime(attempt: Int) -> TimeAmount {
        let exp = Int64(exp2(Double(attempt)))
        return .nanoseconds(Int64.random(in: 0..<(base.nanoseconds * exp)))
    }
}

