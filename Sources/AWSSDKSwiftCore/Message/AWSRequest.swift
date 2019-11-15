//
//  AWSRequest.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/04/07.
//
//

import Foundation
import NIO
import NIOHTTP1
import AWSSigner

/// Object encapsulating all the information needed to generate a raw HTTP request to AWS
public struct AWSRequest {
    public let region: Region
    public var url: URL
    public let serviceProtocol: ServiceProtocol
    public let operation: String
    public let httpMethod: String
    public var httpHeaders: [String: Any] = [:]
    public var body: Body

    /// Initialize AWSRequest struct
    /// - parameters:
    ///     - region: Region of AWS server
    ///     - url : Request URL
    ///     - serviceProtocol: protocol of service (.json, .xml, .query etc)
    ///     - operation: Name of AWS operation
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - httpHeaders: HTTP request headers
    ///     - body: HTTP Request body
    public init(region: Region = .useast1, url: URL, serviceProtocol: ServiceProtocol, operation: String, httpMethod: String, httpHeaders: [String: Any] = [:], body: Body = .empty) {
        self.region = region
        self.url = url
        self.serviceProtocol = serviceProtocol
        self.operation = operation
        self.httpMethod = httpMethod
        self.httpHeaders = httpHeaders
        self.body = body
    }

    /// Add a header value
    /// - parameters:
    ///     - value : value
    ///     - forHTTPHeaderField: name of header
    public mutating func addValue(_ value: String, forHTTPHeaderField field: String) {
        httpHeaders[field] = value
    }

    func getHttpHeaders() -> HTTPHeaders {
        var headers: [String:String] = [:]
        for (key, value) in httpHeaders {
            //guard let value = value else { continue }
            headers[key] = "\(value)"
        }

        switch httpMethod {
        case "GET","HEAD":
            break
        default:
            switch serviceProtocol.type {
            case .json:
                headers["Content-Type"] = serviceProtocol.contentTypeString
            case .restjson:
                if case .buffer(_) = body {
                    headers["Content-Type"] = "binary/octet-stream"
                } else {
                    headers["Content-Type"] = "application/json"
                }
            case .query:
                headers["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8"
            case .other(let service):
                if service == "ec2" {
                    headers["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8"
                }
            default:
                break
            }

            headers["Content-Type"] = headers["Content-Type"] ?? "application/octet-stream"
        }

        return HTTPHeaders(headers.map { ($0, $1) })
    }
    
    /// Create HTTP Client request from AWSRequest
    func toHTTPRequest() -> AWSHTTPRequest {
        return AWSHTTPRequest.init(url: url, method: HTTPMethod(from: httpMethod), headers: getHttpHeaders(), body: body.asByteBuffer())
    }
    
    /// Create HTTP Client request with signed URL from AWSRequest
    func toHTTPRequestWithSignedURL(signer: AWSSigner) -> AWSHTTPRequest {
        let method = HTTPMethod(from: httpMethod)
        let bodyData = body.asByteBuffer()
        let signedURL = signer.signURL(url: url, method: method, body: bodyData != nil ? .byteBuffer(bodyData!) : nil, date: Date(), expires: 86400)
        return AWSHTTPRequest.init(url: signedURL, method: method, headers: getHttpHeaders(), body: bodyData)
    }
    
    /// Create HTTP Client request with signed headers from AWSRequest
    func toHTTPRequestWithSignedHeader(signer: AWSSigner) -> AWSHTTPRequest {
        let method = HTTPMethod(from: httpMethod)
        let bodyData = body.asByteBuffer()
        let signedHeaders = signer.signHeaders(url: url, method: method, headers: getHttpHeaders(), body: bodyData != nil ? .byteBuffer(bodyData!) : nil, date: Date())
        return AWSHTTPRequest.init(url: url, method: method, headers: signedHeaders, body: bodyData)
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


extension HTTPMethod {
    init(from: String) {
        switch from {
        case "HEAD":
            self = .HEAD
        case "GET":
            self = .GET
        case "POST":
            self = .POST
        case "PUT":
            self = .PUT
        case "PATCH":
            self = .PATCH
        case "DELETE":
            self = .DELETE
        default:
            self = .GET
        }
    }
}
