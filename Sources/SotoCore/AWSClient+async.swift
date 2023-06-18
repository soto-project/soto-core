//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Atomics
import Dispatch
import Foundation
import Logging
import Metrics
import NIOCore
import SotoSignerV4

extension AWSClient {
    /// Shutdown AWSClient asynchronously.
    ///
    /// Before an `AWSClient` is deleted you need to call this function or the synchronous
    /// version `syncShutdown` to do a clean shutdown of the client. It cleans up `CredentialProvider` tasks and shuts down
    /// the HTTP client if it was created by the `AWSClient`.
    public func shutdown() async throws {
        guard self.isShutdown.compareExchange(expected: false, desired: true, ordering: .relaxed).exchanged else {
            throw ClientError.alreadyShutdown
        }
        // shutdown credential provider ignoring any errors as credential provider that doesn't initialize
        // can cause the shutdown process to fail
        try? await self.credentialProvider.shutdown(on: self.eventLoopGroup.any()).get()
        // if httpClient was created by AWSClient then it is required to shutdown the httpClient.
        switch self.httpClientProvider {
        case .createNew, .createNewWithEventLoopGroup:
            do {
                try await self.httpClient.shutdown()
            } catch {
                self.clientLogger.log(level: self.options.errorLogLevel, "Error shutting down HTTP client", metadata: [
                    "aws-error": "\(error)",
                ])
                throw error
            }

        case .shared:
            return
        }
    }

