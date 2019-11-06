//
//  Client.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/03/13.
//
//

import AsyncHTTPClient
import AWSSigner
import HypertextApplicationLanguage
import Foundation
import NIO
import NIOHTTP1
import NIOTransportServices

/// Convenience shorthand for `EventLoopFuture`.
public typealias Future = EventLoopFuture

/// Helper struct for ensuring atomic access to a structure
struct AtomicProperty<T> {
    private var _value: T
    private var lock = NSLock()

    public init(value: T) {
        _value = value
    }

    public var value: T {
        get {
            lock.lock()
            let value = _value
            lock.unlock()
            return value
        }
        set {
            lock.lock()
            _value = newValue
            lock.unlock()
        }
    }
}

/// This is the workhorse of aws-sdk-swift-core. You provide it with a `AWSShape` Input object, it converts it to `AWSRequest` which is then converted to a raw `HTTPClient` Request. This is then sent to AWS. When the response from AWS is received if it is successful it is converted to a `AWSResponse` which is then decoded to generate a `AWSShape` Output object. If it is not successful then `AWSClient` will throw an `AWSErrorType`.
public class AWSClient {

    public enum RequestError: Error {
        case invalidURL(String)
    }

    var signer: AtomicProperty<AWSSigner>

    let apiVersion: String

    let amzTarget: String?

    let service: String

    let endpoint: String

    public let region: Region

    let serviceProtocol: ServiceProtocol

    let serviceEndpoints: [String: String]

    let partitionEndpoint: String?

    let middlewares: [AWSServiceMiddleware]

    var possibleErrorTypes: [AWSErrorType.Type]

    public static let eventGroup: EventLoopGroup = createEventLoopGroup()

    /// create an eventLoopGroup
    static func createEventLoopGroup() -> EventLoopGroup {
        #if canImport(Network)
            if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
                return NIOTSEventLoopGroup()
            }
        #endif
        return MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }

    var usingNIOTransportServices: Bool {
        #if canImport(Network)
        if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *), AWSClient.eventGroup is NIOTSEventLoopGroup {
            return true
        }
        #endif
        return false
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
    public init(accessKeyId: String? = nil, secretAccessKey: String? = nil, sessionToken: String? = nil, region givenRegion: Region?, amzTarget: String? = nil, service: String, signingName: String? = nil, serviceProtocol: ServiceProtocol, apiVersion: String, endpoint: String? = nil, serviceEndpoints: [String: String] = [:], partitionEndpoint: String? = nil, middlewares: [AWSServiceMiddleware] = [], possibleErrorTypes: [AWSErrorType.Type]? = nil) {
        let credential: CredentialProvider
        if let accessKey = accessKeyId, let secretKey = secretAccessKey {
            credential = Credential(accessKeyId: accessKey, secretAccessKey: secretKey, sessionToken: sessionToken)
        } else if let ecredential = EnvironmentCredential() {
            credential = ecredential
        } else if let scredential = try? SharedCredential() {
            credential = scredential
        } else {
            // create an expired credential
            credential = ExpiringCredential(accessKeyId: "", secretAccessKey: "", expiration: Date.init(timeIntervalSince1970: 0))
        }

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

        self.signer = AtomicProperty(value: AWSSigner(credentials: credential, name: signingName ?? service, region: region.rawValue))
        self.apiVersion = apiVersion
        self.service = service
        //self._endpoint = endpoint
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

}
// invoker
extension AWSClient {

    /// invoke AWS request, create HTTP request from AWS request and then make request. Return response. Function chooses which HTTP client to use based
    fileprivate func invoke(_ awsRequest: AWSRequest, signer: AWSSigner) -> Future<HTTPResponseDescription> {
        do {
            if usingNIOTransportServices {
                let request: AWSHTTPClient.Request = try createHTTPRequest(awsRequest, signer: signer)
                return invokeAWSHTTPClient(request).map { $0 }
            } else {
                let request: AsyncHTTPClient.HTTPClient.Request = try createHTTPRequest(awsRequest, signer: signer)
                return invokeAsyncHTTPClient(request).map { $0 }
            }
        } catch {
            return AWSClient.eventGroup.next().makeFailedFuture(error)
        }
    }

