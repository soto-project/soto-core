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

@_implementationOnly import AWSXML
import AsyncHTTPClient
import Dispatch
import Metrics
import NIO
import NIOHTTP1
import NIOTransportServices
import class  Foundation.JSONSerialization
import class  Foundation.JSONDecoder
import struct Foundation.Data
import struct Foundation.URL
import struct Foundation.URLComponents
import struct Foundation.URLQueryItem
import struct Foundation.CharacterSet

/// This is the workhorse of aws-sdk-swift-core. You provide it with a `AWSShape` Input object, it converts it to `AWSRequest` which is then converted
/// to a raw `HTTPClient` Request. This is then sent to AWS. When the response from AWS is received if it is successful it is converted to a `AWSResponse`
/// which is then decoded to generate a `AWSShape` Output object. If it is not successful then `AWSClient` will throw an `AWSErrorType`.
public final class AWSClient {

    public enum ClientError: Swift.Error, Equatable {
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
    let credentialProvider: CredentialProvider
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

    /// Initialize an AWSClient struct
    /// - parameters:
    ///     - credentialProvider: An object that returns valid signing credentials for request signing.
    ///     - serviceConfig: AWS service configuration
    ///     - retryPolicy: Object returning whether retries should be attempted. Possible options are NoRetry(), ExponentialRetry() or JitterRetry()
    ///     - middlewares: Array of middlewares to apply to requests and responses
    ///     - httpClientProvider: HTTPClient to use. Use `.createNew` if you want the client to manage its own HTTPClient.
    public init(
        credentialProvider: CredentialProvider?,
        retryPolicy: RetryPolicy = JitterRetry(),
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

        if let credentialProvider = credentialProvider {
            self.credentialProvider = credentialProvider
        }
        else {
            self.credentialProvider = RuntimeCredentialProvider.createProvider(
                on: self.httpClient.eventLoopGroup.next(),
                httpClient: self.httpClient)
        }

        self.middlewares = middlewares
        self.retryPolicy = retryPolicy
    }

    /// Initialize an AWSClient struct
    /// - parameters:
    ///     - accessKeyId: Public access key provided by AWS
    ///     - secretAccessKey: Private access key provided by AWS
    ///     - sessionToken: Token provided by STS.AssumeRole() which allows access to another AWS account
    ///     - region: Region of server you want to communicate with
    ///     - partition: Amazon endpoint partition. This is ignored if region is set. If no region is set then this is used along side serviceProtocol to calculate endpoint
    ///     - amzTarget: "x-amz-target" header value
    ///     - service: Name of service endpoint
    ///     - signingName: Name that all AWS requests are signed with
    ///     - serviceProtocol: protocol of service (.json, .xml, .query etc)
    ///     - apiVersion: "Version" header value
    ///     - endpoint: Custom endpoint URL to use instead of standard AWS servers
    ///     - serviceEndpoints: Dictionary of region to endpoints URLs
    ///     - partitionEndpoint: Default endpoint to use, if no region endpoint is supplied
    ///     - retryPolicy: Object returning whether retries should be attempted. Possible options are NoRetry(), ExponentialRetry() or JitterRetry()
    ///     - middlewares: Array of middlewares to apply to requests and responses
    ///     - possibleErrorTypes: Array of possible error types that the client can throw
    ///     - httpClientProvider: HTTPClient to use. Use `.createNew` if you want the client to manage its own HTTPClient.
    convenience public init(
        accessKeyId: String? = nil,
        secretAccessKey: String? = nil,
        sessionToken: String? = nil,
        httpClientProvider: HTTPClientProvider
    ) {
        var credentials: StaticCredential? = nil
        if let accessKeyId = accessKeyId, let secretAccessKey = secretAccessKey {
            credentials = StaticCredential(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey, sessionToken: sessionToken)
        }

        self.init(
            credentialProvider: credentials,
            httpClientProvider: httpClientProvider)
    }

