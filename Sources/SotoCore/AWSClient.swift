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
            eventLoop: httpClient.eventLoopGroup.next(),
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
    public func syncShutdown() throws {
        let errorStorageLock = NIOLock()
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

    /// Shutdown AWSClient asynchronously.
    ///
    /// Before an `AWSClient` is deleted you need to call this function or the synchronous
    /// version `syncShutdown` to do a clean shutdown of the client. It cleans up `CredentialProvider` tasks and shuts down
    /// the HTTP client if it was created by the `AWSClient`. Given we could be destroying the `EventLoopGroup` the client
    /// uses, we have to use a `DispatchQueue` to run some of this work on.
    ///
    /// - Parameters:
    ///   - queue: Dispatch Queue to run shutdown on
    ///   - callback: Callback called when shutdown is complete. If there was an error it will return with Error in callback
    public func shutdown(queue: DispatchQueue = .global(), _ callback: @escaping (Error?) -> Void) {
        guard self.isShutdown.compareExchange(expected: false, desired: true, ordering: .relaxed).exchanged else {
            callback(ClientError.alreadyShutdown)
            return
        }
        let eventLoop = eventLoopGroup.next()
        // ignore errors from credential provider. Don't need shutdown erroring because no providers were available
        credentialProvider.shutdown(on: eventLoop).whenComplete { _ in
            // if httpClient was created by AWSClient then it is required to shutdown the httpClient.
            switch self.httpClientProvider {
            case .createNew, .createNewWithEventLoopGroup:
                self.httpClient.shutdown(queue: queue) { error in
                    if let error = error {
                        self.clientLogger.log(level: self.options.errorLogLevel, "Error shutting down HTTP client", metadata: [
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

    // MARK: Member structs/enums

    /// Errors returned by `AWSClient` code
    public struct ClientError: Swift.Error, Equatable {
        enum Error {
            case alreadyShutdown
            case invalidURL
            case tooMuchData
            case notEnoughData
            case waiterFailed
            case waiterTimeout
            case failedToAccessPayload
        }

        let error: Error

        /// client has already been shutdown
        public static var alreadyShutdown: ClientError { .init(error: .alreadyShutdown) }
        /// URL provided to client is invalid
        public static var invalidURL: ClientError { .init(error: .invalidURL) }
        /// Too much data has been supplied for the Request
        public static var tooMuchData: ClientError { .init(error: .tooMuchData) }
        /// Not enough data has been supplied for the Request
        public static var notEnoughData: ClientError { .init(error: .notEnoughData) }
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

// response validator
extension AWSClient {
    /// Generate an AWS Response from  the operation HTTP response and return the output shape from it. This is only every called if the response includes a successful http status code
    internal func validate<Output: AWSDecodableShape>(operation operationName: String, response: AWSHTTPResponse, serviceConfig: AWSServiceConfig) throws -> Output {
        assert((200..<300).contains(response.status.code), "Shouldn't get here if error was returned")

        let raw = Output._options.contains(.rawPayload) == true
        let awsResponse = try AWSResponse(from: response, serviceProtocol: serviceConfig.serviceProtocol, raw: raw)
            .applyMiddlewares(serviceConfig.middlewares + middlewares, config: serviceConfig)

        return try awsResponse.generateOutputShape(operation: operationName)
    }

    /// Create error from HTTPResponse. This is only called if we received an unsuccessful http status code.
    internal func createError(for response: AWSHTTPResponse, serviceConfig: AWSServiceConfig, logger: Logger) -> Error {
        // if we can create an AWSResponse and create an error from it return that
        if let awsResponse = try? AWSResponse(from: response, serviceProtocol: serviceConfig.serviceProtocol)
            .applyMiddlewares(serviceConfig.middlewares + middlewares, config: serviceConfig),
            let error = awsResponse.generateError(serviceConfig: serviceConfig, logLevel: options.errorLogLevel, logger: logger)
        {
            return error
        } else {
            // else return "Unhandled error message" with rawBody attached
            var rawBodyString: String?
            if var body = response.body {
                rawBodyString = body.readString(length: body.readableBytes)
            }
            let context = AWSErrorContext(
                message: "Unhandled Error",
                responseCode: response.status,
                headers: response.headers
            )
            return AWSRawError(rawBody: rawBodyString, context: context)
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
        case .notEnoughData:
            return "You have not supplied enough data for the Request."
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
