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

#if compiler(>=5.5)

import _Concurrency
import _NIOConcurrency
import Logging
import NIO

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
extension AWSClient {
    /// Execute an empty request and return a future with the output object generated from the response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS service configuration used in request creation and signing
    ///     - endpointDiscovery: Endpoint discovery helper
    ///     - logger: Logger
    ///     - eventLoop: Optional EventLoop to run everything on
    /// - returns:
    ///     Future containing output object that completes when response is received
    public func execute(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        endpointDiscovery: AWSEndpointDiscovery,
        logger: Logger = AWSClient.loggingDisabled,
        on eventLoop: EventLoop? = nil
    ) async throws {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
        return try await self.execute(
            execute: { endpoint in
                return try await self.execute(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    serviceConfig: endpoint.map { serviceConfig.with(patch: .init(endpoint: $0)) } ?? serviceConfig,
                    logger: logger,
                    on: eventLoop
                )
            },
            isEnabled: serviceConfig.options.contains(.enableEndpointDiscovery),
            endpointDiscovery: endpointDiscovery,
            eventLoop: eventLoop,
            logger: logger
        )
    }

    /// Execute a request with an input object and return a future with the output object generated from the response
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
    ///     Future containing output object that completes when response is received
    public func execute<Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        input: Input,
        hostPrefix: String? = nil,
        endpointDiscovery: AWSEndpointDiscovery,
        logger: Logger = AWSClient.loggingDisabled,
        on eventLoop: EventLoop? = nil
    ) async throws {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
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
                    on: eventLoop
                )
            },
            isEnabled: serviceConfig.options.contains(.enableEndpointDiscovery),
            endpointDiscovery: endpointDiscovery,
            eventLoop: eventLoop,
            logger: logger
        )
    }

    /// Execute an empty request and return a future with the output object generated from the response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS service configuration used in request creation and signing
    ///     - endpointDiscovery: Endpoint discovery helper
    ///     - logger: Logger
    ///     - eventLoop: Optional EventLoop to run everything on
    /// - returns:
    ///     Future containing output object that completes when response is received
    @discardableResult public func execute<Output: AWSDecodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        endpointDiscovery: AWSEndpointDiscovery,
        logger: Logger = AWSClient.loggingDisabled,
        on eventLoop: EventLoop? = nil
    ) async throws -> Output {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
        return try await self.execute(
            execute: { endpoint in
                return try await self.execute(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    serviceConfig: endpoint.map { serviceConfig.with(patch: .init(endpoint: $0)) } ?? serviceConfig,
                    logger: logger,
                    on: eventLoop
                )
            },
            isEnabled: serviceConfig.options.contains(.enableEndpointDiscovery),
            endpointDiscovery: endpointDiscovery,
            eventLoop: eventLoop,
            logger: logger
        )
    }

    /// Execute a request with an input object and return a future with the output object generated from the response
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
    ///     Future containing output object that completes when response is received
    public func execute<Output: AWSDecodableShape, Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        input: Input,
        hostPrefix: String? = nil,
        endpointDiscovery: AWSEndpointDiscovery,
        logger: Logger = AWSClient.loggingDisabled,
        on eventLoop: EventLoop? = nil
    ) async throws -> Output {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
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
                    on: eventLoop
                )
            },
            isEnabled: serviceConfig.options.contains(.enableEndpointDiscovery),
            endpointDiscovery: endpointDiscovery,
            eventLoop: eventLoop,
            logger: logger
        )
    }

    /// Execute a request with an input object and return a future with the output object generated from the response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - input: Input object
    ///     - config: AWS service configuration used in request creation and signing
    ///     - context: additional context for call
    /// - returns:
    ///     Future containing output object that completes when response is received
    public func execute<Output: AWSDecodableShape, Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        input: Input,
        hostPrefix: String? = nil,
        endpointDiscovery: AWSEndpointDiscovery,
        logger: Logger = AWSClient.loggingDisabled,
        on eventLoop: EventLoop? = nil,
        stream: @escaping AWSHTTPClient.ResponseStream
    ) async throws -> Output {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
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
                    on: eventLoop,
                    stream: stream
                )
            },
            isEnabled: serviceConfig.options.contains(.enableEndpointDiscovery),
            endpointDiscovery: endpointDiscovery,
            eventLoop: eventLoop,
            logger: logger
        )
    }

    private func execute<Output>(
        execute: @escaping (String?) async throws -> Output,
        isEnabled: Bool,
        endpointDiscovery: AWSEndpointDiscovery,
        eventLoop: EventLoop,
        logger: Logger
    ) async throws -> Output {
        guard isEnabled || endpointDiscovery.isRequired else { return try await execute(nil) }
        // get endpoint
        if endpointDiscovery.isExpiring(within: 3 * 60) {
            do {
                let endpointTask = Task { () -> String in
                    logger.trace("Request endpoint")
                    let endpoint = try await endpointDiscovery.getEndpoint(logger: logger, on: eventLoop).get()
                    logger.trace("Received endpoint \(endpoint)")
                    return endpoint
                }
                if endpointDiscovery.isRequired {
                    let endpoint = try await endpointTask.value
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

#endif // compiler(>=5.5)