    deinit {
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

    /// invoke HTTP request
    fileprivate func invoke(_ httpRequest: AWSHTTPRequest, on eventLoop: EventLoop) -> EventLoopFuture<AWSHTTPResponse> {
        let eventloop = self.eventLoopGroup.next()
        let promise = eventloop.makePromise(of: AWSHTTPResponse.self)

        func execute(_ httpRequest: AWSHTTPRequest, attempt: Int) {
            // execute HTTP request
            httpClient.execute(request: httpRequest, timeout: .seconds(20), on: eventLoop)
                .flatMapThrowing { (response) throws -> Void in
                    // if it returns an HTTP status code outside 2xx then throw an error
                    guard (200..<300).contains(response.status.code) else { throw AWSClient.InternalError.httpResponseError(response) }
                    promise.succeed(response)
                }
                .whenFailure { (error) in
                    // If I we failed, let's try to recover.
                    // If we get a retry time we will recover after that time has passed
                    if case .retry(let retryTime) = self.retryPolicy.getRetryWaitTime(error: error, attempt: attempt) {
                        // schedule task for retrying AWS request
                        eventloop.scheduleTask(in: retryTime) {
                            execute(httpRequest, attempt: attempt + 1)
                        }
                    } else {
                        // we could not recover - therefore let's fail
                        promise.fail(error)
                    }
                }
                
        }

        execute(httpRequest, attempt: 0)

        return promise.futureResult
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

// apis used by aws service structs
extension AWSClient {

    // We have four execute methods:
    //   1. No input, no output
    //   2. input but no output
    //   3. no input but an output
    //   4. an input and an output
    //
    // in this order:
    
    /// execute an operation without input payload and return a future with an empty result
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - configuration: A `ServiceConfig` object configuring the client
    ///     - eventLoop: An optional `EventLoop` on which the operation shall be send and received
    /// - returns:
    ///     Empty Future that completes when response is received
    public func execute(
        operation operationName: String,
        path: String,
        httpMethod: String,
        with configuration: ServiceConfig,
        on eventLoop: EventLoop? = nil) -> EventLoopFuture<Void>
    {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
        return credentialProvider.getCredential(on: eventLoop).flatMapThrowing { credential in
            let signer = AWSSigner(credentials: credential, name: configuration.signingName, region: configuration.region.rawValue)
            let awsRequest = try AWSRequest(
                        operation: operationName,
                        path: path,
                        httpMethod: httpMethod,
                        configuration: configuration).applyMiddlewares(configuration.middlewares + self.middlewares)
            return awsRequest.createHTTPRequest(signer: signer)
        }.flatMap { request in
            return self.invoke(request, on: eventLoop)
        }.flatMapErrorThrowing { (error) -> AWSHTTPResponse in
            guard case AWSClient.InternalError.httpResponseError(let response) = error else {
                throw error
            }
            throw Self.createError(for: response, configuration: configuration)
        }.map { _ in
            return
        }.recordMetrics(for: configuration.service, operation: operationName)
    }
    
    
    /// execute an operation with an input payload and return a future with an empty response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - input: Input object
    ///     - configuration: A `ServiceConfig` object configuring the client
    ///     - eventLoop: An optional `EventLoop` on which the operation shall be send and received
    /// - returns:
    ///     Empty Future that completes when response is received
    public func execute<Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: String,
        input: Input,
        with configuration: ServiceConfig,
        on eventLoop: EventLoop? = nil) -> EventLoopFuture<Void>
    {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
        return credentialProvider.getCredential(on: eventLoop).flatMapThrowing { credential in
            let signer = AWSSigner(credentials: credential, name: configuration.signingName, region: configuration.region.rawValue)
            let awsRequest = try AWSRequest(
                        operation: operationName,
                        path: path,
                        httpMethod: httpMethod,
                        input: input,
                        configuration: configuration
            ).applyMiddlewares(configuration.middlewares + self.middlewares)
            return awsRequest.createHTTPRequest(signer: signer)
        }.flatMap { request in
            return self.invoke(request, on: eventLoop)
        }.flatMapErrorThrowing { (error) -> AWSHTTPResponse in
            guard case AWSClient.InternalError.httpResponseError(let response) = error else {
                throw error
            }
            throw Self.createError(for: response, configuration: configuration)
        }.map { _ in
            return
        }.recordMetrics(for: configuration.service, operation: operationName)
    }

    /// execute an operation without input payload and return a future with the output object generated from the response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - configuration: A `ServiceConfig` object configuring the client
    ///     - eventLoop: An optional `EventLoop` on which the operation shall be send and received
    /// - returns:
    ///     Future containing output object that completes when response is received
    public func execute<Output: AWSDecodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: String,
        with configuration: ServiceConfig,
        on eventLoop: EventLoop? = nil) -> EventLoopFuture<Output>
    {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
        return credentialProvider.getCredential(on: eventLoop).flatMapThrowing { credential in
            let signer = AWSSigner(credentials: credential, name: configuration.signingName, region: configuration.region.rawValue)
            let awsRequest = try AWSRequest(
                        operation: operationName,
                        path: path,
                        httpMethod: httpMethod,
                        configuration: configuration).applyMiddlewares(configuration.middlewares + self.middlewares)
            return awsRequest.createHTTPRequest(signer: signer)
        }.flatMap { request in
            return self.invoke(request, on: eventLoop)
        }.flatMapErrorThrowing { (error) -> AWSHTTPResponse in
            guard case AWSClient.InternalError.httpResponseError(let response) = error else {
                throw error
            }
            throw Self.createError(for: response, configuration: configuration)
        }.flatMapThrowing { response in
            return try response.validate(operation: operationName, configuration: configuration, middlewares: self.middlewares)
        }.recordMetrics(for: configuration.service, operation: operationName)
    }

    /// execute an operation with an input object and return a future with the output object generated from the response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - input: Input object
    ///     - configuration: A `ServiceConfig` object configuring the client
    ///     - eventLoop: An optional `EventLoop` on which the operation shall be send and received
    /// - returns:
    ///     Future containing output object that completes when response is received
    public func send<Output: AWSDecodableShape, Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: String,
        input: Input,
        with configuration: ServiceConfig,
        on eventLoop: EventLoop? = nil) -> EventLoopFuture<Output>
    {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
        return credentialProvider.getCredential(on: eventLoop).flatMapThrowing { credential in
            let signer = AWSSigner(credentials: credential, name: configuration.signingName, region: configuration.region.rawValue)
            let awsRequest = try AWSRequest(
                        operation: operationName,
                        path: path,
                        httpMethod: httpMethod,
                        input: input,
                        configuration: configuration).applyMiddlewares(configuration.middlewares + self.middlewares)
            return awsRequest.createHTTPRequest(signer: signer)
        }.flatMap { request in
            return self.invoke(request, on: eventLoop)
        }.flatMapErrorThrowing { (error) -> AWSHTTPResponse in
            guard case AWSClient.InternalError.httpResponseError(let response) = error else {
                throw error
            }
            throw Self.createError(for: response, configuration: configuration)
        }.flatMapThrowing { response in
            return try response.validate(operation: operationName, configuration: configuration, middlewares: self.middlewares)
        }.recordMetrics(for: configuration.service, operation: operationName)
    }

