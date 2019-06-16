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

extension String {
    public static let uriAWSQueryAllowed: [String] = ["&", "\'", "(", ")", "-", ".", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "=", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"]
}

/// Convenience shorthand for `EventLoopFuture`.
public typealias Future = EventLoopFuture

public struct InputContext {
    let Shape: AWSShape.Type
    let input: AWSShape
}

public struct AWSClient {

    public enum RequestError: Error {
        case invalidURL(String)
    }

    let signer: Signers.V4

    let apiVersion: String

    let amzTarget: String?

    let _endpoint: String?

    let serviceProtocol: ServiceProtocol

    let serviceEndpoints: [String: String]

    let partitionEndpoint: String?

    public let middlewares: [AWSRequestMiddleware]

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
        return "\(signer.service).\(signer.region.rawValue).amazonaws.com"
    }

    public static let eventGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    public init(accessKeyId: String? = nil, secretAccessKey: String? = nil, region givenRegion: Region?, amzTarget: String? = nil, service: String, serviceProtocol: ServiceProtocol, apiVersion: String, endpoint: String? = nil, serviceEndpoints: [String: String] = [:], partitionEndpoint: String? = nil, middlewares: [AWSRequestMiddleware] = [], possibleErrorTypes: [AWSErrorType.Type]? = nil) {
        let credential: CredentialProvider
        if let accessKey = accessKeyId, let secretKey = secretAccessKey {
            credential = Credential(accessKeyId: accessKey, secretAccessKey: secretKey)
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

        self.signer = Signers.V4(credential: credential, region: region, service: service, endpoint: endpoint)
        self.apiVersion = apiVersion
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
        let client = createHTTPClient(for: nioRequest)
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

    private func createHTTPClient(for nioRequest: Request) -> HTTPClient {
        let client: HTTPClient
        if let _ = self._endpoint {
            client = HTTPClient(hostname: nioRequest.head.host!, port: nioRequest.head.port ?? 443)
        } else {
            client = HTTPClient(hostname: nioRequest.head.hostWithPort!, port: 443)
        }
        return client
    }
}

// public facing apis
extension AWSClient {
    public func send<Input: AWSShape>(operation operationName: String, path: String, httpMethod: String, input: Input) throws -> Future<Void> {

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
                return try self.validateCode(response: response)
            }
    }

    public func send(operation operationName: String, path: String, httpMethod: String) throws -> Future<Void> {

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
                return try self.validateCode(response: response)
            }
    }

    public func send<Output: AWSShape>(operation operationName: String, path: String, httpMethod: String) throws -> Future<Output> {

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

    public func send<Output: AWSShape, Input: AWSShape>(operation operationName: String, path: String, httpMethod: String, input: Input)
        throws -> Future<Output> {

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
            service: signer.service,
            amzTarget: amzTarget,
            operation: operationName,
            httpMethod: httpMethod,
            httpHeaders: [:],
            body: .empty,
            middlewares: middlewares
        )
    }

