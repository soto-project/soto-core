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

import AsyncHTTPClient
import NIO
import NIOHTTP1
import NIOTransportServices
import class  Foundation.ProcessInfo
import class  Foundation.JSONSerialization
import class  Foundation.JSONDecoder
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.URL
import struct Foundation.URLComponents
import struct Foundation.URLQueryItem
import struct Foundation.CharacterSet

/// This is the workhorse of aws-sdk-swift-core. You provide it with a `AWSShape` Input object, it converts it to `AWSRequest` which is then converted to a raw `HTTPClient` Request. This is then sent to AWS. When the response from AWS is received if it is successful it is converted to a `AWSResponse` which is then decoded to generate a `AWSShape` Output object. If it is not successful then `AWSClient` will throw an `AWSErrorType`.
public final class AWSClient {

    public enum RequestError: Error {
        case invalidURL(String)
    }

    /// Specifies how `EventLoopGroup` will be created and establishes lifecycle ownership.
    public enum EventLoopGroupProvider {
        /// `EventLoopGroup` will be provided by the user. Owner of this group is responsible for its lifecycle.
        case shared(EventLoopGroup)
        /// `EventLoopGroup` will be created by the client. When `syncShutdown` is called, created `EventLoopGroup` will be shut down as well.
        case useAWSClientShared
    }

    let credentialProvider: CredentialProvider

    let signingName: String

    let apiVersion: String

    let amzTarget: String?

    let service: String

    public let endpoint: String

    public let region: Region

    let serviceProtocol: ServiceProtocol

    let serviceEndpoints: [String: String]

    let partitionEndpoint: String?

    let middlewares: [AWSServiceMiddleware]

    var possibleErrorTypes: [AWSErrorType.Type]

    let httpClient: AWSHTTPClient

    public let eventLoopGroup: EventLoopGroup

    private static let sharedEventLoopGroup: EventLoopGroup = createEventLoopGroup()

