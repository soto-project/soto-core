//
//  Client.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/03/13.
//
//

import Foundation
import Dispatch
import NIO
import NIOHTTP1
import HypertextApplicationLanguage

/// Convenience shorthand for `EventLoopFuture`.
public typealias Future = EventLoopFuture

public struct AWSClient {

    public enum RequestError: Error {
        case invalidURL(String)
    }

    let signer: Signers.V4

    let apiVersion: String

    let amzTarget: String?

    let service: String

    let _endpoint: String?

    let serviceProtocol: ServiceProtocol

    let serviceEndpoints: [String: String]

    let partitionEndpoint: String?

    public let middlewares: [AWSServiceMiddleware]

    public var possibleErrorTypes: [AWSErrorType.Type]

    public var endpoint: String {
        if let givenEndpoint = self._endpoint {
            return givenEndpoint
        }
        return "https://\(serviceHost)"
    }

    public var serviceHost: String {
        if let serviceEndpoint = serviceEndpoints[signer.region.rawValue] {
            return serviceEndpoint
        }

        if let partitionEndpoint = partitionEndpoint, let globalEndpoint = serviceEndpoints[partitionEndpoint] {
            return globalEndpoint
        }
        return "\(service).\(signer.region.rawValue).amazonaws.com"
    }

    public static let eventGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    public init(accessKeyId: String? = nil, secretAccessKey: String? = nil, sessionToken: String? = nil, region givenRegion: Region?, amzTarget: String? = nil, service: String, signingName: String? = nil, serviceProtocol: ServiceProtocol, apiVersion: String, endpoint: String? = nil, serviceEndpoints: [String: String] = [:], partitionEndpoint: String? = nil, middlewares: [AWSServiceMiddleware] = [], possibleErrorTypes: [AWSErrorType.Type]? = nil) {
        let credential: CredentialProvider
        if let accessKey = accessKeyId, let secretKey = secretAccessKey {
            credential = Credential(accessKeyId: accessKey, secretAccessKey: secretKey, sessionToken: sessionToken)
        } else if let ecredential = EnvironementCredential() {
            credential = ecredential
        } else if let scredential = try? SharedCredential() {
            credential = scredential
        } else {
            credential = Credential(accessKeyId: "", secretAccessKey: "")
        }

        let region: Region
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

        self.signer = Signers.V4(credential: credential, region: region, signingName: signingName ?? service, endpoint: endpoint)
        self.apiVersion = apiVersion
        self.service = service
        self._endpoint = endpoint
        self.amzTarget = amzTarget
        self.serviceProtocol = serviceProtocol
        self.serviceEndpoints = serviceEndpoints
        self.partitionEndpoint = partitionEndpoint
        self.middlewares = middlewares
        self.possibleErrorTypes = possibleErrorTypes ?? []
    }

}
// invoker
extension AWSClient {
    fileprivate func invoke(_ nioRequest: Request) -> Future<Response> {
        let client = HTTPClient(hostname: nioRequest.head.hostWithPort!, port: nioRequest.head.port ?? 443)
        let futureResponse = client.connect(nioRequest)

        futureResponse.whenComplete { _ in
            client.close { error in
                if let error = error {
                    print("Error closing connection: \(error)")
                }
            }
        }

        return futureResponse
    }
}

// public facing apis
extension AWSClient {
    public func send<Input: AWSShape>(operation operationName: String, path: String, httpMethod: String, input: Input) -> Future<Void> {

        return signer.manageCredential().flatMapThrowing { _ in
                let awsRequest = try self.createAWSRequest(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod,
                    input: input
                )
                return try self.createNioRequest(awsRequest)
            }.flatMap { nioRequest in
                return self.invoke(nioRequest)
            }.flatMapThrowing { response in
                return try self.validate(response: response)
            }
    }

    public func send(operation operationName: String, path: String, httpMethod: String) -> Future<Void> {

        return signer.manageCredential().flatMapThrowing { _ in
                let awsRequest = try self.createAWSRequest(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod
                )
                return try self.createNioRequest(awsRequest)
            }.flatMap { nioRequest in
                return self.invoke(nioRequest)
            }.flatMapThrowing { response in
                return try self.validate(response: response)
            }
    }

    public func send<Output: AWSShape>(operation operationName: String, path: String, httpMethod: String) -> Future<Output> {

        return signer.manageCredential().flatMapThrowing { _ in
                let awsRequest = try self.createAWSRequest(
                    operation: operationName,
                    path: path,
                    httpMethod: httpMethod
                )
                return try self.createNioRequest(awsRequest)
            }.flatMap { nioRequest in
                return self.invoke(nioRequest)
            }.flatMapThrowing { response in
                return try self.validate(operation: operationName, response: response)
            }
    }

    public func send<Output: AWSShape, Input: AWSShape>(operation operationName: String, path: String, httpMethod: String, input: Input) -> Future<Output> {

            return signer.manageCredential().flatMapThrowing { _ in
                    let awsRequest = try self.createAWSRequest(
                        operation: operationName,
                        path: path,
                        httpMethod: httpMethod,
                        input: input
                    )
                    return try self.createNioRequest(awsRequest)
                }.flatMap { nioRequest in
                    return self.invoke(nioRequest)
                }.flatMapThrowing { response in
                    return try self.validate(operation: operationName, response: response)
                }
    }