    fileprivate func createAWSRequest<Input: AWSShape>(operation operationName: String, path: String, httpMethod: String, input: Input) throws -> AWSRequest {
        var headers: [String: String] = [:]
        var path = path
        var urlComponents = URLComponents()
        var body: Body = .empty
        var queryParams: [String: Any] = [:]

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
                headers[key] = "\(attr)"
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
            if let payload = Input.payloadPath, let payloadBody = mirror.getAttribute(forKey: payload.toSwiftVariableCase()) {
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
            if let payload = Input.payloadPath, let payloadBody = mirror.getAttribute(forKey: payload.toSwiftVariableCase()) {
                switch payloadBody {
                case is AWSShape:
                    let node = try AWSShapeEncoder().xml(input)
                    // cannot use payload path to find XmlElement as it may have a different. Need to translate this to the tag used in the Encoder
                    guard let member = Input._members.first(where: {$0.label == payload}) else { throw AWSClientError.unsupportedOperation(message: "The shape is requesting a payload that does not exist")}
                    guard let element = node.elements(forName: member.location?.name ?? member.label).first else { throw AWSClientError.missingParameter(message: "Payload is missing")}
                    // if shape has an xml namespace apply it to the element
                    if let xmlNamespace = Input._xmlNamespace {
                        element.addNamespace(XMLNode.namespace(withName: "", stringValue: xmlNamespace) as! XMLNode)
                    }
                    body = .xml(element)
                default:
                    body = Body(anyValue: payloadBody)
                }
                headers.removeValue(forKey: payload.toSwiftVariableCase())
            } else {
                // only include the body if there are members that are output in the body.
                if Input.hasEncodableBody {
                    body = .xml(try AWSShapeEncoder().xml(input))
                }
            }

        case .other(let proto):
            switch proto.lowercased() {
            case "ec2":
                var params = AWSShapeEncoder().query(input)
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
            service: signer.service,
            amzTarget: amzTarget,
            operation: operationName,
            httpMethod: httpMethod,
            httpHeaders: headers,
            body: body,
            middlewares: middlewares
        )
    }

    fileprivate func urlEncodeQueryParams(fromDictionary dict: [String:Any]) -> String? {
        var components = URLComponents()
        components.queryItems = urlQueryItems(fromDictionary: dict)
        if components.queryItems != nil, let url = components.url {
            return url.query
        }
        return nil
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

    fileprivate func validate<Output: AWSShape>(operation operationName: String, response: Response) throws -> Output {

        try validateCode(response: response, members: Output._members)

        let responseBody = try validateBody(
            for: response,
            payloadPath: Output.payloadPath,
            members: Output._members
        )
        
        let decoder = DictionaryDecoder()

        var responseHeaders: [String: String] = [:]
        for (key, value) in response.head.headers {
            responseHeaders[key.description] = value
        }

        var outputDict: [String: Any] = [:]
        switch responseBody {
        case .json(let data):
            outputDict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] ?? [:]
            decoder.dataDecodingStrategy = .base64

        case .xml(let node):
            var outputNode = node
            if let child = node.children?.first as? XMLElement, (node.name == operationName + "Response" && child.name == operationName + "Result") {
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

        for (key, value) in response.head.headers {
            let headerParams = Output.headerParams
            if let index = headerParams.firstIndex(where: { $0.key.lowercased() == key.description.lowercased() }) {
                if let number = Double(value) {
                    outputDict[headerParams[index].key] = number.truncatingRemainder(dividingBy: 1) == 0 ? Int(number) : number
                } else if let boolean = Bool(value) {
                    outputDict[headerParams[index].key] = boolean
                } else {
                    outputDict[headerParams[index].key] = value
                }
            }
        }

        return try decoder.decode(Output.self, from: outputDict)
    }

    private func validateCode(response: Response, members: [AWSShapeMember] = []) throws {
        guard (200..<300).contains(response.head.status.code) else {
            let responseBody = try validateBody(
                for: response,
                payloadPath: nil,
                members: members
            )
            throw createError(for: response, withComputedBody: responseBody, withRawData: response.body)
        }
    }

    private func validateBody(for response: Response, payloadPath: String?, members: [AWSShapeMember]) throws -> Body {
        var responseBody: Body = .empty
        let data = response.body

        if data.isEmpty {
            return responseBody
        }

        if payloadPath != nil {
            return .buffer(data)
        }

        switch serviceProtocol.type {
        case .json, .restjson:
            if let cType = response.contentType(), cType.contains("hal+json") {
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
                responseBody = .json(try JSONSerialization.data(withJSONObject: dictionary, options: []))

            } else {
                responseBody = .json(data)
            }

        case .restxml, .query:
            let xmlDocument = try XMLDocument(data: data)
            if let element = xmlDocument.rootElement() {
                responseBody = .xml(element)
            }

        case .other(let proto):
            switch proto.lowercased() {
            case "ec2":
                let xmlDocument = try XMLDocument(data: data)
                if let element = xmlDocument.rootElement() {
                    responseBody = .xml(element)
                }

            default:
                responseBody = .buffer(data)
            }
        }

        return responseBody
    }

    private func createError(for response: Response, withComputedBody body: Body, withRawData data: Data) -> Error {
        let bodyDict: [String: Any] = (try? body.asDictionary()) ?? [:]

        var code: String?
        var message: String?

        switch serviceProtocol.type {
        case .query:
            guard let xmlDocument = try? XMLDocument(data: data) else { break }
            guard let element = xmlDocument.rootElement() else { break }
            guard let error = element.elements(forName: "Error").first else { break }
            code = error.elements(forName: "Code").first?.stringValue
            message = error.elements(forName: "Message").first?.stringValue

        case .restxml:
            guard let xmlDocument = try? XMLDocument(data: data) else { break }
            guard let element = xmlDocument.rootElement() else { break }
            code = element.elements(forName: "Code").first?.stringValue
            message = element.children?.filter({$0.name != "Code"}).map({"\($0.name!): \($0.stringValue!)"}).joined(separator: ", ")

        case .restjson:
            code = response.head.headers.filter( { $0.name == "x-amzn-ErrorType"}).first?.value
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

        return AWSError(message: message ?? "Unhandled Error. Response Code: \(response.head.status.code)", rawBody: String(data: data, encoding: .utf8) ?? "")
    }
}

// debug request validator
#if DEBUG
extension AWSClient {

    func debugValidateCode(response: Response) throws {
        return try validateCode(response: response)
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