    /// execute a request with an input object and an empty response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS Service configuration
    ///     - input: Input object
    ///     - hostPrefix: String to prefix host name with
    ///     - logger: Logger to log request details to
    public func execute<Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        input: Input,
        hostPrefix: String? = nil,
        logger: Logger = AWSClient.loggingDisabled
    ) async throws {
        return try await self.execute(
            operation: operationName,
            createRequest: {
                try AWSRequest(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    input: input,
                    hostPrefix: hostPrefix,
                    configuration: serviceConfig
                )
            },
            execute: { request, eventLoop, logger in
                return try await self.httpClient.execute(request: request, timeout: serviceConfig.timeout, on: eventLoop, logger: logger)
            },
            processResponse: { _ in
                return
            },
            config: serviceConfig,
            logger: logger
        )
    }

    /// Execute an empty request and an empty response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS Service configuration
    ///     - logger: Logger to log request details to
    public func execute(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        logger: Logger = AWSClient.loggingDisabled
    ) async throws {
        return try await self.execute(
            operation: operationName,
            createRequest: {
                try AWSRequest(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    configuration: serviceConfig
                )
            },
            execute: { request, eventLoop, logger in
                return try await self.httpClient.execute(request: request, timeout: serviceConfig.timeout, on: eventLoop, logger: logger)
            },
            processResponse: { _ in
                return
            },
            config: serviceConfig,
            logger: logger
        )
    }

    /// Execute an empty request and return the output object generated from the response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS Service configuration
    ///     - logger: Logger to log request details to
    /// - returns:
    ///     Output object that completes when response is received
    public func execute<Output: AWSDecodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        logger: Logger = AWSClient.loggingDisabled
    ) async throws -> Output {
        return try await self.execute(
            operation: operationName,
            createRequest: {
                try AWSRequest(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    configuration: serviceConfig
                )
            },
            execute: { request, eventLoop, logger in
                return try await self.httpClient.execute(request: request, timeout: serviceConfig.timeout, on: eventLoop, logger: logger)
            },
            processResponse: { response in
                return try self.validate(operation: operationName, response: response, serviceConfig: serviceConfig)
            },
            config: serviceConfig,
            logger: logger
        )
    }

    /// Execute a request with an input object and return the output object generated from the response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS Service configuration
    ///     - input: Input object
    ///     - hostPrefix: String to prefix host name with
    ///     - logger: Logger to log request details to
    /// - returns:
    ///     Output object that completes when response is received
    public func execute<Output: AWSDecodableShape, Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        input: Input,
        hostPrefix: String? = nil,
        logger: Logger = AWSClient.loggingDisabled
    ) async throws -> Output {
        return try await self.execute(
            operation: operationName,
            createRequest: {
                try AWSRequest(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    input: input,
                    hostPrefix: hostPrefix,
                    configuration: serviceConfig
                )
            },
            execute: { request, eventLoop, logger in
                return try await self.httpClient.execute(request: request, timeout: serviceConfig.timeout, on: eventLoop, logger: logger)
            },
            processResponse: { response in
                return try self.validate(operation: operationName, response: response, serviceConfig: serviceConfig)
            },
            config: serviceConfig,
            logger: logger
        )
    }

    /// Execute a request with an input object and return the output object generated from the response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS Service configuration
    ///     - input: Input object
    ///     - hostPrefix: String to prefix host name with
    ///     - logger: Logger to log request details to
    /// - returns:
    ///     Output object that completes when response is received
    public func execute<Output: AWSDecodableShape, Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        input: Input,
        hostPrefix: String? = nil,
        logger: Logger = AWSClient.loggingDisabled,
        stream: @escaping AWSResponseStream
    ) async throws -> Output {
        return try await self.execute(
            operation: operationName,
            createRequest: {
                try AWSRequest(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    input: input,
                    hostPrefix: hostPrefix,
                    configuration: serviceConfig
                )
            },
            execute: { request, eventLoop, logger in
                return try await self.httpClient.execute(request: request, timeout: serviceConfig.timeout, on: eventLoop, logger: logger, stream: stream)
            },
            processResponse: { response in
                return try self.validate(operation: operationName, response: response, serviceConfig: serviceConfig)
            },
            config: serviceConfig,
            logger: logger
        )
    }

    /// internal version of execute
    internal func execute<Output>(
        operation operationName: String,
        createRequest: @escaping () throws -> AWSRequest,
        execute: @escaping (AWSHTTPRequest, EventLoop, Logger) async throws -> AWSHTTPResponse,
        processResponse: @escaping (AWSHTTPResponse) throws -> Output,
        config: AWSServiceConfig,
        logger: Logger = AWSClient.loggingDisabled
    ) async throws -> Output {
        let logger = logger.attachingRequestId(
            Self.globalRequestID.wrappingIncrementThenLoad(ordering: .relaxed),
            operation: operationName,
            service: config.service
        )
        let eventLoop = self.eventLoopGroup.any()
        let dimensions: [(String, String)] = [("aws-service", config.service), ("aws-operation", operationName)]
        let startTime = DispatchTime.now().uptimeNanoseconds

        Counter(label: "aws_requests_total", dimensions: dimensions).increment()
        logger.log(level: self.options.requestLogLevel, "AWS Request")
        do {
            // get credentials
            let credential = try await credentialProvider.getCredential(on: eventLoop, logger: logger).get()
            // construct signer
            let signer = AWSSigner(credentials: credential, name: config.signingName, region: config.region.rawValue)
            // create request and sign with signer
            let awsRequest = try createRequest()
                .applyMiddlewares(config.middlewares + self.middlewares, config: config)
                .createHTTPRequest(signer: signer, serviceConfig: config)
            // send request to AWS and process result
            let streaming: Bool
            switch awsRequest.body.payload {
            case .stream:
                streaming = true
            default:
                streaming = false
            }
            try Task.checkCancellation()
            let response = try await self.invoke(
                with: config,
                eventLoop: eventLoop,
                logger: logger,
                request: { eventLoop in try await execute(awsRequest, eventLoop, logger) },
                processResponse: processResponse,
                streaming: streaming
            )
            logger.trace("AWS Response")
            Metrics.Timer(
                label: "aws_request_duration",
                dimensions: dimensions,
                preferredDisplayUnit: .seconds
            ).recordNanoseconds(DispatchTime.now().uptimeNanoseconds - startTime)
            return response
        } catch {
            Counter(label: "aws_request_errors", dimensions: dimensions).increment()
            // AWSErrorTypes have already been logged
            if error as? AWSErrorType == nil {
                // log error message
                logger.error("AWSClient error", metadata: [
                    "aws-error-message": "\(error)",
                ])
            }
            throw error
        }
    }

    func invoke<Output>(
        with serviceConfig: AWSServiceConfig,
        eventLoop: EventLoop,
        logger: Logger,
        request: @escaping (EventLoop) async throws -> AWSHTTPResponse,
        processResponse: @escaping (AWSHTTPResponse) throws -> Output,
        streaming: Bool
    ) async throws -> Output {
        var attempt = 0
        while true {
            do {
                let response = try await request(eventLoop)
                // if it returns an HTTP status code outside 2xx then throw an error
                guard (200..<300).contains(response.status.code) else {
                    throw self.createError(for: response, serviceConfig: serviceConfig, logger: logger)
                }
                let output = try processResponse(response)
                return output
            } catch {
                // if streaming and the error returned is an AWS error fail immediately. Do not attempt
                // to retry as the streaming function will not know you are retrying
                if streaming,
                   error is AWSErrorType || error is AWSRawError
                {
                    throw error
                }
                // If I get a retry wait time for this error then attempt to retry request
                if case .retry(let retryTime) = self.retryPolicy.getRetryWaitTime(error: error, attempt: attempt) {
                    logger.trace("Retrying request", metadata: [
                        "aws-retry-time": "\(Double(retryTime.nanoseconds) / 1_000_000_000)",
                    ])
                    try await Task.sleep(nanoseconds: UInt64(retryTime.nanoseconds))
                } else {
                    throw error
                }
            }
            attempt += 1
        }
    }

    /// Get credential used by client
    /// - Parameters:
    ///   - eventLoop: optional eventLoop to run operation on
    ///   - logger: optional logger to use
    /// - Returns: Credential
    public func getCredential(logger: Logger = AWSClient.loggingDisabled) async throws -> Credential {
        let eventLoop = self.eventLoopGroup.any()
        if let asyncCredentialProvider = self.credentialProvider as? AsyncCredentialProvider {
            return try await asyncCredentialProvider.getCredential(on: eventLoop, logger: logger)
        } else {
            return try await self.credentialProvider.getCredential(on: eventLoop, logger: logger).get()
        }
    }

    /// Generate a signed URL
    /// - parameters:
    ///     - url : URL to sign
    ///     - httpMethod: HTTP method to use (.GET, .PUT, .PUSH etc)
    ///     - httpHeaders: Headers that are to be used with this URL. Be sure to include these headers when you used the returned URL
    ///     - expires: How long before the signed URL expires
    ///     - serviceConfig: additional AWS service configuration used to sign the url
    ///     - logger: Logger to output to
    /// - returns:
    ///     A signed URL
    public func signURL(
        url: URL,
        httpMethod: HTTPMethod,
        headers: HTTPHeaders = HTTPHeaders(),
        expires: TimeAmount,
        serviceConfig: AWSServiceConfig,
        logger: Logger = AWSClient.loggingDisabled
    ) async throws -> URL {
        let logger = logger.attachingRequestId(
            Self.globalRequestID.wrappingIncrementThenLoad(ordering: .relaxed),
            operation: "signHeaders",
            service: serviceConfig.service
        )
        let signer = try await self.createSigner(serviceConfig: serviceConfig, logger: logger)
        guard let cleanURL = signer.processURL(url: url) else {
            throw AWSClient.ClientError.invalidURL
        }
        return signer.signURL(url: cleanURL, method: httpMethod, headers: headers, expires: expires)
    }

    /// Generate signed headers
    /// - parameters:
    ///     - url : URL to sign
    ///     - httpMethod: HTTP method to use (.GET, .PUT, .PUSH etc)
    ///     - httpHeaders: Headers that are to be used with this URL.
    ///     - body: Payload to sign as well. While it is unnecessary to provide the body for S3 other services may require it
    ///     - serviceConfig: additional AWS service configuration used to sign the url
    ///     - logger: Logger to output to
    /// - returns:
    ///     A set of signed headers that include the original headers supplied
    public func signHeaders(
        url: URL,
        httpMethod: HTTPMethod,
        headers: HTTPHeaders = HTTPHeaders(),
        body: AWSPayload,
        serviceConfig: AWSServiceConfig,
        logger: Logger = AWSClient.loggingDisabled
    ) async throws -> HTTPHeaders {
        let logger = logger.attachingRequestId(
            Self.globalRequestID.wrappingIncrementThenLoad(ordering: .relaxed),
            operation: "signHeaders",
            service: serviceConfig.service
        )
        let signer = try await self.createSigner(serviceConfig: serviceConfig, logger: logger)
        guard let cleanURL = signer.processURL(url: url) else {
            throw AWSClient.ClientError.invalidURL
        }
        let body: AWSSigner.BodyData? = body.asByteBuffer().map { .byteBuffer($0) }
        return signer.signHeaders(url: cleanURL, method: httpMethod, headers: headers, body: body)
    }

    func createSigner(serviceConfig: AWSServiceConfig, logger: Logger) async throws -> AWSSigner {
        let credential = try await credentialProvider.getCredential(on: eventLoopGroup.next(), logger: logger).get()
        return AWSSigner(credentials: credential, name: serviceConfig.signingName, region: serviceConfig.region.rawValue)
    }
}
