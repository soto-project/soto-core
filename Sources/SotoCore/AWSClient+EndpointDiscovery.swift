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

import NIO

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
        endpointDiscovery: EndpointDiscovery,
        logger: Logger = AWSClient.loggingDisabled,
        on eventLoop: EventLoop? = nil
    ) -> EventLoopFuture<Void> {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
        // get endpoint
        if endpointDiscovery.isExpiring(within: 5*60) {
            return endpointDiscovery.getEndpoint(logger: logger, on: eventLoop).flatMap { endpoint in
                return self.execute(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    serviceConfig: serviceConfig.with(patch: .init(endpoint: endpoint)),
                    logger: logger,
                    on: eventLoop
                )
            }
        } else {
            return self.execute(
                operation: operationName,
                path: path,
                httpMethod: httpMethod,
                serviceConfig: serviceConfig.with(patch: .init(endpoint: endpointDiscovery.endpoint)),
                logger: logger,
                on: eventLoop
            )
        }
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
    @discardableResult public func execute<Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        input: Input,
        hostPrefix: String? = nil,
        endpointDiscovery: EndpointDiscovery,
        logger: Logger = AWSClient.loggingDisabled,
        on eventLoop: EventLoop? = nil
    ) -> EventLoopFuture<Void> {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
        // get endpoint
        if endpointDiscovery.isExpiring(within: 5*60) {
            return endpointDiscovery.getEndpoint(logger: logger, on: eventLoop).flatMap { endpoint in
                return self.execute(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    serviceConfig: serviceConfig.with(patch: .init(endpoint: endpoint)),
                    input: input,
                    hostPrefix: hostPrefix,
                    logger: logger,
                    on: eventLoop
                )
            }
        } else {
            return self.execute(
                operation: operationName,
                path: path,
                httpMethod: httpMethod,
                serviceConfig: serviceConfig.with(patch: .init(endpoint: endpointDiscovery.endpoint)),
                input: input,
                hostPrefix: hostPrefix,
                logger: logger,
                on: eventLoop
            )
        }
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
    public func execute<Output: AWSDecodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        endpointDiscovery: EndpointDiscovery,
        logger: Logger = AWSClient.loggingDisabled,
        on eventLoop: EventLoop? = nil
    ) -> EventLoopFuture<Output> {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
        // get endpoint
        if endpointDiscovery.isExpiring(within: 5*60) {
            return endpointDiscovery.getEndpoint(logger: logger, on: eventLoop).flatMap { endpoint in
                return self.execute(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    serviceConfig: serviceConfig.with(patch: .init(endpoint: endpoint)),
                    logger: logger,
                    on: eventLoop
                )
            }
        } else {
            return self.execute(
                operation: operationName,
                path: path,
                httpMethod: httpMethod,
                serviceConfig: serviceConfig.with(patch: .init(endpoint: endpointDiscovery.endpoint)),
                logger: logger,
                on: eventLoop
            )
        }
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
        endpointDiscovery: EndpointDiscovery,
        logger: Logger = AWSClient.loggingDisabled,
        on eventLoop: EventLoop? = nil
    ) -> EventLoopFuture<Output> {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
        // get endpoint
        if endpointDiscovery.isExpiring(within: 5*60) {
            return endpointDiscovery.getEndpoint(logger: logger, on: eventLoop).flatMap { endpoint in
                return self.execute(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    serviceConfig: serviceConfig.with(patch: .init(endpoint: endpoint)),
                    input: input,
                    hostPrefix: hostPrefix,
                    logger: logger,
                    on: eventLoop
                )
            }
        } else {
            return self.execute(
                operation: operationName,
                path: path,
                httpMethod: httpMethod,
                serviceConfig: serviceConfig.with(patch: .init(endpoint: endpointDiscovery.endpoint)),
                input: input,
                hostPrefix: hostPrefix,
                logger: logger,
                on: eventLoop
            )
        }
    }
}