    /// create an eventLoopGroup
    static func createEventLoopGroup() -> EventLoopGroup {
        #if canImport(Network)
            if #available(OSX 10.15, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
                return NIOTSEventLoopGroup()
            }
        #endif
        return MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }

    /// Initialize an AWSClient struct
    /// - parameters:
    ///     - accessKeyId: Public access key provided by AWS
    ///     - secretAccessKey: Private access key provided by AWS
    ///     - sessionToken: Token provided by STS.AssumeRole() which allows access to another AWS account
    ///     - region: Region of server you want to communicate with
    ///     - amzTarget: "x-amz-target" header value
    ///     - service: Name of service endpoint
    ///     - signingName: Name that all AWS requests are signed with
    ///     - serviceProtocol: protocol of service (.json, .xml, .query etc)
    ///     - apiVersion: "Version" header value
    ///     - endpoint: Custom endpoint URL to use instead of standard AWS servers
    ///     - serviceEndpoints: Dictionary of region to endpoints URLs
    ///     - partitionEndpoint: Default endpoint to use
    ///     - middlewares: Array of middlewares to apply to requests and responses
    ///     - possibleErrorTypes: Array of possible error types that the client can throw
    ///     - eventLoopGroupProvider: EventLoopGroup to use. Use `useAWSClientShared` if the client shall manage its own EventLoopGroup.
    public init(accessKeyId: String? = nil, secretAccessKey: String? = nil, sessionToken: String? = nil, region givenRegion: Region?, amzTarget: String? = nil, service: String, signingName: String? = nil, serviceProtocol: ServiceProtocol, apiVersion: String, endpoint: String? = nil, serviceEndpoints: [String: String] = [:], partitionEndpoint: String? = nil, middlewares: [AWSServiceMiddleware] = [], possibleErrorTypes: [AWSErrorType.Type]? = nil, eventLoopGroupProvider: EventLoopGroupProvider) {
        if let _region = givenRegion {
            region = _region
        }
        else if let partitionEndpoint = partitionEndpoint, let reg = Region(rawValue: partitionEndpoint) {
            region = reg
        } else if let defaultRegion = ProcessInfo.processInfo.environment["AWS_DEFAULT_REGION"], let reg = Region(rawValue: defaultRegion) {
            region = reg
        } else {
            region = .useast1
        }

        // setup eventLoopGroup and httpClient
        switch eventLoopGroupProvider {
        case .shared(let providedEventLoopGroup):
            self.eventLoopGroup = providedEventLoopGroup
        case .useAWSClientShared:
            self.eventLoopGroup = AWSClient.sharedEventLoopGroup
        }
        self.httpClient = AWSClient.createHTTPClient(eventLoopGroup: eventLoopGroup)

        // create credentialProvider
        if let accessKey = accessKeyId, let secretKey = secretAccessKey {
            let credential = StaticCredential(accessKeyId: accessKey, secretAccessKey: secretKey, sessionToken: sessionToken)
            self.credentialProvider = StaticCredentialProvider(credential: credential, eventLoopGroup: self.eventLoopGroup)
        } else if let ecredential = EnvironmentCredential() {
            let credential = ecredential
            self.credentialProvider = StaticCredentialProvider(credential: credential, eventLoopGroup: self.eventLoopGroup)
        } else if let scredential = try? SharedCredential() {
            let credential = scredential
            self.credentialProvider = StaticCredentialProvider(credential: credential, eventLoopGroup: self.eventLoopGroup)
        } else {
            self.credentialProvider = MetaDataCredentialProvider(httpClient: self.httpClient)
        }

        self.signingName = signingName ?? service
        self.apiVersion = apiVersion
        self.service = service
        self.amzTarget = amzTarget
        self.serviceProtocol = serviceProtocol
        self.serviceEndpoints = serviceEndpoints
        self.partitionEndpoint = partitionEndpoint
        self.middlewares = middlewares
        self.possibleErrorTypes = possibleErrorTypes ?? []

        // work out endpoint, if provided use that otherwise
        if let endpoint = endpoint {
            self.endpoint = endpoint
        } else {
            let serviceHost: String
            if let serviceEndpoint = serviceEndpoints[region.rawValue] {
                serviceHost = serviceEndpoint
            } else if let partitionEndpoint = partitionEndpoint, let globalEndpoint = serviceEndpoints[partitionEndpoint] {
                serviceHost = globalEndpoint
            } else {
                serviceHost = "\(service).\(region.rawValue).amazonaws.com"
            }
            self.endpoint = "https://\(serviceHost)"
        }
    }

    deinit {
        do {
            try httpClient.syncShutdown()
        } catch {
            preconditionFailure("Error shutting down AWSClient: \(error.localizedDescription)")
        }
    }
}
// invoker
extension AWSClient {

    /// invoke HTTP request
    fileprivate func invoke(_ httpRequest: AWSHTTPRequest) -> EventLoopFuture<AWSHTTPResponse> {
        let futureResponse = httpClient.execute(request: httpRequest, timeout: .seconds(5))
        return futureResponse
    }

    /// create HTTPClient
    fileprivate static func createHTTPClient(eventLoopGroup: EventLoopGroup) -> AWSHTTPClient {
        #if canImport(Network)
        if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *), let nioTSEventLoopGroup = eventLoopGroup as? NIOTSEventLoopGroup {
            return NIOTSHTTPClient(eventLoopGroup: nioTSEventLoopGroup)
        }
        #endif
        return AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
    }

}

// public facing apis
extension AWSClient {

