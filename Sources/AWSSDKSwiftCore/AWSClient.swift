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

    let signer: AWSSigner
    let credentialProvider: CredentialProvider

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
            if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
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
    public convenience init(accessKeyId: String? = nil, secretAccessKey: String? = nil, sessionToken: String? = nil, region givenRegion: Region?, amzTarget: String? = nil, service: String, signingName: String? = nil, serviceProtocol: ServiceProtocol, apiVersion: String, endpoint: String? = nil, serviceEndpoints: [String: String] = [:], partitionEndpoint: String? = nil, middlewares: [AWSServiceMiddleware] = [], possibleErrorTypes: [AWSErrorType.Type]? = nil, eventLoopGroupProvider: EventLoopGroupProvider) {
        
        // 1. get eventLoopGroup
        let eventloopGroup: EventLoopGroup
        switch eventLoopGroupProvider {
        case .shared(let loopGroup):
            eventloopGroup = loopGroup
        case .useAWSClientShared:
            eventloopGroup = AWSClient.sharedEventLoopGroup
        }
        let httpClient = AWSClient.createHTTPClient(eventLoopGroup: eventloopGroup)
        
        // 2. check credential chain
        let credentialProvider = CredentialChain.createProvider(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            sessionToken: sessionToken,
            eventLoopGroup: eventloopGroup,
            httpClient: httpClient)
        
        // 3. get endpoint
        let _region: Region
        if let region = givenRegion {
            _region = region
        }
        else if let partitionEndpoint = partitionEndpoint, let reg = Region(rawValue: partitionEndpoint) {
            _region = reg
        } else if let defaultRegion = ProcessInfo.processInfo.environment["AWS_DEFAULT_REGION"], let reg = Region(rawValue: defaultRegion) {
            _region = reg
        } else {
            _region = .useast1
        }
        
        // 4. get endpoint
        let _endpoint: String
        if let endpoint = endpoint {
            _endpoint = endpoint
        } else {
            let serviceHost: String
            if let serviceEndpoint = serviceEndpoints[_region.rawValue] {
                serviceHost = serviceEndpoint
            } else if let partitionEndpoint = partitionEndpoint, let globalEndpoint = serviceEndpoints[partitionEndpoint] {
                serviceHost = globalEndpoint
            } else {
                serviceHost = "\(service).\(_region.rawValue).amazonaws.com"
            }
            _endpoint = "https://\(serviceHost)"
        }
        
        self.init(credentialProvider: credentialProvider,
                  region: _region,
                  amzTarget: amzTarget,
                  service: service,
                  signingName: signingName,
                  serviceProtocol: serviceProtocol,
                  apiVersion: apiVersion,
                  endpoint: _endpoint,
                  serviceEndpoints: serviceEndpoints,
                  partitionEndpoint: partitionEndpoint,
                  middlewares: middlewares,
                  possibleErrorTypes: possibleErrorTypes ?? [],
                  eventLoopGroup: eventloopGroup,
                  httpClient: httpClient)
    }
  
    public init(credentialProvider: CredentialProvider,
                region givenRegion: Region,
                amzTarget: String?,
                service: String,
                signingName: String?,
                serviceProtocol: ServiceProtocol,
                apiVersion: String,
                endpoint: String,
                serviceEndpoints: [String: String],
                partitionEndpoint: String?,
                middlewares: [AWSServiceMiddleware],
                possibleErrorTypes: [AWSErrorType.Type],
                eventLoopGroup: EventLoopGroup,
                httpClient: AWSHTTPClient) {
        assert(eventLoopGroup === httpClient.eventLoopGroup)

        self.apiVersion         = apiVersion
        self.amzTarget          = amzTarget
        self.service            = service
        self.endpoint           = endpoint
        self.region             = givenRegion
        self.serviceProtocol    = serviceProtocol
        self.serviceEndpoints   = serviceEndpoints
        self.partitionEndpoint  = partitionEndpoint
        self.middlewares        = middlewares
        self.possibleErrorTypes = possibleErrorTypes
        
        self.signer = AWSSigner(name: signingName ?? service, region: region.rawValue)
        self.credentialProvider = credentialProvider

        self.eventLoopGroup     = eventLoopGroup
        self.httpClient         = httpClient
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

    /// invoke HTTP request using AsyncHTTPClient
    fileprivate func invoke(_ httpRequest: AWSHTTPRequest) -> Future<AWSHTTPResponse> {
        let futureResponse = httpClient.execute(request: httpRequest, timeout: .seconds(5))
        return futureResponse
    }

    /// create HTTPClient
    fileprivate static func createHTTPClient(eventLoopGroup: EventLoopGroup) -> AWSHTTPClient {
        #if canImport(Network)
        if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *), eventLoopGroup is NIOTSEventLoopGroup {
            return NIOTSHTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
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
    public func send<Input: AWSShape>(operation operationName: String, path: String, httpMethod: String, input: Input) -> Future<Void> {
        return self.credentialProvider.getCredential()
            .flatMapThrowing { credential in
                let awsRequest = try self.createAWSRequest(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    input: input)
                return self.signRequest(awsRequest, with: credential)
            }
            .flatMap { request in
                return self.invoke(request)
            }
            .flatMapThrowing { response in
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
        return self.credentialProvider.getCredential()
            .flatMapThrowing { credential in
                let awsRequest = try self.createAWSRequest(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod)
                return self.signRequest(awsRequest, with: credential)
            }
            .flatMap { request in
                return self.invoke(request)
            }
            .flatMapThrowing { response in
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
        return self.credentialProvider.getCredential()
            .flatMapThrowing { credential in
                let awsRequest = try self.createAWSRequest(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod)
                return self.signRequest(awsRequest, with: credential)
            }
            .flatMap { request in
                return self.invoke(request)
            }
            .flatMapThrowing { response in
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
        return self.credentialProvider.getCredential()
            .flatMapThrowing { credential in
                let awsRequest = try self.createAWSRequest(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    input: input)
                return self.signRequest(awsRequest, with: credential)
            }
            .flatMap { request in
                return self.invoke(request)
            }
            .flatMapThrowing { response in
                return try self.validate(operation: operationName, response: response)
            }
    }
}

// request creator
extension AWSClient {

    func signRequest(_ awsRequest: AWSRequest, with credential: Credential) -> AWSHTTPRequest {
        
        #warning("we need a way if we don't have credentials here. is that even possible?")

        switch (awsRequest.httpMethod, self.serviceProtocol.type) {
        case ("GET",  .restjson), ("HEAD", .restjson):
            return awsRequest.withSignedHeader(signer, credential: credential)

        case ("GET",  _), ("HEAD", _):
            if awsRequest.httpHeaders.count > 0 {
                return awsRequest.withSignedHeader(signer, credential: credential)
            }
            return awsRequest.withSignedURL(signer, credential: credential)

        default:
            return awsRequest.withSignedHeader(signer, credential: credential)
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
    internal func validate<Output: AWSShape>(operation operationName: String, response: AWSHTTPResponse) throws -> Output {
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
                        let properties : [[String: Any]] = representations.map({
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
                                    
                                    //
                                    // this is a hack to wait...
                                    //
                                    while dict[name] == nil {
                                        _ = self.credentialProvider.getCredential()
                                            .flatMapThrowing { credential in
                                                let signedHeaders = self.signer.signHeaders(with: credential, url: url, method: .GET)
                                                return AWSHTTPRequest(url: url, method: .GET, headers: signedHeaders, body: nil)
                                            }
                                            .flatMap { (request) in
                                                return self.invoke(request)
                                            }
                                            .flatMapThrowing{ res in
                                                if let body = res.body, let bodyData = body.getData(at: body.readerIndex, length: body.readableBytes, byteTransferStrategy: .noCopy) {
                                                    let representaion = try Representation().from(json: bodyData)
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
