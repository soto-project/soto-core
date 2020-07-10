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
import NIO
import NIOHTTP1
import struct Foundation.URL
import struct Foundation.Date
import struct Foundation.Data
import struct Foundation.CharacterSet
import struct Foundation.URLComponents

/// Object encapsulating all the information needed to generate a raw HTTP request to AWS
public struct AWSRequest {
    public let region: Region
    public var url: URL
    public let serviceProtocol: ServiceProtocol
    public let operation: String
    public let httpMethod: String
    public var httpHeaders: HTTPHeaders
    public var body: Body

    /// Create HTTP Client request from AWSRequest.
    /// If the signer's credentials are available the request will be sigend. Otherweise defaults to an unsinged request
    func createHTTPRequest(signer: AWSSigner) -> AWSHTTPRequest {
        // if credentials are empty don't sign request
        if signer.credentials.isEmpty() {
            return self.toHTTPRequest()
        }
        
        return self.toHTTPRequestWithSignedHeader(signer: signer)
    }

    /// Create HTTP Client request from AWSRequest
    func toHTTPRequest() -> AWSHTTPRequest {
        return AWSHTTPRequest.init(url: url, method: HTTPMethod(rawValue: httpMethod), headers: httpHeaders, body: body.asPayload())
    }

    /// Create HTTP Client request with signed headers from AWSRequest
    func toHTTPRequestWithSignedHeader(signer: AWSSigner) -> AWSHTTPRequest {
        let method = HTTPMethod(rawValue: httpMethod)
        let payload = self.body.asPayload()
        let bodyDataForSigning: AWSSigner.BodyData?
        switch payload.payload {
        case .byteBuffer(let buffer):
            bodyDataForSigning = .byteBuffer(buffer)
        case .stream(let reader):
            if signer.name == "s3" {
                assert(reader.size != nil, "S3 stream requires size")
                var headers = httpHeaders
                // need to add this header here as it needs to be included in the signed headers
                headers.add(name: "x-amz-decoded-content-length", value: reader.size!.description)
                let (signedHeaders, seedSigningData) = signer.startSigningChunks(url: url, method: method, headers: headers, date: Date())
                let s3Reader = S3ChunkedStreamReader(
                    size: reader.size!,
                    seedSigningData: seedSigningData,
                    signer: signer,
                    byteBufferAllocator: reader.byteBufferAllocator,
                    read: reader.read)
                let payload = AWSPayload.streamReader(s3Reader)
                return AWSHTTPRequest.init(url: url, method: method, headers: signedHeaders, body: payload)
            } else {
                bodyDataForSigning = .unsignedPayload
            }
        case .empty:
            bodyDataForSigning = nil
        }
        let signedHeaders = signer.signHeaders(url: url, method: method, headers: httpHeaders, body: bodyDataForSigning, date: Date())
        return AWSHTTPRequest.init(url: url, method: method, headers: signedHeaders, body: payload)
    }

    // return new request with middleware applied
    func applyMiddlewares(_ middlewares: [AWSServiceMiddleware]) throws -> AWSRequest {
        var awsRequest = self
        // apply middleware to request
        for middleware in middlewares {
            awsRequest = try middleware.chain(request: awsRequest)
        }
        return awsRequest
    }
}

extension AWSRequest {
    
    internal init(operation operationName: String, path: String, httpMethod: String, configuration: AWSServiceConfig) throws {
        var headers = HTTPHeaders()

        guard let url = URL(string: "\(configuration.endpoint)\(path)"), let _ = url.host else {
            throw AWSClient.ClientError.invalidURL("\(configuration.endpoint)\(path) must specify url host and scheme")
        }

        // set x-amz-target header
        if let target = configuration.amzTarget {
            headers.replaceOrAdd(name: "x-amz-target", value: "\(target).\(operationName)")
        }
        
        self.region = configuration.region
        self.url = url
        self.serviceProtocol = configuration.serviceProtocol
        self.operation = operationName
        self.httpMethod = httpMethod
        self.httpHeaders = headers
        self.body = .empty
        
        addStandardHeaders()
    }
    
    internal init<Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        httpMethod: String,
        input: Input,
        configuration: AWSServiceConfig) throws
    {
        var headers = HTTPHeaders()
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
            headers.replaceOrAdd(name: "x-amz-target", value: "\(target).\(operationName)")
        }

        // TODO should replace with Encodable
        let mirror = Mirror(reflecting: input)
        var memberVariablesCount = mirror.children.count - Input._encoding.count

        // extract header, query and uri params
        for encoding in Input._encoding {
            if let value = mirror.getAttribute(forKey: encoding.label) {
                switch encoding.location {
                case .header(let location):
                    switch value {
                    case let dictionary as AWSRequestEncodableDictionary:
                        dictionary.encoded.forEach { headers.replaceOrAdd(name: "\(location)\($0.key)", value: $0.value) }
                    default:
                        headers.replaceOrAdd(name: location, value: "\(value)")
                    }

                case .querystring(let location):
                    switch value {
                    case let array as AWSRequestEncodableArray:
                        array.encoded.forEach { queryParams.append((key:location, value:$0)) }
                    case let dictionary as AWSRequestEncodableDictionary:
                        dictionary.encoded.forEach { queryParams.append($0) }
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
                let payload = shapeWithPayload._payloadPath
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
                let payload = shapeWithPayload._payloadPath
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
        
        addStandardHeaders()
    }

    private mutating func addStandardHeaders() {
        httpHeaders.replaceOrAdd(name: "user-agent", value: "AWSSDKSwift/5.0")
        guard httpHeaders["content-type"].first == nil else {
            return
        }
        guard httpMethod != "GET", httpMethod != "HEAD" else {
            return
        }

        if case .restjson = serviceProtocol, case .raw(_) = body {
            httpHeaders.replaceOrAdd(name: "content-type", value: "binary/octet-stream")
        } else {
            httpHeaders.replaceOrAdd(name: "content-type", value: serviceProtocol.contentType)
        }
    }

    // this list of query allowed characters comes from https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
    static let queryAllowedCharacters = CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func urlEncodeQueryParam(_ value: String) -> String {
        return value.addingPercentEncoding(withAllowedCharacters: AWSRequest.queryAllowedCharacters) ?? value
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
    
    
    internal static func verifyStream(operation: String, payload: AWSPayload, input: AWSShapeWithPayload.Type) {
        guard case .stream(let reader) = payload.payload else { return }
        precondition(input._payloadOptions.contains(.allowStreaming), "\(operation) does not allow streaming of data")
        precondition(reader.size != nil || input._payloadOptions.contains(.allowChunkedStreaming), "\(operation) does not allow chunked streaming of data. Please supply a data size.")
    }
    
}

fileprivate protocol AWSRequestEncodableArray {
    var encoded: [String] { get }
}

extension Array : AWSRequestEncodableArray {
    var encoded: [String] { return self.map{ "\($0)" }}
}

fileprivate protocol AWSRequestEncodableDictionary {
    var encoded: [(key:String, value: String)] { get }
}

extension Dictionary : AWSRequestEncodableDictionary {
    var encoded: [(key:String, value: String)] {
        return self.map { (key:"\($0.key)", value:"\($0.value)") }
    }
}