    /// send a request with an input object and return a future with an empty response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - input: Input object
    /// - returns:
    ///     Empty Future that completes when response is received
    public func send<Input: AWSEncodableShape>(operation operationName: String, path: String, httpMethod: String, input: Input) -> EventLoopFuture<Void> {

        return credentialProvider.getCredential().flatMapThrowing { credential in
            let signer = AWSSigner(credentials: credential, name: self.signingName, region: self.region.rawValue)
            let awsRequest = try self.createAWSRequest(
                        operation: operationName,
                        path: path,
                        httpMethod: httpMethod,
                        input: input)
            return awsRequest.createHTTPRequest(signer: signer)
        }.flatMap { request in
            return self.invoke(request)
        }.flatMapThrowing { response in
            return try self.validate(response: response)
        }
    }

    /// send an empty request and return a future with an empty response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    /// - returns:
    ///     Empty Future that completes when response is received
    public func send(operation operationName: String, path: String, httpMethod: String) -> EventLoopFuture<Void> {

        return credentialProvider.getCredential().flatMapThrowing { credential in
            let signer = AWSSigner(credentials: credential, name: self.signingName, region: self.region.rawValue)
            let awsRequest = try self.createAWSRequest(
                        operation: operationName,
                        path: path,
                        httpMethod: httpMethod)
            return awsRequest.createHTTPRequest(signer: signer)
        }.flatMap { request in
            return self.invoke(request)
        }.flatMapThrowing { response in
            return try self.validate(response: response)
        }
    }

    /// send an empty request and return a future with the output object generated from the response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    /// - returns:
    ///     Future containing output object that completes when response is received
    public func send<Output: AWSDecodableShape>(operation operationName: String, path: String, httpMethod: String) -> EventLoopFuture<Output> {

        return credentialProvider.getCredential().flatMapThrowing { credential in
            let signer = AWSSigner(credentials: credential, name: self.signingName, region: self.region.rawValue)
            let awsRequest = try self.createAWSRequest(
                        operation: operationName,
                        path: path,
                        httpMethod: httpMethod)
            return awsRequest.createHTTPRequest(signer: signer)
        }.flatMap { request in
            return self.invoke(request)
        }.flatMapThrowing { response in
            return try self.validate(operation: operationName, response: response)
        }
    }

    /// send a request with an input object and return a future with the output object generated from the response
    /// - parameters:
    ///     - operationName: Name of the AWS operation
    ///     - path: path to append to endpoint URL
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - input: Input object
    /// - returns:
    ///     Future containing output object that completes when response is received
    public func send<Output: AWSDecodableShape, Input: AWSEncodableShape>(operation operationName: String, path: String, httpMethod: String, input: Input) -> EventLoopFuture<Output> {

        return credentialProvider.getCredential().flatMapThrowing { credential in
            let signer = AWSSigner(credentials: credential, name: self.signingName, region: self.region.rawValue)
            let awsRequest = try self.createAWSRequest(
                        operation: operationName,
                        path: path,
                        httpMethod: httpMethod,
                        input: input)
            return awsRequest.createHTTPRequest(signer: signer)
        }.flatMap { request in
            return self.invoke(request)
        }.flatMapThrowing { response in
            return try self.validate(operation: operationName, response: response)
        }
    }

    /// generate a signed URL
    /// - parameters:
    ///     - url : URL to sign
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - expires: How long before the signed URL expires
    /// - returns:
    ///     A signed URL
    public func signURL(url: URL, httpMethod: String, expires: Int = 86400) -> EventLoopFuture<URL> {
        return signer.map { signer in signer.signURL(url: url, method: HTTPMethod(rawValue: httpMethod), expires: expires) }
    }
}

// request creator
extension AWSClient {

    var signer: EventLoopFuture<AWSSigner> {
        return credentialProvider.getCredential().map { credential in
            return AWSSigner(credentials: credential, name: self.signingName, region: self.region.rawValue)
        }
    }

    internal func createAWSRequest(operation operationName: String, path: String, httpMethod: String) throws -> AWSRequest {

        guard let url = URL(string: "\(endpoint)\(path)"), let _ = url.host else {
            throw RequestError.invalidURL("\(endpoint)\(path) must specify url host and scheme")
        }

        return try AWSRequest(
            region: region,
            url: url,
            serviceProtocol: serviceProtocol,
            operation: operationName,
            httpMethod: httpMethod,
            httpHeaders: [:],
            body: .empty
        ).applyMiddlewares(middlewares)
    }

