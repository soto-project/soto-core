//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
import BaggageContext
import Dispatch
import struct Foundation.URL
import struct Foundation.URLQueryItem
import Logging
import Metrics
import NIO
import NIOConcurrencyHelpers
import SotoSignerV4
import SotoXML

/// This is the workhorse of SotoCore. You provide it with a `AWSShape` Input object, it converts it to `AWSRequest` which is then converted
/// to a raw `HTTPClient` Request. This is then sent to AWS. When the response from AWS is received if it is successful it is converted to a `AWSResponse`
/// which is then decoded to generate a `AWSShape` Output object. If it is not successful then `AWSClient` will throw an `AWSErrorType`.
public final class AWSClient {
    /// Errors returned by AWSClient code
    public struct ClientError: Swift.Error, Equatable {
        enum Error {
            case alreadyShutdown
            case invalidURL
            case tooMuchData
        }

        let error: Error

        /// client has already been shutdown
        public static var alreadyShutdown: ClientError { .init(error: .alreadyShutdown) }
        /// URL provided to client is invalid
        public static var invalidURL: ClientError { .init(error: .invalidURL) }
        /// Too much data has been supplied for the Request
        public static var tooMuchData: ClientError { .init(error: .tooMuchData) }
    }

    public struct HTTPResponseError: Swift.Error {
        public let response: AWSHTTPResponse
    }

    /// Specifies how `HTTPClient` will be created and establishes lifecycle ownership.
    public enum HTTPClientProvider {
        /// HTTP Client will be provided by the user. Owner of this group is responsible for its lifecycle. Any HTTPClient that conforms to
        /// `AWSHTTPClient` can be specified here including AsyncHTTPClient
        case shared(AWSHTTPClient)
        /// HTTP Client will be created by the client. When `shutdown` is called, created `HTTPClient` will be shut down as well.
        case createNew
    }

    /// default logger that logs nothing
    public static let loggingDisabled = Logger(label: "AWS-do-not-log", factory: { _ in SwiftLogNoOpLogHandler() })
    /// default baggage context
    public static let emptyContext = DefaultContext.TODO(logger: loggingDisabled)

    static let globalRequestID = NIOAtomic<Int>.makeAtomic(value: 0)

    /// AWS credentials provider
    public let credentialProvider: CredentialProvider
    /// middleware code to be applied to requests and responses
    public let middlewares: [AWSServiceMiddleware]
    /// HTTP client used by AWSClient
    public let httpClient: AWSHTTPClient
    /// keeps a record of how we obtained the HTTP client
    let httpClientProvider: HTTPClientProvider
    /// EventLoopGroup used by AWSClient
    public var eventLoopGroup: EventLoopGroup { return httpClient.eventLoopGroup }
    /// Retry policy specifying what to do when a request fails
    public let retryPolicy: RetryPolicy
    /// Logger used for non-request based output
    let clientLogger: Logger

    private let isShutdown = NIOAtomic<Bool>.makeAtomic(value: false)

    /// Initialize an AWSClient struct
    /// - parameters:
    ///     - credentialProvider: An object that returns valid signing credentials for request signing.
    ///     - retryPolicy: Object returning whether retries should be attempted. Possible options are NoRetry(), ExponentialRetry() or JitterRetry()
    ///     - middlewares: Array of middlewares to apply to requests and responses
    ///     - httpClientProvider: HTTPClient to use. Use `.createNew` if you want the client to manage its own HTTPClient.
    ///     - logger: Logger used to log background AWSClient events
    public init(
        credentialProvider credentialProviderFactory: CredentialProviderFactory = .default,
        retryPolicy retryPolicyFactory: RetryPolicyFactory = .default,
        middlewares: [AWSServiceMiddleware] = [],
        httpClientProvider: HTTPClientProvider,
        logger clientLogger: Logger = AWSClient.loggingDisabled
    ) {
        // setup httpClient
        self.httpClientProvider = httpClientProvider
        switch httpClientProvider {
        case .shared(let providedHTTPClient):
            self.httpClient = providedHTTPClient
        case .createNew:
            self.httpClient = AWSClient.createHTTPClient()
        }

        self.credentialProvider = credentialProviderFactory.createProvider(context: .init(
            httpClient: httpClient,
            eventLoop: httpClient.eventLoopGroup.next(),
            logger: clientLogger
        ))

        self.middlewares = middlewares
        self.retryPolicy = retryPolicyFactory.retryPolicy
        self.clientLogger = clientLogger
    }

    deinit {
        assert(self.isShutdown.load(), "AWSClient not shut down before the deinit. Please call client.syncShutdown() when no longer needed.")
    }

