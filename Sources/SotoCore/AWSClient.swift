//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
import Atomics
import Dispatch
import struct Foundation.URL
import struct Foundation.URLQueryItem
import Logging
import Metrics
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOTransportServices
import SotoSignerV4
import SotoXML

/// Client managing communication with AWS services
///
/// This is the workhorse of SotoCore. You provide it with a ``AWSShape`` Input object, it converts it to ``AWSRequest`` which is then converted
/// to a raw `HTTPClient` Request. This is then sent to AWS. When the response from AWS is received if it is successful it is converted to a ``AWSResponse``
/// which is then decoded to generate a ``AWSShape`` Output object. If it is not successful then `AWSClient` will throw an ``AWSErrorType``.
public final class AWSClient: Sendable {
    // MARK: Member variables

    /// Default logger that logs nothing
    public static let loggingDisabled = Logger(label: "AWS-do-not-log", factory: { _ in SwiftLogNoOpLogHandler() })

    static let globalRequestID = ManagedAtomic<Int>(0)

    /// AWS credentials provider
    public let credentialProvider: CredentialProvider
    /// Middleware code to be applied to requests and responses
    public let middlewares: [AWSServiceMiddleware]
    /// HTTP client used by AWSClient
    public let httpClient: HTTPClient
    /// Keeps a record of how we obtained the HTTP client
    let httpClientProvider: HTTPClientProvider
    /// EventLoopGroup used by AWSClient
    public var eventLoopGroup: EventLoopGroup { return httpClient.eventLoopGroup }
    /// Retry policy specifying what to do when a request fails
    public let retryPolicy: RetryPolicy
    /// Logger used for non-request based output
    let clientLogger: Logger
    /// client options
    let options: Options

    internal let isShutdown = ManagedAtomic<Bool>(false)

    // MARK: Initialization

    /// Initialize an AWSClient struct
    /// - parameters:
    ///     - credentialProvider: An object that returns valid signing credentials for request signing.
    ///     - retryPolicy: Object returning whether retries should be attempted.
    ///         Possible options are `.default`, `.noRetry`, `.exponential` or `.jitter`.
    ///     - middlewares: Array of middlewares to apply to requests and responses
    ///     - options: Configuration flags
    ///     - httpClientProvider: HTTPClient to use. Use `.createNew` if you want the client to manage its own HTTPClient.
    ///     - logger: Logger used to log background AWSClient events
    public init(
        credentialProvider credentialProviderFactory: CredentialProviderFactory = .default,
        retryPolicy retryPolicyFactory: RetryPolicyFactory = .default,
        middlewares: [AWSServiceMiddleware] = [],
        options: Options = Options(),
        httpClientProvider: HTTPClientProvider,
        logger clientLogger: Logger = AWSClient.loggingDisabled
    ) {
        // setup httpClient
        self.httpClientProvider = httpClientProvider
        switch httpClientProvider {
        case .shared(let providedHTTPClient):
            self.httpClient = providedHTTPClient
        case .createNewWithEventLoopGroup(let elg):
            self.httpClient = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .shared(elg), configuration: .init(timeout: .init(connect: .seconds(10))))
        case .createNew:
            self.httpClient = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .createNew, configuration: .init(timeout: .init(connect: .seconds(10))))
        }

        self.credentialProvider = credentialProviderFactory.createProvider(context: .init(
            httpClient: httpClient,
            logger: clientLogger,
            options: options
        ))

        self.middlewares = middlewares
        self.retryPolicy = retryPolicyFactory.retryPolicy
        self.clientLogger = clientLogger
        self.options = options
    }

    deinit {
        assert(self.isShutdown.load(ordering: .relaxed), "AWSClient not shut down before the deinit. Please call client.syncShutdown() when no longer needed.")
    }

    // MARK: API Calls

    /// Shutdown client synchronously.
    ///
    /// Before an `AWSClient` is deleted you need to call this function or the async version `shutdown`
    /// to do a clean shutdown of the client. It cleans up `CredentialProvider` tasks and shuts down the HTTP client if it was created by
    /// the `AWSClient`.
    ///
    /// - Throws: AWSClient.ClientError.alreadyShutdown: You have already shutdown the client
    @available(*, noasync, message: "syncShutdown() can block indefinitely, prefer shutdown()", renamed: "shutdown()")
    public func syncShutdown() throws {
        let errorStorage: NIOLockedValueBox<Error?> = .init(nil)
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                try await shutdown()
            } catch {
                errorStorage.withLockedValue { errorStorage in
                    errorStorage = error
                }
            }
            semaphore.signal()
        }
        semaphore.wait()
        try errorStorage.withLockedValue { errorStorage in
            if let error = errorStorage {
                throw error
            }
        }
    }

    // MARK: Member structs/enums

    /// Errors returned by `AWSClient` code
    public struct ClientError: Swift.Error, Equatable {
        enum Error {
            case alreadyShutdown
            case invalidURL
            case bodyLengthMismatch
            case waiterFailed
            case waiterTimeout
            case failedToAccessPayload
        }

        let error: Error

        /// client has already been shutdown
        public static var alreadyShutdown: ClientError { .init(error: .alreadyShutdown) }
        /// URL provided to client is invalid
        public static var invalidURL: ClientError { .init(error: .invalidURL) }
        /// Data supplied to the Request does not equal length indicated
        public static var bodyLengthMismatch: ClientError { .init(error: .bodyLengthMismatch) }
        /// Waiter failed, but without an error. ie a successful api call was an error
        public static var waiterFailed: ClientError { .init(error: .waiterFailed) }
        /// Waiter failed to complete in time alloted
        public static var waiterTimeout: ClientError { .init(error: .waiterTimeout) }
        /// Failed to access payload while building request
        public static var failedToAccessPayload: ClientError { .init(error: .failedToAccessPayload) }
    }

    /// Specifies how `HTTPClient` will be created and establishes lifecycle ownership.
    public enum HTTPClientProvider: Sendable {
        /// Use HTTPClient provided by the user. User is responsible for the lifecycle of the HTTPClient.
        case shared(HTTPClient)
        /// HTTPClient will be created by AWSClient using provided EventLoopGroup. When `shutdown` is called, created `HTTPClient`
        /// will be shut down as well.
        case createNewWithEventLoopGroup(EventLoopGroup)
        /// `HTTPClient` will be created by `AWSClient`. When `shutdown` is called, created `HTTPClient` will be shut down as well.
        case createNew
    }

    /// Additional options
    public struct Options: Sendable {
        /// log level used for request logging
        let requestLogLevel: Logger.Level
        /// log level used for error logging
        let errorLogLevel: Logger.Level

        /// Initialize AWSClient.Options
        /// - Parameter requestLogLevel:Log level used for request logging
        public init(
            requestLogLevel: Logger.Level = .debug,
            errorLogLevel: Logger.Level = .debug
        ) {
            self.requestLogLevel = requestLogLevel
            self.errorLogLevel = errorLogLevel
        }
    }
}

