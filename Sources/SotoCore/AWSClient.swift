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

import AsyncHTTPClient
import Atomics
import Dispatch
import Logging
import Metrics
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOTransportServices
import SotoSignerV4

import struct Foundation.URL
import struct Foundation.URLQueryItem

/// Client managing communication with AWS services
///
/// This is the workhorse of SotoCore. You provide it with a ``AWSShape`` Input object, it converts it to
/// ``AWSHTTPRequest`` which is then passed through a chain of middleware and then sent to AWS. When
/// the response from AWS is received if it is successful it is converted to a ``AWSHTTPResponse`` which is
/// then decoded to generate a ``AWSShape`` Output object. If it is not successful then `AWSClient` will
/// throw an ``AWSErrorType``.
public final class AWSClient: Sendable {
    // MARK: Member variables

    /// Default logger that logs nothing
    public static let loggingDisabled = Logger(label: "AWS-do-not-log", factory: { _ in SwiftLogNoOpLogHandler() })

    static let globalRequestID = ManagedAtomic<Int>(0)

    /// AWS credentials provider
    public let credentialProvider: CredentialProvider
    /// Middleware code to be applied to requests and responses
    public let middleware: AWSMiddlewareProtocol
    /// HTTP client used by AWSClient
    public let httpClient: AWSHTTPClient
    /// Logger used for non-request based output
    public let logger: Logger
    /// client options
    let options: Options

    internal let isShutdown = ManagedAtomic<Bool>(false)

    // MARK: Initialization

    /// Initialize an AWSClient struct
    /// - parameters:
    ///     - credentialProvider: An object that returns valid signing credentials for request signing.
    ///     - retryPolicy: Object returning whether retries should be attempted.
    ///         Possible options are `.default`, `.noRetry`, `.exponential` or `.jitter`.
    ///     - middleware: Chain of middlewares to apply to requests and responses
    ///     - options: Configuration flags
    ///     - httpClient: HTTPClient to use.
    ///     - logger: Logger used to log background AWSClient events
    public init(
        credentialProvider credentialProviderFactory: CredentialProviderFactory = .default,
        retryPolicy retryPolicyFactory: RetryPolicyFactory = .default,
        middleware: some AWSMiddlewareProtocol,
        options: Options = Options(),
        httpClient: AWSHTTPClient = HTTPClient.shared,
        logger: Logger = AWSClient.loggingDisabled
    ) {
        self.httpClient = httpClient
        let credentialProvider = credentialProviderFactory.createProvider(
            context: .init(
                httpClient: self.httpClient,
                logger: logger,
                options: options
            )
        )
        self.credentialProvider = credentialProvider
        self.middleware = AWSMiddlewareStack {
            middleware
            SigningMiddleware(credentialProvider: credentialProvider, algorithm: options.signingAlgorithm)
            RetryMiddleware(retryPolicy: retryPolicyFactory.retryPolicy)
            ErrorHandlingMiddleware(options: options)
        }
        self.logger = logger
        self.options = options
    }

    /// Initialize an AWSClient struct
    /// - parameters:
    ///     - credentialProvider: An object that returns valid signing credentials for request signing.
    ///     - retryPolicy: Object returning whether retries should be attempted.
    ///         Possible options are `.default`, `.noRetry`, `.exponential` or `.jitter`.
    ///     - options: Configuration flags
    ///     - httpClient: HTTPClient to use.
    ///     - logger: Logger used to log background AWSClient events
    public init(
        credentialProvider credentialProviderFactory: CredentialProviderFactory = .default,
        retryPolicy retryPolicyFactory: RetryPolicyFactory = .default,
        options: Options = Options(),
        httpClient: AWSHTTPClient = HTTPClient.shared,
        logger: Logger = AWSClient.loggingDisabled
    ) {
        self.httpClient = httpClient
        let credentialProvider = credentialProviderFactory.createProvider(
            context: .init(
                httpClient: self.httpClient,
                logger: logger,
                options: options
            )
        )
        self.credentialProvider = credentialProvider
        self.middleware = AWSMiddlewareStack {
            SigningMiddleware(credentialProvider: credentialProvider, algorithm: options.signingAlgorithm)
            RetryMiddleware(retryPolicy: retryPolicyFactory.retryPolicy)
            ErrorHandlingMiddleware(options: options)
        }
        self.logger = logger
        self.options = options
    }

