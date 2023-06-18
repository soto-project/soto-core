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

import Logging
import NIOCore

extension AWSClient {
    /// Execute an empty request
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS service configuration used in request creation and signing
    ///     - endpointDiscovery: Endpoint discovery helper
    ///     - logger: Logger
    ///     - eventLoop: Optional EventLoop to run everything on
    public func execute(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        endpointDiscovery: AWSEndpointDiscovery,
        logger: Logger = AWSClient.loggingDisabled
    ) async throws {
        return try await self.execute(
            execute: { endpoint in
                return try await self.execute(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    serviceConfig: endpoint.map { serviceConfig.with(patch: .init(endpoint: $0)) } ?? serviceConfig,
                    logger: logger
                )
            },
            isEnabled: serviceConfig.options.contains(.enableEndpointDiscovery),
            endpointDiscovery: endpointDiscovery,
            logger: logger
        )
    }

    /// Execute a request with an input object
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS service configuration used in request creation and signing
    ///     - input: Input object
    ///     - hostPrefix: Prefix to append to host name
    ///     - endpointDiscovery: Endpoint discovery helper
    ///     - logger: Logger
    ///     - eventLoop: Optional EventLoop to run everything on
    public func execute<Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        input: Input,
        hostPrefix: String? = nil,
        endpointDiscovery: AWSEndpointDiscovery,
        logger: Logger = AWSClient.loggingDisabled
    ) async throws {
        return try await self.execute(
            execute: { endpoint in
                return try await self.execute(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    serviceConfig: endpoint.map { serviceConfig.with(patch: .init(endpoint: $0)) } ?? serviceConfig,
                    input: input,
                    hostPrefix: hostPrefix,
                    logger: logger
                )
            },
            isEnabled: serviceConfig.options.contains(.enableEndpointDiscovery),
            endpointDiscovery: endpointDiscovery,
            logger: logger
        )
    }

    /// Execute an empty request and return the output object generated from the response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS service configuration used in request creation and signing
    ///     - endpointDiscovery: Endpoint discovery helper
    ///     - logger: Logger
    ///     - eventLoop: Optional EventLoop to run everything on
    /// - returns:
    ///     Output object that completes when response is received
    @discardableResult public func execute<Output: AWSDecodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        endpointDiscovery: AWSEndpointDiscovery,
        logger: Logger = AWSClient.loggingDisabled
    ) async throws -> Output {
        return try await self.execute(
            execute: { endpoint in
                return try await self.execute(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    serviceConfig: endpoint.map { serviceConfig.with(patch: .init(endpoint: $0)) } ?? serviceConfig,
                    logger: logger
                )
            },
            isEnabled: serviceConfig.options.contains(.enableEndpointDiscovery),
            endpointDiscovery: endpointDiscovery,
            logger: logger
        )
    }

    /// Execute a request with an input object and return the output object generated from the response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS service configuration used in request creation and signing
    ///     - input: Input object
    ///     - hostPrefix: Prefix to append to host name
    ///     - endpointDiscovery: Endpoint discovery helper
    ///     - logger: Logger
    ///     - eventLoop: Optional EventLoop to run everything on
    /// - returns:
    ///     Output object that completes when response is received
    public func execute<Output: AWSDecodableShape, Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        input: Input,
        hostPrefix: String? = nil,
        endpointDiscovery: AWSEndpointDiscovery,
        logger: Logger = AWSClient.loggingDisabled
    ) async throws -> Output {
        return try await self.execute(
            execute: { endpoint in
                return try await self.execute(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    serviceConfig: endpoint.map { serviceConfig.with(patch: .init(endpoint: $0)) } ?? serviceConfig,
                    input: input,
                    hostPrefix: hostPrefix,
                    logger: logger
                )
            },
            isEnabled: serviceConfig.options.contains(.enableEndpointDiscovery),
            endpointDiscovery: endpointDiscovery,
            logger: logger
        )
    }

    /// Execute a request with an input object and return the output object generated from the response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS service configuration used in request creation and signing
    ///     - input: Input object
    ///     - hostPrefix: Prefix to append to host name
    ///     - endpointDiscovery: Endpoint discovery helper
    ///     - logger: Logger
    ///     - eventLoop: Optional EventLoop to run everything on
    ///     - stream: Closure to stream payload response into
    /// - returns:
    ///     Output object that completes when response is received
    public func execute<Output: AWSDecodableShape, Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        input: Input,
        hostPrefix: String? = nil,
        endpointDiscovery: AWSEndpointDiscovery,
        logger: Logger = AWSClient.loggingDisabled,
        stream: @escaping AWSResponseStream
    ) async throws -> Output {
        return try await self.execute(
            execute: { endpoint in
                return try await self.execute(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    serviceConfig: endpoint.map { serviceConfig.with(patch: .init(endpoint: $0)) } ?? serviceConfig,
                    input: input,
                    hostPrefix: hostPrefix,
                    logger: logger,
                    stream: stream
                )
            },
            isEnabled: serviceConfig.options.contains(.enableEndpointDiscovery),
            endpointDiscovery: endpointDiscovery,
            logger: logger
        )
    }

    private func execute<Output>(
        execute: @escaping (String?) async throws -> Output,
        isEnabled: Bool,
        endpointDiscovery: AWSEndpointDiscovery,
        logger: Logger
    ) async throws -> Output {
        guard isEnabled || endpointDiscovery.isRequired else { return try await execute(nil) }
        // get endpoint
        if endpointDiscovery.isExpiring(within: 3 * 60) {
            do {
                logger.trace("Request endpoint")
                let endpoint = try await endpointDiscovery.getEndpoint(logger: logger, on: self.eventLoopGroup.any()).get()
                logger.trace("Received endpoint \(endpoint)")

                if endpointDiscovery.isRequired {
                    return try await execute(endpoint)
                } else {
                    return try await execute(nil)
                }
            } catch {
                logger.debug("Error requesting endpoint", metadata: ["aws-error-message": "\(error)"])
                throw error
            }
        } else {
            return try await execute(endpointDiscovery.endpoint)
        }
    }
}