    /// generate a signed URL
    /// - parameters:
    ///     - url : URL to sign
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - expires: How long before the signed URL expires
    /// - returns:
    ///     A signed URL
    public func signURL(url: URL, httpMethod: String, expires: Int = 86400) -> EventLoopFuture<URL> {
        preconditionFailure()
        //signer.map { signer in signer.signURL(url: url, method: HTTPMethod(rawValue: httpMethod), expires: expires) }
    }
}

// request creator
extension AWSClient {

//    var signer: EventLoopFuture<AWSSigner> {
//        return credentialProvider.getCredential(on: eventLoopGroup.next()).map { credential in
//            return AWSSigner(credentials: credential, name: self.serviceConfig.signingName, region: self.serviceConfig.region.rawValue)
//        }
//    }
}

extension AWSRequest {
    
    init(operation operationName: String,
         path: String,
         httpMethod: String,
         configuration: ServiceConfig) throws
    {
        var headers: [String: Any] = [:]

        guard let url = URL(string: "\(configuration.endpoint)\(path)"), let _ = url.host else {
            throw AWSClient.ClientError.invalidURL("\(configuration.endpoint)\(path) must specify url host and scheme")
        }

        // set x-amz-target header
        if let target = configuration.amzTarget {
            headers["x-amz-target"] = "\(target).\(operationName)"
        }

        self.region = configuration.region
        self.url = url
        self.serviceProtocol = configuration.serviceProtocol
        self.operation = operationName
        self.httpMethod = httpMethod
        self.httpHeaders = headers
        self.body = .empty
    }
    