    /// invoke HTTP request using AsyncHTTPClient
    fileprivate func invokeAsyncHTTPClient(_ httpRequest: AsyncHTTPClient.HTTPClient.Request) -> Future<AsyncHTTPClient.HTTPClient.Response> {
        let client = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .shared(AWSClient.eventGroup))
        let futureResponse = client.execute(request: httpRequest)

        futureResponse.whenComplete { _ in
            do {
                try client.syncShutdown()
            } catch {
                print("Error closing connection: \(error)")
            }
        }

        return futureResponse
    }

    /// invoke HTTP request using AWSSDKSwiftCore internal HTTPClient
    fileprivate func invokeAWSHTTPClient(_ httpRequest: AWSHTTPClient.Request) -> Future<AWSHTTPClient.Response> {
        let client = AWSHTTPClient(eventLoopGroupProvider: .shared(AWSClient.eventGroup))
        let futureResponse = client.connect(httpRequest)

        futureResponse.whenComplete { _ in
            do {
                try client.syncShutdown()
            } catch {
                print("Error closing connection: \(error)")
            }
        }

        return futureResponse
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
    public func send<Input: AWSShape>(operation operationName: String, path: String, httpMethod: String, input: Input) -> Future<Void> {

        return manageCredential().flatMapThrowing { signer in
            return (request: try self.createAWSRequest(
                        operation: operationName,
                        path: path,
                        httpMethod: httpMethod,
                        input: input),
                    signer: signer)
        }.flatMap { request in
            return self.invoke(request.request, signer: request.signer)
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
    public func send(operation operationName: String, path: String, httpMethod: String) -> Future<Void> {

        return manageCredential().flatMapThrowing { signer in
            return (request: try self.createAWSRequest(
                        operation: operationName,
                        path: path,
                        httpMethod: httpMethod),
                    signer: signer)
        }.flatMap { request in
            return self.invoke(request.request, signer: request.signer)
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
    public func send<Output: AWSShape>(operation operationName: String, path: String, httpMethod: String) -> Future<Output> {

        return manageCredential().flatMapThrowing { signer in
            return (request: try self.createAWSRequest(
                        operation: operationName,
                        path: path,
                        httpMethod: httpMethod),
                    signer: signer)
        }.flatMap { request in
            return self.invoke(request.request, signer: request.signer)
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
    public func send<Output: AWSShape, Input: AWSShape>(operation operationName: String, path: String, httpMethod: String, input: Input) -> Future<Output> {

        return manageCredential().flatMapThrowing { signer in
            return (request: try self.createAWSRequest(
                        operation: operationName,
                        path: path,
                        httpMethod: httpMethod,
                        input: input),
                    signer: signer)
        }.flatMap { request in
            return self.invoke(request.request, signer: request.signer)
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
    public func signURL(url: URL, httpMethod: String, expires: Int = 86400) -> URL {
        return signer.value.signURL(url: url, method: HTTPMethod(from: httpMethod), expires: expires)
    }
}

// request creator
extension AWSClient {

    func manageCredential() -> Future<AWSSigner> {
        #if os(Linux)
        let signer = self.signer.value
        if signer.credentials.nearExpiration() {
            do {
                return try MetaDataService.getCredential(eventLoopGroup: AWSClient.eventGroup).map { credential in
                    let signer = AWSSigner(credentials: credential, name: signer.name, region: signer.region)
                    self.signer.value = signer
                    return signer
                }
            } catch {
                // should not be crash
            }
        }
        #endif // os(Linux)
        return AWSClient.eventGroup.next().makeSucceededFuture(self.signer.value)
    }

    func createHTTPRequest<Request: HTTPRequestDescription>(_ awsRequest: AWSRequest, signer: AWSSigner) throws -> Request {
        // if credentials are empty don't sign request
        if signer.credentials.isEmpty() {
            return try awsRequest.toHTTPRequest()
        }

        switch awsRequest.httpMethod {
        case "GET", "HEAD":
            switch self.serviceProtocol.type {
            case .restjson:
                return try awsRequest.toHTTPRequestWithSignedHeader(signer: signer)
            default:
                return try awsRequest.toHTTPRequestWithSignedURL(signer: signer)
            }
        default:
            return try awsRequest.toHTTPRequestWithSignedHeader(signer: signer)
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

        for (key, value) in Input.headerParams {
            if let attr = mirror.getAttribute(forKey: value.toSwiftVariableCase()) {
                headers[key] = attr
            }
        }

        for (key, value) in Input.queryParams {
            if let attr = mirror.getAttribute(forKey: value.toSwiftVariableCase()) {
                queryParams[key] = "\(attr)"
            }
        }

        for (key, value) in Input.pathParams {
            if let attr = mirror.getAttribute(forKey: value.toSwiftVariableCase()) {
                path = path
                    .replacingOccurrences(of: "{\(key)}", with: "\(attr)")
                    // percent-encode key which is part of the path
                    .replacingOccurrences(of: "{\(key)+}", with: "\(attr)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)
            }
        }

        switch serviceProtocol.type {
        case .json, .restjson:
            if let payload = Input.payloadPath {
                if let payloadBody = mirror.getAttribute(forKey: payload.toSwiftVariableCase()) {
                    switch payloadBody {
                    case is AWSShape:
                        let inputDictionary = try AWSShapeEncoder().dictionary(input)
                        if let payloadDict = inputDictionary[payload] {
                            body = .json(try JSONSerialization.data(withJSONObject: payloadDict))
                        }
                    default:
                        body = Body(anyValue: payloadBody)
                    }
                    headers.removeValue(forKey: payload.toSwiftVariableCase())
                } else {
                    body = .empty
                }
            } else {
                // only include the body if there are members that are output in the body.
                if Input.hasEncodableBody {
                    body = .json(try AWSShapeEncoder().json(input))
                }
            }

        case .query:
            var dict = AWSShapeEncoder().query(input)

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
                if let payloadBody = mirror.getAttribute(forKey: payload.toSwiftVariableCase()) {
                    switch payloadBody {
                    case is AWSShape:
                        let node = try AWSShapeEncoder().xml(input)
                        // cannot use payload path to find XmlElement as it may have a different. Need to translate this to the tag used in the Encoder
                        guard let member = Input._members.first(where: {$0.label == payload}) else { throw AWSClientError.unsupportedOperation(message: "The shape is requesting a payload that does not exist")}
                        guard let element = node.elements(forName: member.location?.name ?? member.label).first else { throw AWSClientError.missingParameter(message: "Payload is missing")}
                        // if shape has an xml namespace apply it to the element
                        if let xmlNamespace = Input._xmlNamespace {
                            element.addNamespace(XML.Node.namespace(stringValue: xmlNamespace))
                        }
                        body = .xml(element)
                    default:
                        body = Body(anyValue: payloadBody)
                    }
                    headers.removeValue(forKey: payload.toSwiftVariableCase())
                } else {
                    body = .empty
                }
            } else {
                // only include the body if there are members that are output in the body.
                if Input.hasEncodableBody {
                    body = .xml(try AWSShapeEncoder().xml(input))
                }
            }

        case .other(let proto):
            switch proto.lowercased() {
            case "ec2":
                var params = AWSShapeEncoder().query(input, flattenLists: true)
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
    internal func validate<Output: AWSShape>(operation operationName: String, response: HTTPResponseDescription) throws -> Output {
        let raw: Bool
        if let payloadPath = Output.payloadPath, let member = Output.getMember(named: payloadPath), member.type == .blob {
            raw = true
        } else {
            raw = false
        }

        var awsResponse = try AWSResponse(from: response, serviceProtocolType: serviceProtocol.type, raw: raw)

        try validateCode(response: awsResponse)

        awsResponse = try hypertextApplicationLanguageProcess(response: awsResponse, members: Output._members)

        // do we need to fix up the response before processing it
        for middleware in middlewares {
            awsResponse = try middleware.chain(response: awsResponse)
        }

        let decoder = DictionaryDecoder()

        var outputDict: [String: Any] = [:]
        switch awsResponse.body {
        case .json(let data):
            outputDict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] ?? [:]
            // if payload path is set then the decode will expect the payload to decode to the relevant member variable
            if let payloadPath = Output.payloadPath {
                outputDict = [payloadPath : outputDict]
            }
            decoder.dataDecodingStrategy = .base64

        case .xml(let node):
            var outputNode = node
            // if payload path is set then the decode will expect the payload to decode to the relevant member variable. Most CloudFront responses have this.
            if let payloadPath = Output.payloadPath {
                // set output node name
                outputNode.name = payloadPath
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
            if let payload = Output.payloadPath {
                outputDict[payload] = data
            }

        case .text(let text):
            if let payload = Output.payloadPath {
                outputDict[payload] = text
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
    internal func validate(response: HTTPResponseDescription) throws {
        let awsResponse = try AWSResponse(from: response, serviceProtocolType: serviceProtocol.type)
        try validateCode(response: awsResponse)
    }

    /// validate http status code. If it is an error then throw an Error object
    private func validateCode(response: AWSResponse) throws {
        guard (200..<300).contains(response.status.code) else {
            throw createError(for: response)
        }
    }

    func hypertextApplicationLanguageProcess(response: AWSResponse, members: [AWSShapeMember]) throws -> AWSResponse {
        switch response.body {
        case .json(let data):
            if (response.headers["Content-Type"] as? String)?.contains("hal+json") == true {
                let representation = try Representation.from(json: data)
                var dictionary = representation.properties
                for rel in representation.rels {
                    guard let representations = try Representation.from(json: data).representations(for: rel) else {
                        continue
                    }

                    guard let hint = members.filter({ $0.location?.name == rel }).first else {
                        continue
                    }

                    switch hint.type {
                    case .list:
                        let properties : [[String: Any]] = try representations.map({
                            var props = $0.properties
                            var linkMap: [String: [Link]] = [:]

                            for link in $0.links {
                                let key = link.rel.camelCased(separator: ":")
                                if linkMap[key] == nil {
                                    linkMap[key] = []
                                }
                                linkMap[key]?.append(link)
                            }

                            for (key, links) in linkMap {
                                var dict: [String: Any] = [:]
                                for link in links {
                                    guard let name = link.name else { continue }
                                    guard let url = URL(string:endpoint + link.href) else { continue }
                                    //let head = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: endpoint + link.href)
                                    let signedHeaders = signer.value.signHeaders(url: url, method: .GET)
                                    let httpRequest = try AWSHTTPClient.Request(url: url, method: .GET, headers: signedHeaders)
                                    //let nioRequest = try nioRequestWithSignedHeader(AWSHTTPClient.Request(head: head, body: Data()))
                                    //
                                    // this is a hack to wait...
                                    ///
                                    while dict[name] == nil {
                                        _ = invokeAWSHTTPClient(httpRequest).flatMapThrowing{ res in
                                            if let body = res.bodyData {
                                                let representaion = try Representation().from(json: body)
                                                dict[name] = representaion.properties
                                            }
                                        }
                                    }
                                }
                                props[key] = dict
                            }

                            return props
                        })
                        dictionary[rel] = properties

                    default:
                        dictionary[rel] = representations.map({ $0.properties }).first ?? [:]
                    }
                }
                var response = response
                response.body = .json(try JSONSerialization.data(withJSONObject: dictionary, options: []))
                return response
            }
        default:
            break
        }
        return response
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
        return AWSError(message: message ?? "Unhandled Error. Response Code: \(response.status.code)", rawBody: rawBodyString ?? "")
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