    /// Shutdown client synchronously. Before an AWSClient is deleted you need to call this function or the async version `shutdown`
    /// to do a clean shutdown of the client. It cleans up CredentialProvider tasks and shuts down the HTTP client if it was created by this
    /// AWSClient.
    ///
    /// - Throws: AWSClient.ClientError.alreadyShutdown: You have already shutdown the client
    public func syncShutdown() throws {
        let errorStorageLock = Lock()
        var errorStorage: Error?
        let continuation = DispatchWorkItem {}
        self.shutdown(queue: DispatchQueue(label: "aws-client.shutdown")) { error in
            if let error = error {
                errorStorageLock.withLock {
                    errorStorage = error
                }
            }
            continuation.perform()
        }
        continuation.wait()
        try errorStorageLock.withLock {
            if let error = errorStorage {
                throw error
            }
        }
    }

    /// Shutdown AWSClient asynchronously. Before an AWSClient is deleted you need to call this function or the synchronous
    /// version `syncShutdown` to do a clean shutdown of the client. It cleans up CredentialProvider tasks and shuts down
    /// the HTTP client if it was created by this AWSClient. Given we could be destroying the EventLoopGroup the client
    /// uses, we have to use a DispatchQueue to run some of this work on.
    ///
    /// - Parameters:
    ///   - queue: Dispatch Queue to run shutdown on
    ///   - callback: Callback called when shutdown is complete. If there was an error it will return with Error in callback
    public func shutdown(queue: DispatchQueue = .global(), _ callback: @escaping (Error?) -> Void) {
        guard self.isShutdown.compareAndExchange(expected: false, desired: true) else {
            callback(ClientError.alreadyShutdown)
            return
        }
        let eventLoop = eventLoopGroup.next()
        // ignore errors from credential provider. Don't need shutdown erroring because no providers were available
        credentialProvider.shutdown(on: eventLoop).whenComplete { _ in
            // if httpClient was created by AWSClient then it is required to shutdown the httpClient.
            switch self.httpClientProvider {
            case .createNew:
                self.httpClient.shutdown(queue: queue) { error in
                    if let error = error {
                        self.clientLogger.error("Error shutting down HTTP client", metadata: [
                            "aws-error": "\(error)",
                        ])
                    }
                    callback(error)
                }

            case .shared:
                callback(nil)
            }
        }
    }
}

// invoker
extension AWSClient {
    fileprivate func invoke(with serviceConfig: AWSServiceConfig, logger: Logger, _ request: @escaping () -> EventLoopFuture<AWSHTTPResponse>) -> EventLoopFuture<AWSHTTPResponse> {
        let eventloop = self.eventLoopGroup.next()
        let promise = eventloop.makePromise(of: AWSHTTPResponse.self)

        func execute(attempt: Int) {
            // execute HTTP request
            _ = request()
                .flatMapThrowing { (response) throws -> Void in
                    // if it returns an HTTP status code outside 2xx then throw an error
                    guard (200..<300).contains(response.status.code) else { throw HTTPResponseError(response: response) }
                    promise.succeed(response)
                }
                .flatMapErrorThrowing { (error) -> Void in
                    // If I get a retry wait time for this error then attempt to retry request
                    if case .retry(let retryTime) = self.retryPolicy.getRetryWaitTime(error: error, attempt: attempt) {
                        logger.info("Retrying request", metadata: [
                            "aws-retry-time": "\(Double(retryTime.nanoseconds) / 1_000_000_000)",
                        ])
                        // schedule task for retrying AWS request
                        eventloop.scheduleTask(in: retryTime) {
                            execute(attempt: attempt + 1)
                        }
                    } else if let responseError = error as? HTTPResponseError {
                        // if there was no retry and error was a response status code then attempt to convert to AWS error
                        promise.fail(self.createError(for: responseError.response, serviceConfig: serviceConfig, logger: logger))
                    } else {
                        promise.fail(error)
                    }
                }
        }

        execute(attempt: 0)

        return promise.futureResult
    }

    /// create HTTPClient
    fileprivate static func createHTTPClient() -> AWSHTTPClient {
        return AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .createNew)
    }
}