    init<Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: String,
        input: Input,
        configuration: ServiceConfig) throws
    {
        var headers: [String: Any] = [:]
        var path = path
        var body: Body = .empty
        var queryParams: [(key:String, value:Any)] = []

        // validate input parameters
        try input.validate()

        guard let baseURL = URL(string: "\(configuration.endpoint)"), let _ = baseURL.host else {
            throw AWSClient.ClientError.invalidURL("\(configuration.endpoint) must specify url host and scheme")
        }

        // set x-amz-target header
        if let target = configuration.amzTarget {
            headers["x-amz-target"] = "\(target).\(operationName)"
        }

        // TODO should replace with Encodable
        let mirror = Mirror(reflecting: input)
        var memberVariablesCount = mirror.children.count - Input._encoding.count

        // extract header, query and uri params
        for encoding in Input._encoding {
            if let value = mirror.getAttribute(forKey: encoding.label) {
                switch encoding.location {
                case .header(let location):
                    headers[location] = value

                case .querystring(let location):
                    switch value {
                    case let array as QueryEncodableArray:
                        array.queryEncoded.forEach { queryParams.append((key:location, value:$0)) }
                    case let dictionary as QueryEncodableDictionary:
                        dictionary.queryEncoded.forEach { queryParams.append($0) }
                    default:
                        queryParams.append((key:location, value:"\(value)"))
                    }

                case .uri(let location):
                    path = path
                        .replacingOccurrences(of: "{\(location)}", with: "\(value)")
                        // percent-encode key which is part of the path
                        .replacingOccurrences(of: "{\(location)+}", with: "\(value)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)

                default:
                    memberVariablesCount += 1
                }
            }
        }

        switch configuration.serviceProtocol {
        case .json, .restjson:
            if let shapeWithPayload = Input.self as? AWSShapeWithPayload.Type {
                let payload = shapeWithPayload.payloadPath
                if let payloadBody = mirror.getAttribute(forKey: payload) {
                    switch payloadBody {
                    case let awsPayload as AWSPayload:
                        Self.verifyStream(operation: operationName, payload: awsPayload, input: shapeWithPayload)
                        body = .raw(awsPayload)
                    case let shape as AWSEncodableShape:
                        body = .json(try shape.encodeAsJSON())
                    default:
                        preconditionFailure("Cannot add this as a payload")
                    }
                } else {
                    body = .empty
                }
            } else {
                // only include the body if there are members that are output in the body.
                if memberVariablesCount > 0 {
                    body = .json(try input.encodeAsJSON())
                }
            }

        case .query:
            var dict = try input.encodeAsQuery()

            dict["Action"] = operationName
            dict["Version"] = configuration.apiVersion

            switch httpMethod {
            case "GET":
                queryParams.append(contentsOf: dict.map {(key:$0.key, value:$0)})
            default:
                if let urlEncodedQueryParams = Self.urlEncodeQueryParams(fromDictionary: dict) {
                    body = .text(urlEncodedQueryParams)
                }
            }

        case .restxml:
            if let shapeWithPayload = Input.self as? AWSShapeWithPayload.Type {
                let payload = shapeWithPayload.payloadPath
                if let payloadBody = mirror.getAttribute(forKey: payload) {
                    switch payloadBody {
                    case let awsPayload as AWSPayload:
                        Self.verifyStream(operation: operationName, payload: awsPayload, input: shapeWithPayload)
                        body = .raw(awsPayload)
                    case let shape as AWSEncodableShape:
                        var rootName: String? = nil
                        // extract custom payload name
                        if let encoding = Input.getEncoding(for: payload), case .body(let locationName) = encoding.location {
                            rootName = locationName
                        }
                        body = .xml(try shape.encodeAsXML(rootName: rootName))
                    default:
                        preconditionFailure("Cannot add this as a payload")
                    }
                } else {
                    body = .empty
                }
            } else {
                // only include the body if there are members that are output in the body.
                if memberVariablesCount > 0 {
                    body = .xml(try input.encodeAsXML())
                }
            }

        case .ec2:
            var params = try input.encodeAsQueryForEC2()
            params["Action"] = operationName
            params["Version"] = configuration.apiVersion
            if let urlEncodedQueryParams = Self.urlEncodeQueryParams(fromDictionary: params) {
                body = .text(urlEncodedQueryParams)
            }
        }

        guard let parsedPath = URLComponents(string: path) else {
            throw AWSClient.ClientError.invalidURL("\(configuration.endpoint)\(path)")
        }

        // add queries from the parsed path to the query params list
        if let pathQueryItems = parsedPath.queryItems {
            for item in pathQueryItems {
                queryParams.append((key:item.name, value: item.value ?? ""))
            }
        }

        // Build URL. Don't use URLComponents as Foundation and AWS disagree on what should be percent encoded in the query values
        var urlString = "\(baseURL.absoluteString)\(parsedPath.path)"
        if queryParams.count > 0 {
            urlString.append("?")
            urlString.append(queryParams.sorted{$0.key < $1.key}.map{"\($0.key)=\(Self.urlEncodeQueryParam("\($0.value)"))"}.joined(separator:"&"))
        }

        guard let url = URL(string: urlString) else {
            throw AWSClient.ClientError.invalidURL("\(urlString)")
        }

        
        self.region = configuration.region
        self.url = url
        self.serviceProtocol = configuration.serviceProtocol
        self.operation = operationName
        self.httpMethod = httpMethod
        self.httpHeaders = headers
        self.body = body
    }
    
    // MARK: - Private static helpers -

    private static func verifyStream(operation: String, payload: AWSPayload, input: AWSShapeWithPayload.Type) {
        guard case .stream(let size,_) = payload.payload else { return }
        precondition(input.options.contains(.allowStreaming), "\(operation) does not allow streaming of data")
        precondition(size != nil || input.options.contains(.allowChunkedStreaming), "\(operation) does not allow chunked streaming of data. Please supply a data size.")
    }

    static let queryAllowedCharacters = CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/")

    private static func urlEncodeQueryParam(_ value: String) -> String {
        return value.addingPercentEncoding(withAllowedCharacters: Self.queryAllowedCharacters) ?? value
    }

    private static func urlEncodeQueryParams(fromDictionary dict: [String:Any]) -> String? {
        guard dict.count > 0 else {return nil}
        var query = ""
        let keys = Array(dict.keys).sorted()

        for iterator in keys.enumerated() {
            let value = dict[iterator.element]
            query += iterator.element + "=" + (urlEncodeQueryParam(String(describing: value ?? "")))
            if iterator.offset < dict.count - 1 {
                query += "&"
            }
        }
        return query
    }
}

// response validator
extension AWSHTTPResponse {

