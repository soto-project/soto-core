//
//  AWSRequest.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/04/07.
//
//

import Foundation
import NIO
import NIOTLS
import NIOHTTP1

public protocol AWSServiceMiddleware {
    func chain(request: AWSRequest) throws -> AWSRequest
    func chain(responseBody: Body) throws -> Body
}

public extension AWSServiceMiddleware {
    func chain(request: AWSRequest) throws -> AWSRequest {
        return request
    }
    func chain(responseBody: Body) throws -> Body {
        return responseBody
    }
}

extension URL {
    public var hostWithPort: String? {
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

public struct AWSRequest {
    public let region: Region
    public var url: URL
    public let serviceProtocol: ServiceProtocol
    public let service: String
    public let amzTarget: String?
    public let operation: String
    public let httpMethod: String
    public var httpHeaders: [String: Any?] = [:]
    public var body: Body
    public let middlewares: [AWSServiceMiddleware]

    public init(region: Region = .useast1, url: URL, serviceProtocol: ServiceProtocol, service: String, amzTarget: String? = nil, operation: String, httpMethod: String, httpHeaders: [String: Any?] = [:], body: Body = .empty, middlewares: [AWSServiceMiddleware] = []) {
        self.region = region
        self.url = url
        self.serviceProtocol = serviceProtocol
        self.service = service
        self.amzTarget = amzTarget
        self.operation = operation
        self.httpMethod = httpMethod
        self.httpHeaders = httpHeaders
        self.body = body
        self.middlewares = middlewares
    }

    public mutating func addValue(_ value: String, forHTTPHeaderField field: String) {
        httpHeaders[field] = value
    }

    func toNIORequest() throws -> Request {
        var awsRequest = self
        for middleware in middlewares {
            awsRequest = try middleware.chain(request: awsRequest)
        }

        var headers: [String:String] = [:]
        for (key, value) in awsRequest.httpHeaders {
            guard let value = value else { continue }
            headers[key] = "\(value)"
        }

        if let target = awsRequest.amzTarget {
            headers["x-amz-target"] = "\(target).\(awsRequest.operation)"
        }

        switch awsRequest.httpMethod {
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
          method: nioHTTPMethod(from: awsRequest.httpMethod),
          uri: awsRequest.url.absoluteString
        )
        let generatedHeaders = headers.map { ($0, $1) }
        head.headers = HTTPHeaders(generatedHeaders)

        return Request(head: head, body: awsRequest.body.asData() ?? Data())
    }

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