// public facing apis
extension AWSClient {
    /// execute a request with an input object and return a future with an empty response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS service configuration used in request creation and signing
    ///     - input: Input object
    ///     - context: Baggage context, holding a logger and baggage for tracing
    ///     - eventLoop: Eventloop to execute on
    /// - returns:
    ///     Empty Future that completes when response is received
    public func execute<Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        input: Input,
        context: Context = AWSClient.emptyContext,
        on eventLoop: EventLoop? = nil
    ) -> EventLoopFuture<Void> {
        return execute(
            operation: operationName,
            createRequest: {
                try AWSRequest(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    input: input,
                    configuration: serviceConfig
                )
            },
            execute: { request, eventLoop, context in
                return self.httpClient.execute(request: request, timeout: serviceConfig.timeout, on: eventLoop, context: context)
            },
            processResponse: { _ in
                return
            },
            config: serviceConfig,
            context: context,
            on: eventLoop
        )
    }

    /// execute an empty request and return a future with an empty response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS service configuration used in request creation and signing
    ///     - context: Baggage context, holding a logger and baggage for tracing
    ///     - eventLoop: Eventloop to execute on
    /// - returns:
    ///     Empty Future that completes when response is received
    public func execute(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        context: Context = AWSClient.emptyContext,
        on eventLoop: EventLoop? = nil
    ) -> EventLoopFuture<Void> {
        return execute(
            operation: operationName,
            createRequest: {
                try AWSRequest(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    configuration: serviceConfig
                )
            },
            execute: { request, eventLoop, context in
                return self.httpClient.execute(request: request, timeout: serviceConfig.timeout, on: eventLoop, context: context)
            },
            processResponse: { _ in
                return
            },
            config: serviceConfig,
            context: context,
            on: eventLoop
        )
    }

    /// execute an empty request and return a future with the output object generated from the response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS service configuration used in request creation and signing
    ///     - context: Baggage context, holding a logger and baggage for tracing
    ///     - eventLoop: Eventloop to execute on
    /// - returns:
    ///     Future containing output object that completes when response is received
    public func execute<Output: AWSDecodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        context: Context = AWSClient.emptyContext,
        on eventLoop: EventLoop? = nil
    ) -> EventLoopFuture<Output> {
        return execute(
            operation: operationName,
            createRequest: {
                try AWSRequest(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    configuration: serviceConfig
                )
            },
            execute: { request, eventLoop, context in
                return self.httpClient.execute(request: request, timeout: serviceConfig.timeout, on: eventLoop, context: context)
            },
            processResponse: { response in
                return try self.validate(operation: operationName, response: response, serviceConfig: serviceConfig)
            },
            config: serviceConfig,
            context: context,
            on: eventLoop
        )
    }

    /// execute a request with an input object and return a future with the output object generated from the response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS service configuration used in request creation and signing
    ///     - input: Input object
    ///     - context: Baggage context, holding a logger and baggage for tracing
    ///     - eventLoop: Eventloop to execute on
    /// - returns:
    ///     Future containing output object that completes when response is received
    public func execute<Output: AWSDecodableShape, Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        input: Input,
        context: Context = AWSClient.emptyContext,
        on eventLoop: EventLoop? = nil
    ) -> EventLoopFuture<Output> {
        return execute(
            operation: operationName,
            createRequest: {
                try AWSRequest(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    input: input,
                    configuration: serviceConfig
                )
            },
            execute: { request, eventLoop, context in
                return self.httpClient.execute(request: request, timeout: serviceConfig.timeout, on: eventLoop, context: context)
            },
            processResponse: { response in
                return try self.validate(operation: operationName, response: response, serviceConfig: serviceConfig)
            },
            config: serviceConfig,
            context: context,
            on: eventLoop
        )
    }

    /// execute a request with an input object and return a future with the output object generated from the response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS service configuration used in request creation and signing
    ///     - input: Input object
    ///     - context: Baggage context, holding a logger and baggage for tracing
    ///     - eventLoop: Eventloop to execute on
    ///     - stream: closure receiving payload data as it is received
    /// - returns:
    ///     Future containing output object that completes when response is received
    public func execute<Output: AWSDecodableShape, Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        input: Input,
        context: Context = AWSClient.emptyContext,
        on eventLoop: EventLoop? = nil,
        stream: @escaping AWSHTTPClient.ResponseStream
    ) -> EventLoopFuture<Output> {
        return execute(
            operation: operationName,
            createRequest: {
                try AWSRequest(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    input: input,
                    configuration: serviceConfig
                )
            },
            execute: { request, eventLoop, context in
                return self.httpClient.execute(request: request, timeout: serviceConfig.timeout, on: eventLoop, context: context, stream: stream)
            },
            processResponse: { response in
                return try self.validate(operation: operationName, response: response, serviceConfig: serviceConfig)
            },
            config: serviceConfig,
            context: context,
            on: eventLoop
        )
    }

    /// internal version of execute
    internal func execute<Output>(
        operation operationName: String,
        createRequest: @escaping () throws -> AWSRequest,
        execute: @escaping (AWSHTTPRequest, EventLoop, Context) -> EventLoopFuture<AWSHTTPResponse>,
        processResponse: @escaping (AWSHTTPResponse) throws -> Output,
        config: AWSServiceConfig,
        context: Context,
        on eventLoop: EventLoop? = nil
    ) -> EventLoopFuture<Output> {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
        var context = context
        context.baggage.awsService = config.service
        context.baggage.awsOperation = operationName
        context.baggage.awsRequestId = Self.globalRequestID.add(1)

        let future: EventLoopFuture<Output> = credentialProvider.getCredential(on: eventLoop, logger: context.logger)
            .flatMapThrowing { credential in
                let signer = AWSSigner(credentials: credential, name: config.signingName, region: config.region.rawValue)
                let awsRequest = try createRequest()
                return try awsRequest
                    .applyMiddlewares(config.middlewares + self.middlewares, config: config)
                    .createHTTPRequest(signer: signer, byteBufferAllocator: config.byteBufferAllocator)
            }.flatMap { request in
                return self.invoke(with: config, logger: context.logger) {
                    execute(request, eventLoop, context)
                }
            }.flatMapThrowing(processResponse)
        return recordRequest(future, service: config.service, operation: operationName, logger: context.logger)
    }

    /// generate a signed URL
    /// - parameters:
    ///     - url : URL to sign
    ///     - httpMethod: HTTP method to use (.GET, .PUT, .PUSH etc)
    ///     - httpHeaders: Headers that are to be used with this URL. Be sure to include these headers when you used the returned URL
    ///     - expires: How long before the signed URL expires
    ///     - serviceConfig: additional AWS service configuration used to sign the url
    ///     - context: Baggage context, holding a logger and baggage for tracing
    /// - returns:
    ///     A signed URL
    public func signURL(
        url: URL,
        httpMethod: HTTPMethod,
        headers: HTTPHeaders = HTTPHeaders(),
        expires: TimeAmount,
        serviceConfig: AWSServiceConfig,
        context: Context = AWSClient.emptyContext
    ) -> EventLoopFuture<URL> {
        var context = context
        context.baggage.awsService = config.service
        context.baggage.awsOperation = "signURL"
        context.baggage.awsRequestId = Self.globalRequestID.add(1)

        return createSigner(config: config, context: context).map { signer in
            signer.signURL(url: url, method: httpMethod, headers: headers, expires: expires)
        }
    }

    func createSigner(config: AWSServiceConfig, context: Context) -> EventLoopFuture<AWSSigner> {
        return credentialProvider.getCredential(on: eventLoopGroup.next(), logger: context.logger).map { credential in
            return AWSSigner(credentials: credential, name: config.signingName, region: config.region.rawValue)
        }
    }
}