// MARK: API Calls

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
        try? await self.credentialProvider.shutdown()
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
            processResponse: { response in
                return try await self.processEmptyResponse(
                    operation: operationName,
                    response: response,
                    serviceConfig: serviceConfig,
                    logger: logger
                )
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
            processResponse: { response in
                return try await self.processEmptyResponse(
                    operation: operationName,
                    response: response,
                    serviceConfig: serviceConfig,
                    logger: logger
                )
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
            processResponse: { response in
                return try await self.processResponse(
                    operation: operationName,
                    response: response,
                    serviceConfig: serviceConfig,
                    logger: logger
                )
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
            processResponse: { response in
                return try await self.processResponse(operation: operationName, response: response, serviceConfig: serviceConfig, logger: logger)
            },
            config: serviceConfig,
            logger: logger
        )
    }

    /// internal version of execute
    internal func execute<Output>(
        operation operationName: String,
        createRequest: @escaping () throws -> AWSRequest,
        processResponse: @escaping (AWSHTTPResponse) async throws -> Output,
        config: AWSServiceConfig,
        logger: Logger = AWSClient.loggingDisabled
    ) async throws -> Output {
        let logger = logger.attachingRequestId(
            Self.globalRequestID.wrappingIncrementThenLoad(ordering: .relaxed),
            operation: operationName,
            service: config.service
        )
        let dimensions: [(String, String)] = [("aws-service", config.service), ("aws-operation", operationName)]
        let startTime = DispatchTime.now().uptimeNanoseconds

        Counter(label: "aws_requests_total", dimensions: dimensions).increment()
        logger.log(level: self.options.requestLogLevel, "AWS Request")
        do {
            // get credentials
            let credential = try await credentialProvider.getCredential(logger: logger)
            // construct signer
            let signer = AWSSigner(credentials: credential, name: config.signingName, region: config.region.rawValue)
            // create request and sign with signer
            let awsRequest = try createRequest()
                .applyMiddlewares(config.middlewares + self.middlewares, config: config)
                .createHTTPRequest(signer: signer, serviceConfig: config)
            // send request to AWS and process result
            let streaming = awsRequest.body.isStreaming
            try Task.checkCancellation()
            let response = try await self.invoke(
                request: awsRequest,
                with: config,
                logger: logger,
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
        request: AWSHTTPRequest,
        with serviceConfig: AWSServiceConfig,
        logger: Logger,
        processResponse: @escaping (AWSHTTPResponse) async throws -> Output,
        streaming: Bool
    ) async throws -> Output {
        var attempt = 0
        while true {
            do {
                let response = try await self.httpClient.execute(request: request, timeout: serviceConfig.timeout, logger: logger)
                let output = try await processResponse(response)
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
    ///   - logger: optional logger to use
    /// - Returns: Credential
    public func getCredential(logger: Logger = AWSClient.loggingDisabled) async throws -> Credential {
        try await self.credentialProvider.getCredential(logger: logger)
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
    ///     - headers: Headers that are to be used with this URL.
    ///     - body: Payload to sign as well. While it is unnecessary to provide the body for S3 other services may require it
    ///     - serviceConfig: additional AWS service configuration used to sign the url
    ///     - logger: Logger to output to
    /// - returns:
    ///     A set of signed headers that include the original headers supplied
    public func signHeaders(
        url: URL,
        httpMethod: HTTPMethod,
        headers: HTTPHeaders = HTTPHeaders(),
        body: AWSHTTPBody,
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
        let bodyData: AWSSigner.BodyData?
        switch body.storage {
        case .byteBuffer(let buffer):
            bodyData = .byteBuffer(buffer)
        case .asyncSequence:
            bodyData = nil
        }
        return signer.signHeaders(url: cleanURL, method: httpMethod, headers: headers, body: bodyData)
    }

    func createSigner(serviceConfig: AWSServiceConfig, logger: Logger) async throws -> AWSSigner {
        let credential = try await credentialProvider.getCredential(logger: logger)
        return AWSSigner(credentials: credential, name: serviceConfig.signingName, region: serviceConfig.region.rawValue)
    }
}

// response validator
extension AWSClient {
    /// Generate an AWS Response from  the operation HTTP response and return the output shape from it. This is only every called if the response includes a successful http status code
    internal func processResponse<Output: AWSDecodableShape>(
        operation operationName: String,
        response: AWSHTTPResponse,
        serviceConfig: AWSServiceConfig,
        logger: Logger
    ) async throws -> Output {
        // if it returns an HTTP status code outside 2xx then throw an error
        guard (200..<300).contains(response.status.code) else {
            let error = await self.createError(for: response, serviceConfig: serviceConfig, logger: logger)
            throw error
        }

        let raw = Output._options.contains(.rawPayload) == true
        let awsResponse = try await AWSResponse(from: response, streaming: raw)
            .applyMiddlewares(serviceConfig.middlewares + middlewares, config: serviceConfig)

        return try awsResponse.generateOutputShape(operation: operationName, serviceProtocol: serviceConfig.serviceProtocol)
    }

    /// Generate an AWS Response from  the operation HTTP response and return the output shape from it. This is only every called if the response includes a successful http status code
    internal func processEmptyResponse(
        operation operationName: String,
        response: AWSHTTPResponse,
        serviceConfig: AWSServiceConfig,
        logger: Logger
    ) async throws {
        // if it returns an HTTP status code outside 2xx then throw an error
        guard (200..<300).contains(response.status.code) else {
            let error = await self.createError(for: response, serviceConfig: serviceConfig, logger: logger)
            throw error
        }

        // flush response body contents to complete response read
        for try await _ in response.body {}
    }

    /// Create error from HTTPResponse. This is only called if we received an unsuccessful http status code.
    internal func createError(for response: AWSHTTPResponse, serviceConfig: AWSServiceConfig, logger: Logger) async -> Error {
        // if we can create an AWSResponse and create an error from it return that
        let awsResponse: AWSResponse
        do {
            awsResponse = try await AWSResponse(from: response, streaming: false)
        } catch {
            // else return "Unhandled error message" with rawBody attached
            let context = AWSErrorContext(
                message: "Unhandled Error",
                responseCode: response.status,
                headers: response.headers
            )
            return AWSRawError(rawBody: nil, context: context)
        }
        do {
            let awsResponseWithMiddleware = try awsResponse.applyMiddlewares(serviceConfig.middlewares + middlewares, config: serviceConfig)
            if let error = awsResponseWithMiddleware.generateError(
                serviceConfig: serviceConfig,
                logLevel: options.errorLogLevel,
                logger: logger
            ) {
                return error
            } else {
                // else return "Unhandled error message" with rawBody attached
                let context = AWSErrorContext(
                    message: "Unhandled Error",
                    responseCode: response.status,
                    headers: response.headers
                )
                let responseBody: String?
                switch awsResponseWithMiddleware.body.storage {
                case .byteBuffer(let buffer):
                    responseBody = String(buffer: buffer)
                default:
                    responseBody = nil
                }
                return AWSRawError(rawBody: responseBody, context: context)
            }
        } catch {
            return error
        }
    }
}

extension AWSClient.ClientError: CustomStringConvertible {
    /// return human readable description of error
    public var description: String {
        switch error {
        case .alreadyShutdown:
            return "The AWSClient is already shutdown"
        case .invalidURL:
            return """
            The request url is invalid format.
            This error is internal. So please make a issue on https://github.com/soto-project/soto/issues to solve it.
            """
        case .bodyLengthMismatch:
            return "You have supplied the incorrect amount of data for the Request."
        case .waiterFailed:
            return "Waiter failed"
        case .waiterTimeout:
            return "Waiter failed to complete in time allocated"
        case .failedToAccessPayload:
            return "Failed to access payload while building request for AWS"
        }
    }
}

extension Logger {
    func attachingRequestId(_ id: Int, operation: String, service: String) -> Logger {
        var logger = self
        logger[metadataKey: "aws-service"] = .string(service)
        logger[metadataKey: "aws-operation"] = .string(operation)
        logger[metadataKey: "aws-request-id"] = "\(id)"
        return logger
    }
}
