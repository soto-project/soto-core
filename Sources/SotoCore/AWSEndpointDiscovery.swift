//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2021-2022 the Soto project authors
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
import Logging
import NIOConcurrencyHelpers
import NIOCore

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

/// Endpoint Storage attached to a Service
public struct AWSEndpointStorage: Sendable {
    let endpoint: ExpiringValue<String>

    // TODO: Initialise endpoint storage with an endpoint
    public init() {
        // Set endpoint to renew 3 minutes before it expires
        self.endpoint = .init(threshold: 3 * 60)
    }

    public func getValue(getExpiringValue: @escaping @Sendable () async throws -> (String, Date)) async throws -> String {
        try await self.endpoint.getValue(getExpiringValue: getExpiringValue)
    }
}

/// Helper object holding endpoint storage and closure used to discover endpoint
public struct AWSEndpointDiscovery: Sendable {
    let storage: AWSEndpointStorage
    let discover: @Sendable (Logger) async throws -> AWSEndpoints
    let isRequired: Bool

    public init(storage: AWSEndpointStorage, discover: @escaping @Sendable (Logger) async throws -> AWSEndpoints, required: Bool) {
        self.storage = storage
        self.discover = discover
        self.isRequired = required
    }

    func getEndpoint(logger: Logger) async throws -> String? {
        do {
            return try await self.storage.getValue {
                logger.trace("Request endpoint")
                do {
                    let response = try await discover(logger)
                    let index = Int.random(in: 0..<response.endpoints.count)
                    let endpoint = response.endpoints[index]
                    logger.trace("Received endpoint \(endpoint)")
                    return (endpoint.address, Date(timeIntervalSinceNow: TimeInterval(endpoint.cachePeriodInMinutes * 60)))
                } catch {
                    logger.debug("Error requesting endpoint", metadata: ["aws-error-message": "\(error)"])
                    throw error
                }
            }
        } catch {
            if !isRequired {
                return nil
            } else {
                throw error
            }
        }
    }
}
