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

import Foundation
import Logging
import NIOHTTP1
import SotoSignerV4

/// Middleware that runs an endpoint discovery function  to set service endpoint
/// prior to running operation
public struct EndpointDiscoveryMiddleware: AWSMiddlewareProtocol {
    let storage: AWSEndpointStorage
    let discover: @Sendable (Logger) async throws -> AWSEndpoints
    let isRequired: Bool

    public init(storage: AWSEndpointStorage, discover: @escaping @Sendable (Logger) async throws -> AWSEndpoints, required: Bool) {
        self.storage = storage
        self.discover = discover
        self.isRequired = required
    }

    public func handle(_ request: AWSHTTPRequest, context: AWSMiddlewareContext, next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse) async throws -> AWSHTTPResponse {
        let isEnabled = context.serviceConfig.options.contains(.enableEndpointDiscovery)
        guard isEnabled || self.isRequired else {
            return try await next(request, context)
        }
        if let endpoint = try await getEndpoint(logger: context.logger) {
            var request = request
            var path = request.url.path
            // add trailing "/" back if it was present
            if request.url.pathWithSlash.hasSuffix("/"), path != "/" {
                path += "/"
            }
            // add percent encoding back into path as converting from URL to String has removed it
            let percentEncodedUrlPath = self.urlEncodePath(path)
            var urlString = "\(endpoint)\(percentEncodedUrlPath)"
            if let query = request.url.query {
                urlString += "?\(query)"
            }
            request.url = URL(string: urlString)!
            return try await next(request, context)
        }
        return try await next(request, context)
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
            if !self.isRequired {
                return nil
            } else {
                throw error
            }
        }
    }

    let pathAllowedCharacters = CharacterSet.urlPathAllowed.subtracting(.init(charactersIn: "+@()&$=:,'!*"))
    /// percent encode path value.
    private func urlEncodePath(_ value: String) -> String {
        return value.addingPercentEncoding(withAllowedCharacters: self.pathAllowedCharacters) ?? value
    }
}