    /// Validate the operation response and return a response shape
    internal func validate<Output: AWSDecodableShape>(
        operation operationName: String,
        configuration: ServiceConfig,
        middlewares: [AWSServiceMiddleware] = []) throws -> Output
    {
        var raw: Bool = false
        var payloadKey: String? = (Output.self as? AWSShapeWithPayload.Type)?.payloadPath

        // if response has a payload with encoding info
        if let payloadPath = payloadKey, let encoding = Output.getEncoding(for: payloadPath) {
            // is payload raw
            if case .blob = encoding.shapeEncoding, (200..<300).contains(self.status.code) {
                raw = true
            }
            // get CodingKey string for payload to insert in output
            if let location = encoding.location, case .body(let name) = location {
                payloadKey = name
            }
        }

        var awsResponse = try AWSResponse(from: self, serviceProtocol: configuration.serviceProtocol, raw: raw)

        // do we need to fix up the response before processing it
        for middleware in configuration.middlewares + middlewares {
            awsResponse = try middleware.chain(response: awsResponse)
        }

        awsResponse = try hypertextApplicationLanguageProcess(response: awsResponse)

        let decoder = DictionaryDecoder()

        var outputDict: [String: Any] = [:]
        switch awsResponse.body {
        case .json(let data):
            outputDict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] ?? [:]
            // if payload path is set then the decode will expect the payload to decode to the relevant member variable
            if let payloadKey = payloadKey {
                outputDict = [payloadKey : outputDict]
            }

        case .xml(let node):
            var outputNode = node
            // if payload path is set then the decode will expect the payload to decode to the relevant member variable. Most CloudFront responses have this.
            if let payloadKey = payloadKey {
                // set output node name
                outputNode.name = payloadKey
                // create parent node and add output node and set output node to parent
                let parentNode = XML.Element(name: "Container")
                parentNode.addChild(outputNode)
                outputNode = parentNode
            } else if let child = node.children(of:.element)?.first as? XML.Element, (node.name == operationName + "Response" && child.name == operationName + "Result") {
                outputNode = child
            }

            // add header values to xmlnode as children nodes, so they can be decoded into the response object
            for (key, value) in awsResponse.headers {
                let headerParams = Output.headerParams
                if let index = headerParams.firstIndex(where: { $0.key.lowercased() == key.lowercased() }) {
                    guard let stringValue = value as? String else { continue }
                    let node = XML.Element(name: headerParams[index].key, stringValue: stringValue)
                    outputNode.addChild(node)
                }
            }
            // add status code to output dictionary
            if let statusCodeParam = Output.statusCodeParam {
                let node = XML.Element(name: statusCodeParam, stringValue: "\(self.status.code)")
                outputNode.addChild(node)
            }
            return try XMLDecoder().decode(Output.self, from: outputNode)

        case .raw(let payload):
            if let payloadKey = payloadKey {
                outputDict[payloadKey] = payload
            }

        default:
            break
        }

