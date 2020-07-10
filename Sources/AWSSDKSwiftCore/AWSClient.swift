//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AWSSignerV4
import AWSXML
import AsyncHTTPClient
import Dispatch
import Metrics
import NIO
import NIOConcurrencyHelpers
import NIOHTTP1
import NIOTransportServices
import class  Foundation.JSONSerialization
import class  Foundation.JSONDecoder
import struct Foundation.Data
import struct Foundation.URL
import struct Foundation.URLQueryItem


/// This is the workhorse of aws-sdk-swift-core. You provide it with a `AWSShape` Input object, it converts it to `AWSRequest` which is then converted
/// to a raw `HTTPClient` Request. This is then sent to AWS. When the response from AWS is received if it is successful it is converted to a `AWSResponse`
/// which is then decoded to generate a `AWSShape` Output object. If it is not successful then `AWSClient` will throw an `AWSErrorType`.
public final class AWSClient {

    public enum ClientError: Swift.Error {
        case alreadyShutdown
        case invalidURL(String)
        case tooMuchData
    }

    enum InternalError: Swift.Error {
        case httpResponseError(AWSHTTPResponse)
    }

    /// Specifies how `HTTPClient` will be created and establishes lifecycle ownership.
    public enum HTTPClientProvider {
        /// `HTTPClient` will be provided by the user. Owner of this group is responsible for its lifecycle. Any HTTPClient that conforms to
        /// `AWSHTTPClient` can be specified here including AsyncHTTPClient
        case shared(AWSHTTPClient)
        /// `HTTPClient` will be created by the client. When `deinit` is called, created `HTTPClient` will be shut down as well.
        case createNew
    }

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
    /// Retry Controller specifying what to do when a request fails
    public let retryPolicy: RetryPolicy

    private let isShutdown = NIOAtomic<Bool>.makeAtomic(value: false)

    /// Initialize an AWSClient struct
    /// - parameters:
    ///     - credentialProvider: An object that returns valid signing credentials for request signing.
    ///     - retryPolicy: Object returning whether retries should be attempted. Possible options are NoRetry(), ExponentialRetry() or JitterRetry()
    ///     - middlewares: Array of middlewares to apply to requests and responses
    ///     - httpClientProvider: HTTPClient to use. Use `.createNew` if you want the client to manage its own HTTPClient.
    public init(
        credentialProvider credentialProviderFactory: CredentialProviderFactory = .default,
        retryPolicy retryPolicyFactory: RetryPolicyFactory = .default,
        middlewares: [AWSServiceMiddleware] = [],
        httpClientProvider: HTTPClientProvider
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
            eventLoop: httpClient.eventLoopGroup.next()))

        self.middlewares = middlewares
        self.retryPolicy = retryPolicyFactory.retryPolicy
    }

    deinit {
        assert(self.isShutdown.load(), "AWSClient not shut down before the deinit. Please call client.syncShutdown() when no longer needed.")
    }

    public func syncShutdown() throws {
        guard self.isShutdown.compareAndExchange(expected: false, desired: true) else {
            throw ClientError.alreadyShutdown
        }
        // ignore errors from credential provider. Don't need shutdown erroring because no providers were available
        try? credentialProvider.shutdown(on: eventLoopGroup.next()).wait()
        // if httpClient was created by AWSClient then it is required to shutdown the httpClient
        if case .createNew = httpClientProvider {
            do {
                try httpClient.syncShutdown()
            } catch {
                print("Error shutting down HTTP client: \(error)")
            }
        }
    }
}

// invoker
extension AWSClient {

    fileprivate func invoke(with serviceConfig: AWSServiceConfig, _ request: @escaping () -> EventLoopFuture<AWSHTTPResponse>) -> EventLoopFuture<AWSHTTPResponse> {
        let eventloop = self.eventLoopGroup.next()
        let promise = eventloop.makePromise(of: AWSHTTPResponse.self)

        func execute(attempt: Int) {
            // execute HTTP request
            _ = request()
                .flatMapThrowing { (response) throws -> Void in
                    // if it returns an HTTP status code outside 2xx then throw an error
                    guard (200..<300).contains(response.status.code) else { throw AWSClient.InternalError.httpResponseError(response) }
                    promise.succeed(response)
                }
                .flatMapErrorThrowing { (error)->Void in
                    // If I get a retry wait time for this error then attempt to retry request
                    if case .retry(let retryTime) = self.retryPolicy.getRetryWaitTime(error: error, attempt: attempt) {
                        // schedule task for retrying AWS request
                        eventloop.scheduleTask(in: retryTime) {
                            execute(attempt: attempt + 1)
                        }
                    } else if case AWSClient.InternalError.httpResponseError(let response) = error {
                        // if there was no retry and error was a response status code then attempt to convert to AWS error
                        promise.fail(self.createError(for: response, serviceConfig: serviceConfig))
                    } else {
                        promise.fail(error)
                    }
            }
        }

        execute(attempt: 0)

        return promise.futureResult
    }

