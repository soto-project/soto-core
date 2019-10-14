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

extension HTTPRequestHead {
    var hostWithPort: String? {
        return URL(string: uri)?.hostWithPort
    }

    var host: String? {
        return URL(string: uri)?.host
    }

    var port: Int? {
        return URL(string: uri)?.port
    }
}

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

    /// Create HTTP Client request from AWSRequest
    func toNIORequest() throws -> HTTPClient.Request {
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

        var head = HTTPRequestHead(
          version: HTTPVersion(major: 1, minor: 1),
          method: nioHTTPMethod(from: httpMethod),
          uri: url.absoluteString
        )
        let generatedHeaders = headers.map { ($0, $1) }
        head.headers = HTTPHeaders(generatedHeaders)

        return HTTPClient.Request(head: head, body: body.asData() ?? Data())
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

    // Convert string to NIO HTTP Method
    fileprivate func nioHTTPMethod(from: String) -> HTTPMethod {
        switch from {
        case "HEAD":
            return .HEAD
        case "GET":
            return .GET
        case "POST":
            return .POST
        case "PUT":
            return .PUT
        case "PATCH":
            return .PATCH
        case "DELETE":
            return .DELETE
        default:
            return .GET
        }
    }
}