// response validator
extension AWSClient {
    /// Generate an AWS Response from  the operation HTTP response and return the output shape from it. This is only every called if the response includes a successful http status code
    internal func validate<Output: AWSDecodableShape>(operation operationName: String, response: AWSHTTPResponse, serviceConfig: AWSServiceConfig) throws -> Output {
        assert((200..<300).contains(response.status.code), "Shouldn't get here if error was returned")

        let raw = (Output.self as? AWSShapeWithPayload.Type)?._payloadOptions.contains(.raw) == true
        let awsResponse = try AWSResponse(from: response, serviceProtocol: serviceConfig.serviceProtocol, raw: raw)
            .applyMiddlewares(serviceConfig.middlewares + middlewares, config: serviceConfig)

        return try awsResponse.generateOutputShape(operation: operationName)
    }

    /// Create error from HTTPResponse. This is only called if we received an unsuccessful http status code.
    internal func createError(for response: AWSHTTPResponse, serviceConfig: AWSServiceConfig, logger: Logger) -> Error {
        // if we can create an AWSResponse and create an error from it return that
        if let awsResponse = try? AWSResponse(from: response, serviceProtocol: serviceConfig.serviceProtocol)
            .applyMiddlewares(serviceConfig.middlewares + middlewares, config: serviceConfig),
            let error = awsResponse.generateError(serviceConfig: serviceConfig, logger: logger)
        {
            return error
        } else {
            // else return "Unhandled error message" with rawBody attached
            var rawBodyString: String?
            if var body = response.body {
                rawBodyString = body.readString(length: body.readableBytes)
            }
            return AWSError(statusCode: response.status, message: "Unhandled Error", rawBody: rawBodyString)
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
        case .tooMuchData:
            return "You have supplied too much data for the Request."
        }
    }
}

extension AWSClient {
    /// Record request in swift-metrics, and swift-log
    func recordRequest<Output>(_ future: EventLoopFuture<Output>, service: String, operation: String, logger: Logger) -> EventLoopFuture<Output> {
        let dimensions: [(String, String)] = [("aws-service", service), ("aws-operation", operation)]
        let startTime = DispatchTime.now().uptimeNanoseconds

        Counter(label: "aws_requests_total", dimensions: dimensions).increment()
        logger.info("AWS Request")

        return future.map { response in
            logger.trace("AWS Response")
            Metrics.Timer(
                label: "aws_request_duration",
                dimensions: dimensions,
                preferredDisplayUnit: .seconds
            ).recordNanoseconds(DispatchTime.now().uptimeNanoseconds - startTime)
            return response
        }.flatMapErrorThrowing { error in
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
}