    deinit {
        assert(
            self.isShutdown.load(ordering: .relaxed),
            "AWSClient not shut down before the deinit. Please call client.syncShutdown() when no longer needed."
        )
    }

    // MARK: API Calls

    /// Shutdown AWSClient asynchronously.
    ///
    /// Before an `AWSClient` is deleted you need to call this function or the synchronous
    /// version `syncShutdown` to do a clean shutdown of the client to clean up `CredentialProvider` tasks.
    public func shutdown() async throws {
        guard self.isShutdown.compareExchange(expected: false, desired: true, ordering: .relaxed).exchanged else {
            throw ClientError.alreadyShutdown
        }
        // shutdown credential provider ignoring any errors as credential provider that doesn't initialize
        // can cause the shutdown process to fail
        try? await self.credentialProvider.shutdown()
    }

    /// Shutdown client synchronously.
    ///
    /// Before an `AWSClient` is deleted you need to call this function or the async version `shutdown`
    /// to do a clean shutdown of the client.
    ///
    /// - Throws: AWSClient.ClientError.alreadyShutdown: You have already shutdown the client
    @available(*, noasync, message: "syncShutdown() can block indefinitely, prefer shutdown()", renamed: "shutdown()")
    public func syncShutdown() throws {
        let errorStorage: NIOLockedValueBox<Error?> = .init(nil)
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                try await self.shutdown()
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
            case invalidARN
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
        /// ARN provided to client is invalid
        public static var invalidARN: ClientError { .init(error: .invalidARN) }
    }

    /// Additional options
    public struct Options: Sendable {
        /// Signing method
        let signingAlgorithm: AWSSigner.Algorithm
        /// log level used for request logging
        let requestLogLevel: Logger.Level
        /// log level used for error logging
        let errorLogLevel: Logger.Level

        /// Initialize AWSClient.Options
        /// - Parameters:
        //    - requestLogLevel: Log level used for request logging
        //    - errorLogLevel: Log level used for error logging
        public init(
            requestLogLevel: Logger.Level = .debug,
            errorLogLevel: Logger.Level = .debug
        ) {
            self.signingAlgorithm = .sigV4
            self.requestLogLevel = requestLogLevel
            self.errorLogLevel = errorLogLevel
        }

        /// Initialize AWSClient.Options
        /// - Parameters:
        ///   - signingAlgorithm: Algorithm to use when signing requests
        //    - requestLogLevel: Log level used for request logging
        //    - errorLogLevel: Log level used for error logging
        public init(
            signingAlgorithm: AWSSigner.Algorithm,
            requestLogLevel: Logger.Level = .debug,
            errorLogLevel: Logger.Level = .debug
        ) {
            self.signingAlgorithm = signingAlgorithm
            self.requestLogLevel = requestLogLevel
            self.errorLogLevel = errorLogLevel
        }
    }
}

// MARK: API Calls