    /// invoke HTTP request
    fileprivate func invoke(_ httpRequest: AWSHTTPRequest, with serviceConfig: AWSServiceConfig, on eventLoop: EventLoop) -> EventLoopFuture<AWSHTTPResponse> {
        return invoke(with: serviceConfig) {
            return self.httpClient.execute(request: httpRequest, timeout: serviceConfig.timeout, on: eventLoop)
        }
    }

    /// invoke HTTP request with response streaming
    fileprivate func invoke(_ httpRequest: AWSHTTPRequest, with serviceConfig: AWSServiceConfig, on eventLoop: EventLoop, stream: @escaping AWSHTTPClient.ResponseStream) -> EventLoopFuture<AWSHTTPResponse> {
        return invoke(with: serviceConfig) {
            return self.httpClient.execute(request: httpRequest, timeout: serviceConfig.timeout, on: eventLoop, stream: stream)
        }
    }

    /// create HTTPClient
    fileprivate static func createHTTPClient() -> AWSHTTPClient {
        #if canImport(Network)
        if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
            return NIOTSHTTPClient(eventLoopGroupProvider: .createNew)
        }
        #endif
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
    /// - returns:
    ///     Empty Future that completes when response is received
    public func execute<Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        input: Input,
        on eventLoop: EventLoop? = nil
    ) -> EventLoopFuture<Void> {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
        let future: EventLoopFuture<Void> = credentialProvider.getCredential(on: eventLoop).flatMapThrowing { credential in
            let signer = AWSSigner(credentials: credential, name: serviceConfig.signingName, region: serviceConfig.region.rawValue)
            let awsRequest = try AWSRequest(
                        operation: operationName,
                        path: path,
                        httpMethod: httpMethod,
                        input: input,
                        configuration: serviceConfig)
            return try awsRequest
                .applyMiddlewares(serviceConfig.middlewares + self.middlewares)
                .createHTTPRequest(signer: signer)
        }.flatMap { request in
            return self.invoke(request, with: serviceConfig, on: eventLoop)
        }.map { _ in
            return
        }
        return recordMetrics(future, service: serviceConfig.service, operation: operationName)
    }

    /// execute an empty request and return a future with an empty response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS service configuration used in request creation and signing
    /// - returns:
    ///     Empty Future that completes when response is received
    public func execute(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        on eventLoop: EventLoop? = nil
    ) -> EventLoopFuture<Void> {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
        let future: EventLoopFuture<Void> = credentialProvider.getCredential(on: eventLoop).flatMapThrowing { credential in
            let signer = AWSSigner(credentials: credential, name: serviceConfig.signingName, region: serviceConfig.region.rawValue)
            let awsRequest = try AWSRequest(
                operation: operationName,
                path: path,
                httpMethod: httpMethod,
                configuration: serviceConfig)
            return try awsRequest
                .applyMiddlewares(serviceConfig.middlewares + self.middlewares)
                .createHTTPRequest(signer: signer)

        }.flatMap { request in
            return self.invoke(request, with: serviceConfig, on: eventLoop)
        }.map { _ in
            return
        }
        return recordMetrics(future, service: serviceConfig.service, operation: operationName)
    }

    /// execute an empty request and return a future with the output object generated from the response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS service configuration used in request creation and signing
    /// - returns:
    ///     Future containing output object that completes when response is received
    public func execute<Output: AWSDecodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        on eventLoop: EventLoop? = nil
    ) -> EventLoopFuture<Output> {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
        let future: EventLoopFuture<Output> = credentialProvider.getCredential(on: eventLoop).flatMapThrowing { credential in
            let signer = AWSSigner(credentials: credential, name: serviceConfig.signingName, region: serviceConfig.region.rawValue)
            let awsRequest = try AWSRequest(
                operation: operationName,
                path: path,
                httpMethod: httpMethod,
                configuration: serviceConfig)
            return try awsRequest
                .applyMiddlewares(serviceConfig.middlewares + self.middlewares)
                .createHTTPRequest(signer: signer)
        }.flatMap { request in
            return self.invoke(request, with: serviceConfig, on: eventLoop)
        }.flatMapThrowing { response in
            return try self.validate(operation: operationName, response: response, serviceConfig: serviceConfig)
        }
        return recordMetrics(future, service: serviceConfig.service, operation: operationName)
    }

    /// execute a request with an input object and return a future with the output object generated from the response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS service configuration used in request creation and signing
    ///     - input: Input object
    /// - returns:
    ///     Future containing output object that completes when response is received
    public func execute<Output: AWSDecodableShape, Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        input: Input,
        on eventLoop: EventLoop? = nil
    ) -> EventLoopFuture<Output> {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
        let future: EventLoopFuture<Output> = credentialProvider.getCredential(on: eventLoop).flatMapThrowing { credential in
            let signer = AWSSigner(credentials: credential, name: serviceConfig.signingName, region: serviceConfig.region.rawValue)
            let awsRequest = try AWSRequest(
                        operation: operationName,
                        path: path,
                        httpMethod: httpMethod,
                        input: input,
                        configuration: serviceConfig)
            return try awsRequest
                .applyMiddlewares(serviceConfig.middlewares + self.middlewares)
                .createHTTPRequest(signer: signer)
        }.flatMap { request in
            return self.invoke(request, with: serviceConfig, on: eventLoop)
        }.flatMapThrowing { response in
            return try self.validate(operation: operationName, response: response, serviceConfig: serviceConfig)
        }
        return recordMetrics(future, service: serviceConfig.service, operation: operationName)
    }

    /// execute a request with an input object and return a future with the output object generated from the response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - serviceConfig: AWS service configuration used in request creation and signing
    ///     - input: Input object
    /// - returns:
    ///     Future containing output object that completes when response is received
    public func execute<Output: AWSDecodableShape, Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: HTTPMethod,
        serviceConfig: AWSServiceConfig,
        input: Input,
        on eventLoop: EventLoop? = nil,
        stream: @escaping AWSHTTPClient.ResponseStream
    ) -> EventLoopFuture<Output> {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
        return credentialProvider.getCredential(on: eventLoop).flatMapThrowing { credential in
            let signer = AWSSigner(credentials: credential, name: serviceConfig.signingName, region: serviceConfig.region.rawValue)
            let awsRequest = try AWSRequest(
                operation: operationName,
                path: path,
                httpMethod: httpMethod,
                input: input,
                configuration: serviceConfig)
            return try awsRequest
                .applyMiddlewares(serviceConfig.middlewares + self.middlewares)
                .createHTTPRequest(signer: signer)
        }.flatMap { request in
            return self.invoke(request, with: serviceConfig, on: eventLoop, stream: stream)
        }.flatMapThrowing { response in
            return try self.validate(operation: operationName, response: response, serviceConfig: serviceConfig)
        }
    }

    /// generate a signed URL
    /// - parameters:
    ///     - url : URL to sign
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - expires: How long before the signed URL expires
    ///     - serviceConfig: additional AWS service configuration used to sign the url
    /// - returns:
    ///     A signed URL
    public func signURL(url: URL, httpMethod: String, expires: Int = 86400, serviceConfig: AWSServiceConfig) -> EventLoopFuture<URL> {
        return createSigner(serviceConfig: serviceConfig).map { signer in
            signer.signURL(url: url, method: HTTPMethod(rawValue: httpMethod), expires: expires)
        }
    }

    public func createSigner(serviceConfig: AWSServiceConfig) -> EventLoopFuture<AWSSigner> {
        return credentialProvider.getCredential(on: eventLoopGroup.next()).map { credential in
            return AWSSigner(credentials: credential, name: serviceConfig.signingName, region: serviceConfig.region.rawValue)
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
            .applyMiddlewares(serviceConfig.middlewares + middlewares)

        return try awsResponse.generateOutputShape(operation: operationName)
    }

    /// Create error from HTTPResponse. This is only called if we received an unsuccessful http status code.
    internal func createError(for response: AWSHTTPResponse, serviceConfig: AWSServiceConfig) -> Error {
        // if we can create an AWSResponse and create an error from it return that
        if let awsResponse = try? AWSResponse(from: response, serviceProtocol: serviceConfig.serviceProtocol)
            .applyMiddlewares(serviceConfig.middlewares + middlewares),
            let error = awsResponse.generateError(serviceConfig: serviceConfig) {
            return error
        } else {
            // else return "Unhandled error message" with rawBody attached
            var rawBodyString: String? = nil
            if var body = response.body {
                rawBodyString = body.readString(length: body.readableBytes)
            }
            return AWSError(statusCode: response.status, message: "Unhandled Error", rawBody: rawBodyString)
        }
    }
}

extension AWSClient.ClientError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .alreadyShutdown:
            return "The AWSClient is already shutdown"
        case .invalidURL(let urlString):
            return """
            The request url \(urlString) is invalid format.
            This error is internal. So please make a issue on https://github.com/swift-aws/aws-sdk-swift/issues to solve it.
            """
        case .tooMuchData:
            return "You have supplied too much data for the Request."
        }
    }
}

extension AWSClient {
    func recordMetrics<Output>(_ future: EventLoopFuture<Output>, service: String, operation: String) -> EventLoopFuture<Output> {
        let dimensions: [(String, String)] = [("service", service), ("operation", operation)]
        let startTime = DispatchTime.now().uptimeNanoseconds

        Counter(label: "aws_requests_total", dimensions: dimensions).increment()

        return future.map { response in
            Metrics.Timer(
                label: "aws_request_duration",
                dimensions: dimensions,
                preferredDisplayUnit: .seconds
            ).recordNanoseconds(DispatchTime.now().uptimeNanoseconds - startTime)
            return response
        }.flatMapErrorThrowing { error in
            Counter(label: "aws_request_errors", dimensions: dimensions).increment()
            throw error
        }
    }
}
