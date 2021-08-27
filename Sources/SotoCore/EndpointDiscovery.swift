//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2021 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import struct Foundation.Date
import struct Foundation.TimeInterval
import NIO
import NIOConcurrencyHelpers

/// Endpoint list
public struct AWSEndpoints {
    public struct Endpoint {
        public init(address: String, cachePeriodInMinutes: Int64) {
            self.address = address
            self.cachePeriodInMinutes = cachePeriodInMinutes
        }

        /// An endpoint address.
        let address: String
        /// The TTL for the endpoint, in minutes.
        let cachePeriodInMinutes: Int64
    }

    public init(endpoints: [Endpoint]) {
        self.endpoints = endpoints
    }

    let endpoints: [Endpoint]
}

/// Class for storing Endpoint details
public class EndpointStorage {
    /// endpoint url
    public var endpoint: String
    /// when endpoint expires
    var expiration: Date
    /// promise for endpoint discovery process
    var promise: EventLoopPromise<String>?
    /// Lock access to class
    var lock = Lock()

    /// Initialize endpoint storage
    /// - Parameter endpoint: Initial endpoint to use
    public init(endpoint: String) {
        self.expiration = Date.distantPast
        self.endpoint = endpoint
    }

    /// Will endpoint expire within a certain time
    func isExpiring(within interval: TimeInterval) -> Bool {
        lock.withLock {
            return self.expiration.timeIntervalSinceNow < interval
        }
    }

    /// Get Endpoint from supplied closure, or wait on promise for Endpoint
    /// - Parameters:
    ///   - discover: Closure used to discover endpoint
    ///   - logger: Logger
    ///   - eventLoop: EventLoop to run process on
    /// - Returns: EventLoopFuture holding the endpoint
    func getEndpoint(
        discover: @escaping (Logger, EventLoop) -> EventLoopFuture<AWSEndpoints>,
        logger: Logger,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<String> {
        // lock access to class, until we exit the function
        lock.lock()
        defer { lock.unlock() }
        // if promise is nil then run supplied closure, otherwise wait on result of promise
        guard let promise = self.promise else {
            let promise = eventLoop.makePromise(of: String.self)
            let futureResult = discover(logger, eventLoop).map { response -> String in
                let index = Int.random(in: 0..<response.endpoints.count)
                let endpoint = response.endpoints[index]
                self.lock.withLockVoid {
                    self.endpoint = endpoint.address
                    self.expiration = Date(timeIntervalSinceNow: TimeInterval(endpoint.cachePeriodInMinutes * 60))
                    self.promise = nil
                }
                return response.endpoints[0].address
            }
            self.promise = promise
            futureResult.cascade(to: promise)
            return futureResult
        }
        return promise.futureResult
    }
}

/// Helper object holding endpoint storage and closure used to discover endpoint
public struct EndpointDiscovery {
    let storage: EndpointStorage
    let discover: (Logger, EventLoop) -> EventLoopFuture<AWSEndpoints>
    let isRequired: Bool
    var endpoint: String? { storage.endpoint }

    public init(storage: EndpointStorage, discover: @escaping (Logger, EventLoop) -> EventLoopFuture<AWSEndpoints>, required: Bool) {
        self.storage = storage
        self.discover = discover
        self.isRequired = required
    }

    /// Will endpoint expire within a certain time
    func isExpiring(within interval: TimeInterval) -> Bool {
        return self.storage.expiration.timeIntervalSinceNow < interval
    }

    func getEndpoint(logger: Logger, on eventLoop: EventLoop) -> EventLoopFuture<String> {
        return self.storage.getEndpoint(discover: self.discover, logger: logger, on: eventLoop)
    }
}
