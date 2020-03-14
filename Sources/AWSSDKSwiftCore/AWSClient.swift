//
//  Client.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/03/13.
//
//

import AsyncHTTPClient
import NIO
import NIOHTTP1
import NIOTransportServices
import class  Foundation.ProcessInfo
import class  Foundation.JSONSerialization
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.URL
import struct Foundation.URLComponents
import struct Foundation.URLQueryItem
import struct Foundation.CharacterSet

/// Convenience shorthand for `EventLoopFuture`.
@available(*, deprecated, message: "Use the EventLoopFuture directly")
public typealias Future = EventLoopFuture

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
    public func send<Input: AWSShape>(operation operationName: String, path: String, httpMethod: String, input: Input) -> EventLoopFuture<Void> {

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
    public func send<Output: AWSShape>(operation operationName: String, path: String, httpMethod: String) -> EventLoopFuture<Output> {

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
    public func send<Output: AWSShape, Input: AWSShape>(operation operationName: String, path: String, httpMethod: String, input: Input) -> EventLoopFuture<Output> {

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

        guard let url = URL(string: "\(endpoint)\(path)"), let _ = url.hostWithPort else {
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

    internal func createAWSRequest<Input: AWSShape>(operation operationName: String, path: String, httpMethod: String, input: Input) throws -> AWSRequest {
        var headers: [String: Any] = [:]
        var path = path
        var urlComponents = URLComponents()
        var body: Body = .empty
        var queryParams: [String: Any] = [:]

        // validate input parameters
        try input.validate()

        guard let baseURL = URL(string: "\(endpoint)"), let _ = baseURL.hostWithPort else {
            throw RequestError.invalidURL("\(endpoint) must specify url host and scheme")
        }

        urlComponents.scheme = baseURL.scheme
        urlComponents.host = baseURL.host
        urlComponents.port = baseURL.port

        // set x-amz-target header
        if let target = amzTarget {
            headers["x-amz-target"] = "\(target).\(operationName)"
        }

        // TODO should replace with Encodable
        let mirror = Mirror(reflecting: input)
        var memberVariablesCount = mirror.children.count

        let headerMemberParams = Input.headerParams
        memberVariablesCount -= headerMemberParams.count
        for (key, value) in headerMemberParams {
            if let attr = mirror.getAttribute(forKey: value) {
                headers[key] = attr
            }
        }

        let queryMemberParams = Input.queryParams
        memberVariablesCount -= queryMemberParams.count
        for (key, value) in queryMemberParams {
            if let attr = mirror.getAttribute(forKey: value) {
                queryParams[key] = "\(attr)"
            }
        }

        let pathMemberParams = Input.pathParams
        memberVariablesCount -= pathMemberParams.count
        for (key, value) in pathMemberParams {
            if let attr = mirror.getAttribute(forKey: value) {
                path = path
                    .replacingOccurrences(of: "{\(key)}", with: "\(attr)")
                    // percent-encode key which is part of the path
                    .replacingOccurrences(of: "{\(key)+}", with: "\(attr)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)
            }
        }

        switch serviceProtocol.type {
        case .json, .restjson:
            if let payload = Input.payloadPath {
                if let payloadBody = mirror.getAttribute(forKey: payload) {
                    switch payloadBody {
                    case is AWSShape:
                        let inputDictionary = try AWSShapeEncoder().dictionary(input)
                        let encoding = Input.getEncoding(for: payload)
                        guard let payloadDict = inputDictionary[encoding?.location?.name ?? payload] else {
                            throw AWSClientError.missingParameter(message: "Payload is missing")
                        }
                        body = .json(try JSONSerialization.data(withJSONObject: payloadDict))
                    default:
                        body = Body(anyValue: payloadBody)
                    }
                } else {
                    body = .empty
                }
            } else {
                // only include the body if there are members that are output in the body.
                if memberVariablesCount > 0 {
                    body = .json(try AWSShapeEncoder().json(input))
                }
            }

        case .query:
            var dict = try AWSShapeEncoder().query(input)

            dict["Action"] = operationName
            dict["Version"] = apiVersion

            switch httpMethod {
            case "GET":
                queryParams = queryParams.merging(dict) { $1 }
            default:
                if let urlEncodedQueryParams = urlEncodeQueryParams(fromDictionary: dict) {
                    body = .text(urlEncodedQueryParams)
                }
            }

        case .restxml:
            if let payload = Input.payloadPath {
                if let payloadBody = mirror.getAttribute(forKey: payload) {
                    switch payloadBody {
                    case is AWSShape:
                        let node = try AWSShapeEncoder().xml(input)
                        let encoding = Input.getEncoding(for: payload)
                        guard let element = node.elements(forName: encoding?.location?.name ?? payload).first else {
                            throw AWSClientError.missingParameter(message: "Payload is missing")
                        }
                        // if shape has an xml namespace apply it to the element
                        if let xmlNamespace = Input._xmlNamespace {
                            element.addNamespace(XML.Node.namespace(stringValue: xmlNamespace))
                        }
                        body = .xml(element)
                    default:
                        body = Body(anyValue: payloadBody)
                    }
                } else {
                    body = .empty
                }
            } else {
                // only include the body if there are members that are output in the body.
                if memberVariablesCount > 0 {
                    body = .xml(try AWSShapeEncoder().xml(input))
                }
            }

        case .other(let proto):
            switch proto.lowercased() {
            case "ec2":
                var params = try AWSShapeEncoder().query(input, flattenArrays: true)
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
        urlComponents.path = parsedPath.path

        // construct query array
        var queryItems = urlQueryItems(fromDictionary: queryParams) ?? []

        // add new queries to query item array. These need to be added to the queryItems list instead of the queryParams dictionary as added nil items to a dictionary doesn't add a value.
        if let pathQueryItems = parsedPath.queryItems {
            for item in pathQueryItems {
                if let value = item.value {
                    queryItems.append(URLQueryItem(name:item.name, value:value))
                } else {
                    queryItems.append(URLQueryItem(name:item.name, value:""))
                }
            }
        }

        // only set queryItems if there exist any
        urlComponents.queryItems = queryItems.count == 0 ? nil : queryItems

        guard let url = urlComponents.url else {
            throw RequestError.invalidURL("\(endpoint)\(path)")
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
    fileprivate func urlEncodeQueryParams(fromDictionary dict: [String:Any]) -> String? {
        guard dict.count > 0 else {return nil}
        var query = ""
        let keys = Array(dict.keys).sorted()

        for iterator in keys.enumerated() {
            let value = dict[iterator.element]
            query += iterator.element + "=" + (String(describing: value ?? "").addingPercentEncoding(withAllowedCharacters: AWSClient.queryAllowedCharacters) ?? "")
            if iterator.offset < dict.count - 1 {
                query += "&"
            }
        }
        return query
    }

    fileprivate func urlQueryItems(fromDictionary dict: [String:Any]) -> [URLQueryItem]? {
        var queryItems: [URLQueryItem] = []
        let keys = Array(dict.keys).sorted()

        for key in keys {
            if let value = dict[key] {
                queryItems.append(URLQueryItem(name: key, value: String(describing: value)))
            } else {
                queryItems.append(URLQueryItem(name: key, value: ""))
            }
        }
        return queryItems.isEmpty ? nil : queryItems
    }
}

// response validator
extension AWSClient {

    /// Validate the operation response and return a response shape
    internal func validate<Output: AWSShape>(operation operationName: String, response: AWSHTTPResponse) throws -> Output {
        var raw: Bool = false
        var payloadKey: String? = Output.payloadPath

        // if response has a payload with encoding info
        if let payloadPath = Output.payloadPath, let encoding = Output.getEncoding(for: payloadPath) {
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
            return try XMLDecoder().decode(Output.self, from: outputNode)

        case .buffer(let data):
            if let payloadKey = payloadKey {
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
        let bodyDict: [String: Any] = (try? response.body.asDictionary()) ?? [:]

        var code: String?
        var message: String?

        switch serviceProtocol.type {
        case .query:
            guard case .xml(let element) = response.body else { break }
            guard let error = element.elements(forName: "Error").first else { break }
            code = error.elements(forName: "Code").first?.stringValue
            message = error.elements(forName: "Message").first?.stringValue

        case .restxml:
            guard case .xml(let element) = response.body else { break }
            code = element.elements(forName: "Code").first?.stringValue
            message = element.children(of:.element)?.filter({$0.name != "Code"}).map({"\($0.name!): \($0.stringValue!)"}).joined(separator: ", ")

        case .restjson:
            code = response.headers["x-amzn-ErrorType"] as? String
            message = bodyDict.filter({ $0.key.lowercased() == "message" }).first?.value as? String

        case .json:
            code = bodyDict["__type"] as? String
            message = bodyDict.filter({ $0.key.lowercased() == "message" }).first?.value as? String

        default:
            break
        }

        if let errorCode = code {
            for errorType in possibleErrorTypes {
                if let error = errorType.init(errorCode: errorCode, message: message) {
                    return error
                }
            }

            if let error = AWSClientError(errorCode: errorCode, message: message) {
                return error
            }

            if let error = AWSServerError(errorCode: errorCode, message: message) {
                return error
            }

            return AWSResponseError(errorCode: errorCode, message: message)
        }

        let rawBodyString : String?
        if let rawBody = response.body.asData() {
            rawBodyString = String(data: rawBody, encoding: .utf8)
        } else {
            rawBodyString = nil
        }
        return AWSError(statusCode: response.status, message: message ?? "Unhandled Error. Response Code: \(response.status.code)", rawBody: rawBodyString ?? "")
    }
}

extension AWSClient.RequestError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidURL(let urlString):
            return """
            The request url \(urlString) is invalid format.
            This error is internal. So please make a issue on https://github.com/noppoMan/aws-sdk-swift/issues to solve it.
            """
        }
    }
}

extension URL {
    var hostWithPort: String? {
        guard var host = self.host else {
            return nil
        }
        if let port = self.port {
            host+=":\(port)"
        }
        return host
    }
}