    internal func createAWSRequest<Input: AWSEncodableShape>(operation operationName: String, path: String, httpMethod: String, input: Input) throws -> AWSRequest {
        var headers: [String: Any] = [:]
        var path = path
        var body: Body = .empty
        var queryParams: [(key:String, value:Any)] = []

        // validate input parameters
        try input.validate()

        guard let baseURL = URL(string: "\(endpoint)"), let _ = baseURL.host else {
            throw RequestError.invalidURL("\(endpoint) must specify url host and scheme")
        }

        // set x-amz-target header
        if let target = amzTarget {
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
                    if let array = value as? QueryEncodableArray {
                        array.queryEncoded.forEach { queryParams.append((key:location, value:$0)) }
                    } else {
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

        switch serviceProtocol.type {
        case .json, .restjson:
            if let payload = (Input.self as? AWSShapeWithPayload.Type)?.payloadPath {
                if let payloadBody = mirror.getAttribute(forKey: payload) {
                    switch payloadBody {
                    case let awsPayload as AWSPayload:
                        body = Body(awsPayload)
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
            dict["Version"] = apiVersion

            switch httpMethod {
            case "GET":
                queryParams.append(contentsOf: dict.map {(key:$0.key, value:$0)})
            default:
                if let urlEncodedQueryParams = urlEncodeQueryParams(fromDictionary: dict) {
                    body = .text(urlEncodedQueryParams)
                }
            }

        case .restxml:
            if let payload = (Input.self as? AWSShapeWithPayload.Type)?.payloadPath {
                if let payloadBody = mirror.getAttribute(forKey: payload) {
                    switch payloadBody {
                    case let awsPayload as AWSPayload:
                        body = Body(awsPayload)
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

        case .other(let proto):
            switch proto.lowercased() {
            case "ec2":
                var params = try input.encodeAsQuery(flattenArrays: true)
                params["Action"] = operationName
                params["Version"] = apiVersion
                if let urlEncodedQueryParams = urlEncodeQueryParams(fromDictionary: params) {
                    body = .text(urlEncodedQueryParams)
                }
            default:
                break
            }
        }

        guard let parsedPath = URLComponents(string: path) else {
            throw RequestError.invalidURL("\(endpoint)\(path)")
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
            urlString.append(queryParams.map{"\($0.key)=\(urlEncodeQueryParam("\($0.value)"))"}.sorted().joined(separator:"&"))
        }

        guard let url = URL(string: urlString) else {
            throw RequestError.invalidURL("\(urlString)")
        }

        return try AWSRequest(
            region: region,
            url: url,
            serviceProtocol: serviceProtocol,
            operation: operationName,
            httpMethod: httpMethod,
            httpHeaders: headers,
            body: body
        ).applyMiddlewares(middlewares)
    }

    static let queryAllowedCharacters = CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/")

    fileprivate func urlEncodeQueryParam(_ value: String) -> String {
        return value.addingPercentEncoding(withAllowedCharacters: AWSClient.queryAllowedCharacters) ?? value
    }

    fileprivate func urlEncodeQueryParams(fromDictionary dict: [String:Any]) -> String? {
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
extension AWSClient {

    /// Validate the operation response and return a response shape
    internal func validate<Output: AWSDecodableShape>(operation operationName: String, response: AWSHTTPResponse) throws -> Output {
        var raw: Bool = false
        var payloadKey: String? = (Output.self as? AWSShapeWithPayload.Type)?.payloadPath

        // if response has a payload with encoding info
        if let payloadPath = payloadKey, let encoding = Output.getEncoding(for: payloadPath) {
            // is payload raw
            if case .blob = encoding.shapeEncoding, (200..<300).contains(response.status.code) {
                raw = true
            }
            // get CodingKey string for payload to insert in output
            if let location = encoding.location, case .body(let name) = location {
                payloadKey = name
            }
        }

        var awsResponse = try AWSResponse(from: response, serviceProtocolType: serviceProtocol.type, raw: raw)

        // do we need to fix up the response before processing it
        for middleware in middlewares {
            awsResponse = try middleware.chain(response: awsResponse)
        }

        try validateCode(response: awsResponse)

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
                let node = XML.Element(name: statusCodeParam, stringValue: "\(response.status.code)")
                outputNode.addChild(node)
            }
            return try XMLDecoder().decode(Output.self, from: outputNode)

        case .buffer(let byteBuffer):
            if let payloadKey = payloadKey {
                // convert ByteBuffer to Data
                let data = byteBuffer.getData(at: byteBuffer.readerIndex, length: byteBuffer.readableBytes)
                outputDict[payloadKey] = data
            }
            decoder.dataDecodingStrategy = .raw

        case .text(let text):
            if let payloadKey = payloadKey {
                outputDict[payloadKey] = text
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
            outputDict[statusCodeParam] = response.status.code
        }

        return try decoder.decode(Output.self, from: outputDict)
    }

    /// validate response without returning an output shape
    internal func validate(response: AWSHTTPResponse) throws {
        let awsResponse = try AWSResponse(from: response, serviceProtocolType: serviceProtocol.type)
        try validateCode(response: awsResponse)
    }

    /// validate http status code. If it is an error then throw an Error object
    private func validateCode(response: AWSResponse) throws {
        guard (200..<300).contains(response.status.code) else {
            throw createError(for: response)
        }
    }

    private func createError(for response: AWSResponse) -> Error {
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

        switch serviceProtocol.type {
        case .query:
            guard case .xml(var element) = response.body else { break }
            if let errors = element.elements(forName: "Errors").first {
                element = errors
            }
            guard let errorElement = element.elements(forName: "Error").first else { break }
            errorMessage = try? XMLDecoder().decode(QueryError.self, from: errorElement)

        case .restxml:
            guard case .xml(var element) = response.body else { break }
            if let error = element.elements(forName: "Error").first {
                element = error
            }
            errorMessage = try? XMLDecoder().decode(XMLError.self, from: element)

        case .restjson:
            guard case .json(let data) = response.body else { break }
            errorMessage = try? JSONDecoder().decode(RESTJSONError.self, from: data)
            if errorMessage?.code == nil {
                errorMessage?.code = response.headers["x-amzn-ErrorType"] as? String
            }

        case .json:
            guard case .json(let data) = response.body else { break }
            errorMessage = try? JSONDecoder().decode(JSONError.self, from: data)

        case .other(let service):
            if service == "ec2" {
                guard case .xml(var element) = response.body else { break }
                if let errors = element.elements(forName: "Errors").first {
                    element = errors
                }
                guard let errorElement = element.elements(forName: "Error").first else { break }
                errorMessage = try? XMLDecoder().decode(QueryError.self, from: errorElement)
            }
            break
        }

        if let errorMessage = errorMessage, let code = errorMessage.code {
            for errorType in possibleErrorTypes {
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

        let rawBodyString = response.body.asString()
        return AWSError(statusCode: response.status, message: errorMessage?.message ?? "Unhandled Error. Response Code: \(response.status.code)", rawBody: rawBodyString ?? "")
    }
}

protocol ErrorMessage {
    var code: String? {get set}
    var message: String {get set}
}

extension AWSClient.RequestError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidURL(let urlString):
            return """
            The request url \(urlString) is invalid format.
            This error is internal. So please make a issue on https://github.com/swift-aws/aws-sdk-swift/issues to solve it.
            """
        }
    }
}

protocol QueryEncodableArray {
    var queryEncoded: [String] { get }
}

extension Array : QueryEncodableArray {
    var queryEncoded: [String] { return self.map{ "\($0)" }}
}
