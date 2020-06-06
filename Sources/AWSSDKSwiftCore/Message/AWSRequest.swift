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

import NIO
import NIOHTTP1
import struct Foundation.URL
import struct Foundation.Date
import struct Foundation.Data

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

        if headers["Content-Type"] == nil {
            switch httpMethod {
            case "GET","HEAD":
                break
            default:
                if case .restjson = serviceProtocol, case .raw(_) = body {
                    headers["Content-Type"] = "binary/octet-stream"
                } else {
                    headers["Content-Type"] = serviceProtocol.contentType
                }
            }
        }
        headers["User-Agent"] = "AWSSDKSwift/5.0"
        
        return HTTPHeaders(headers.map { ($0, $1) })
    }

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
        return AWSHTTPRequest.init(url: url, method: HTTPMethod(rawValue: httpMethod), headers: getHttpHeaders(), body: body.asPayload())
    }

    /// Create HTTP Client request with signed headers from AWSRequest
    func toHTTPRequestWithSignedHeader(signer: AWSSigner) -> AWSHTTPRequest {
        let method = HTTPMethod(rawValue: httpMethod)
        let payload = self.body.asPayload()
        let bodyDataForSigning: AWSSigner.BodyData?
        switch payload.payload {
        case .byteBuffer(let buffer):
            bodyDataForSigning = .byteBuffer(buffer)
        case .stream:
            bodyDataForSigning = .unsignedPayload
        case .empty:
            bodyDataForSigning = nil
        }
        let signedHeaders = signer.signHeaders(url: url, method: method, headers: getHttpHeaders(), body: bodyDataForSigning, date: Date())
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