extension AWSClient {
    /// Execute a request with an input object and an empty response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS Service configuration
    ///     - input: Input object
    ///     - hostPrefix: String to prefix host name with
    ///     - logger: Logger to log request details to
    public func execute(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        input: some AWSEncodableShape,
        hostPrefix: String? = nil,
        logger: Logger = AWSClient.loggingDisabled
    ) async throws {
        try await self.execute(
            operation: operationName,
            createRequest: {
                try AWSHTTPRequest(
                    operation: operationName,
                    path: path,
                    method: httpMethod,
                    input: input,
                    hostPrefix: hostPrefix,
                    configuration: serviceConfig
                )
            },
            processResponse: { _ in },
            streaming: false,
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
        try await self.execute(
            operation: operationName,
            createRequest: {
                try AWSHTTPRequest(
                    operation: operationName,
                    path: path,
                    method: httpMethod,
                    configuration: serviceConfig
                )
            },
            processResponse: { _ in },
            streaming: false,
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
        try await self.execute(
            operation: operationName,
            createRequest: {
                try AWSHTTPRequest(
                    operation: operationName,
                    path: path,
                    method: httpMethod,
                    configuration: serviceConfig
                )
            },
            processResponse: { response in
                try await self.processResponse(
                    operation: operationName,
                    response: response,
                    serviceConfig: serviceConfig,
                    logger: logger
                )
            },
            streaming: Output._options.contains(.rawPayload),
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
    public func execute<Output: AWSDecodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        input: some AWSEncodableShape,
        hostPrefix: String? = nil,
        logger: Logger = AWSClient.loggingDisabled
    ) async throws -> Output {
        try await self.execute(
            operation: operationName,
            createRequest: {
                try AWSHTTPRequest(
                    operation: operationName,
                    path: path,
                    method: httpMethod,
                    input: input,
                    hostPrefix: hostPrefix,
                    configuration: serviceConfig
                )
            },
            processResponse: { response in
                try await self.processResponse(operation: operationName, response: response, serviceConfig: serviceConfig, logger: logger)
            },
            streaming: Output._options.contains(.rawPayload),
            config: serviceConfig,
            logger: logger
        )
    }

    /// internal version of execute
    internal func execute<Output>(
        operation operationName: String,
        createRequest: @escaping () throws -> AWSHTTPRequest,
        processResponse: @escaping (AWSHTTPResponse) async throws -> Output,
        streaming: Bool,
        config: AWSServiceConfig,
        logger: Logger = AWSClient.loggingDisabled
    ) async throws -> Output {
        let logger = logger.attachingRequestId(
            Self.globalRequestID.wrappingIncrementThenLoad(ordering: .relaxed),
            operation: operationName,
            service: config.serviceIdentifier
        )
        let dimensions: [(String, String)] = [("aws-service", config.serviceIdentifier), ("aws-operation", operationName)]
        let startTime = DispatchTime.now().uptimeNanoseconds

        Counter(label: "aws_requests_total", dimensions: dimensions).increment()
        logger.log(level: self.options.requestLogLevel, "AWS Request")
        do {
            let request = try createRequest()
            try Task.checkCancellation()
            // combine service and client middleware stacks
            let middlewareStack = config.middleware.map { AWSDynamicMiddlewareStack($0, self.middleware) } ?? self.middleware
            let credential = try await self.credentialProvider.getCredential(logger: logger)
            let middlewareContext = AWSMiddlewareContext(
                operation: operationName,
                serviceConfig: config,
                credential: StaticCredential(
                    accessKeyId: credential.accessKeyId,
                    secretAccessKey: credential.secretAccessKey,
                    sessionToken: credential.sessionToken
                ),
                logger: logger
            )
            // run middleware stack with httpClient execute at the end
            let response = try await middlewareStack.handle(request, context: middlewareContext) { request, _ in
                var response = try await self.httpClient.execute(request: request, timeout: config.timeout, logger: logger)
                if !streaming {
                    try await response.collateBody()
                }
                return response
            }
            logger.trace("AWS Response")
            // process response and return output type
            let output = try await processResponse(response)
            Metrics.Timer(
                label: "aws_request_duration",
                dimensions: dimensions,
                preferredDisplayUnit: .seconds
            ).recordNanoseconds(DispatchTime.now().uptimeNanoseconds - startTime)
            return output
        } catch {
            Counter(label: "aws_request_errors", dimensions: dimensions).increment()
            // AWSErrorTypes have already been logged
            if error as? AWSErrorType == nil {
                // log error message
                logger.error(
                    "AWSClient error",
                    metadata: [
                        "aws-error-message": "\(error)"
                    ]
                )
            }
            throw error
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
            service: serviceConfig.serviceIdentifier
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
            service: serviceConfig.serviceIdentifier
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
        return AWSSigner(
            credentials: credential,
            name: serviceConfig.signingName,
            region: serviceConfig.region.rawValue,
            algorithm: self.options.signingAlgorithm
        )
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
        try response.generateOutputShape(operation: operationName, serviceProtocol: serviceConfig.serviceProtocol)
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
        case .invalidARN:
            return "ARN provided to the client was invalid"
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