        // add header values to output dictionary, so they can be decoded into the response object
        for (key, value) in awsResponse.headers {
            let headerParams = Output.headerParams
            if let index = headerParams.firstIndex(where: { $0.key.lowercased() == key.lowercased() }) {
                // check we can convert to a String. If not just put value straight into output dictionary
                guard let stringValue = value as? String else {
                    outputDict[headerParams[index].key] = value
                    continue
                }
                if let number = Double(stringValue) {
                    outputDict[headerParams[index].key] = number.truncatingRemainder(dividingBy: 1) == 0 ? Int(number) : number
                } else if let boolean = Bool(stringValue) {
                    outputDict[headerParams[index].key] = boolean
                } else {
                    outputDict[headerParams[index].key] = stringValue
                }
            }
        }
        // add status code to output dictionary
        if let statusCodeParam = Output.statusCodeParam {
            outputDict[statusCodeParam] = self.status.code
        }

        return try decoder.decode(Output.self, from: outputDict)
    }
}

extension AWSClient {

    internal static func createError(for response: AWSHTTPResponse, configuration: ServiceConfig) -> Error {
        do {
            let awsResponse = try AWSResponse(from: response, serviceProtocol: configuration.serviceProtocol)
            struct XMLError: Codable, ErrorMessage {
                var code: String?
                var message: String

                private enum CodingKeys: String, CodingKey {
                    case code = "Code"
                    case message = "Message"
                }
            }
            struct QueryError: Codable, ErrorMessage {
                var code: String?
                var message: String

                private enum CodingKeys: String, CodingKey {
                    case code = "Code"
                    case message = "Message"
                }
            }
            struct JSONError: Codable, ErrorMessage {
                var code: String?
                var message: String

                private enum CodingKeys: String, CodingKey {
                    case code = "__type"
                    case message = "message"
                }
            }
            struct RESTJSONError: Codable, ErrorMessage {
                var code: String?
                var message: String

                private enum CodingKeys: String, CodingKey {
                    case code = "code"
                    case message = "message"
                }
            }

            var errorMessage: ErrorMessage? = nil

            switch configuration.serviceProtocol {
            case .query:
                guard case .xml(var element) = awsResponse.body else { break }
                if let errors = element.elements(forName: "Errors").first {
                    element = errors
                }
                guard let errorElement = element.elements(forName: "Error").first else { break }
                errorMessage = try? XMLDecoder().decode(QueryError.self, from: errorElement)

            case .restxml:
                guard case .xml(var element) = awsResponse.body else { break }
                if let error = element.elements(forName: "Error").first {
                    element = error
                }
                errorMessage = try? XMLDecoder().decode(XMLError.self, from: element)

            case .restjson:
                guard case .json(let data) = awsResponse.body else { break }
                errorMessage = try? JSONDecoder().decode(RESTJSONError.self, from: data)
                if errorMessage?.code == nil {
                    errorMessage?.code = awsResponse.headers["x-amzn-ErrorType"] as? String
                }

            case .json:
                guard case .json(let data) = awsResponse.body else { break }
                errorMessage = try? JSONDecoder().decode(JSONError.self, from: data)

            case .ec2:
                guard case .xml(var element) = awsResponse.body else { break }
                if let errors = element.elements(forName: "Errors").first {
                    element = errors
                }
                guard let errorElement = element.elements(forName: "Error").first else { break }
                errorMessage = try? XMLDecoder().decode(QueryError.self, from: errorElement)
            }

            if let errorMessage = errorMessage, var code = errorMessage.code {
                // remove code prefix before #
                if let index = code.firstIndex(of: "#") {
                    code = String(code[code.index(index, offsetBy: 1)...])
                }
                for errorType in configuration.possibleErrorTypes {
                    if let error = errorType.init(errorCode: code, message: errorMessage.message) {
                        return error
                    }
                }
                if let error = AWSClientError(errorCode: code, message: errorMessage.message) {
                    return error
                }

                if let error = AWSServerError(errorCode: code, message: errorMessage.message) {
                    return error
                }

                return AWSResponseError(errorCode: code, message: errorMessage.message)
            }

            let rawBodyString = awsResponse.body.asString()
            return AWSError(statusCode: response.status, message: errorMessage?.message ?? "Unhandled Error. Response Code: \(response.status.code)", rawBody: rawBodyString ?? "")
        } catch {
            return error
        }
    }
}

protocol ErrorMessage {
    var code: String? {get set}
    var message: String {get set}
}

extension AWSClient.ClientError: CustomStringConvertible {
    public var description: String {
        switch self {
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

extension EventLoopFuture {
    func recordMetrics(for service: String, operation: String) -> EventLoopFuture<Value> {
        let dimensions: [(String, String)] = [("service", service), ("operation", operation)]
        let startTime = DispatchTime.now().uptimeNanoseconds

        Counter(label: "aws_requests_total", dimensions: dimensions).increment()
        
        return self.map { response in
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

protocol QueryEncodableArray {
    var queryEncoded: [String] { get }
}

extension Array : QueryEncodableArray {
    var queryEncoded: [String] { return self.map{ "\($0)" }}
}

protocol QueryEncodableDictionary {
    var queryEncoded: [(key:String, entry: String)] { get }
}

extension Dictionary : QueryEncodableDictionary {
    var queryEncoded: [(key:String, entry: String)] {
        return self.map{ (key:"\($0.key)", value:"\($0.value)") }
    }
}