    public func signURL(url: URL, httpMethod: String, expires: Int = 86400) -> URL {
        return signer.signedURL(url: url, method: httpMethod, expires: expires)
    }
}

// request creator
extension AWSClient {

    fileprivate func createNIORequestWithSignedURL(_ awsRequest: AWSRequest) throws -> Request {
        var nioRequest = try awsRequest.toNIORequest()

        guard let unsignedUrl = URL(string: nioRequest.head.uri), let hostWithPort = unsignedUrl.hostWithPort else {
            fatalError("nioRequest.head.uri is invalid.")
        }

        let signedURI = signer.signedURL(url: unsignedUrl, method: awsRequest.httpMethod)
        nioRequest.head.uri = signedURI.absoluteString
        nioRequest.head.headers.replaceOrAdd(name: "Host", value: hostWithPort)

        return nioRequest
    }

    fileprivate func createNIORequestWithSignedHeader(_ awsRequest: AWSRequest) throws -> Request {
        return try nioRequestWithSignedHeader(awsRequest.toNIORequest())
    }

    fileprivate func nioRequestWithSignedHeader(_ nioRequest: Request) throws -> Request {
        var nioRequest = nioRequest

        guard let url = URL(string: nioRequest.head.uri), let _ = url.hostWithPort else {
            throw RequestError.invalidURL("nioRequest.head.uri is invalid.")
        }

        // TODO avoid copying
        var headers: [String: String] = [:]
        for (key, value) in nioRequest.head.headers {
            headers[key.description] = value
        }

        // We need to convert from the NIO type to a string
        // when we sign the headers and attach the auth cookies
        //
        let method = "\(nioRequest.head.method)"

        let signedHeaders = signer.signedHeaders(
            url: url,
            headers: headers,
            method: method,
            bodyData: nioRequest.body
        )

        for (key, value) in signedHeaders {
            nioRequest.head.headers.replaceOrAdd(name: key, value: value)
        }

        return nioRequest
    }

    func createNioRequest(_ awsRequest: AWSRequest) throws -> Request {
        switch awsRequest.httpMethod {
        case "GET", "HEAD":
            switch self.serviceProtocol.type {
            case .restjson:
                return try createNIORequestWithSignedHeader(awsRequest)
            default:
                return try createNIORequestWithSignedURL(awsRequest)
            }
        default:
            return try createNIORequestWithSignedHeader(awsRequest)
        }
    }

    fileprivate func createAWSRequest(operation operationName: String, path: String, httpMethod: String) throws -> AWSRequest {

        guard let url = URL(string: "\(endpoint)\(path)"), let _ = url.hostWithPort else {
            throw RequestError.invalidURL("\(endpoint)\(path) must specify url host and scheme")
        }

        return AWSRequest(
            region: self.signer.region,
            url: url,
            serviceProtocol: serviceProtocol,
            service: service,
            amzTarget: amzTarget,
            operation: operationName,
            httpMethod: httpMethod,
            httpHeaders: [:],
            body: .empty,
            middlewares: middlewares
        )
    }

    fileprivate func createAWSRequest<Input: AWSShape>(operation operationName: String, path: String, httpMethod: String, input: Input) throws -> AWSRequest {
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

        return AWSRequest(
            region: self.signer.region,
            url: url,
            serviceProtocol: serviceProtocol,
            service: service,
            amzTarget: amzTarget,
            operation: operationName,
            httpMethod: httpMethod,
            httpHeaders: headers,
            body: body,
            middlewares: middlewares
        )
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

// debug request creator
#if DEBUG
extension AWSClient {

    func debugCreateAWSRequest<Input: AWSShape>(operation operationName: String, path: String, httpMethod: String, input: Input) throws -> AWSRequest {
        return try createAWSRequest(operation: operationName, path: path, httpMethod: httpMethod, input: input)
    }
}
#endif

// response validator
extension AWSClient {

    /// Validate the operation response and return a response shape
    fileprivate func validate<Output: AWSShape>(operation operationName: String, response: Response) throws -> Output {
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
    private func validate(response: Response) throws {
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
                                    let head = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: endpoint + link.href)
                                    let nioRequest = try nioRequestWithSignedHeader(Request(head: head, body: Data()))
                                    //
                                    // this is a hack to wait...
                                    ///
                                    while dict[name] == nil {
                                        _ = invoke(nioRequest).flatMapThrowing{ res in
                                            let representaion = try Representation().from(json: res.body)
                                            dict[name] = representaion.properties
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

// debug request validator
#if DEBUG
extension AWSClient {

    func debugValidate(response: Response) throws {
        try validate(response: response)
    }

    func debugValidate<Output: AWSShape>(operation operationName: String, response: Response) throws -> Output {
        return try validate(operation: operationName, response: response)
    }
}
#endif


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
