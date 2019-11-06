//
//  HTTPRequest.swift
//  AWSSDKSwiftCore
//
//  Created by Adam Fowler on 2019/11/6.
//
import AsyncHTTPClient
import Foundation
import NIOHTTP1

/// protocol defining requirement for creating an HTTP Request
protocol HTTPRequestDescription {
    init(url: URL, method: HTTPMethod, headers: HTTPHeaders, body: Data?) throws
}

extension AsyncHTTPClient.HTTPClient.Request: HTTPRequestDescription {
    init(url: URL, method: HTTPMethod = .GET, headers: HTTPHeaders = HTTPHeaders(), body: Data? = nil) throws {
        let requestBody: AsyncHTTPClient.HTTPClient.Body?
        if let body = body {
            requestBody = AsyncHTTPClient.HTTPClient.Body.data(body)
        } else {
            requestBody = nil
        }
        self = try AsyncHTTPClient.HTTPClient.Request.init(url: url, method: method, headers: headers, body: requestBody)
    }
}

extension AWSHTTPClient.Request: HTTPRequestDescription {
    init(url: URL, method: HTTPMethod = .GET, headers: HTTPHeaders = HTTPHeaders(), body: Data? = nil) throws {
        var head = HTTPRequestHead(
          version: HTTPVersion(major: 1, minor: 1),
          method: method,
          uri: url.absoluteString
        )
        head.headers = headers
        
        self.head = head
        self.body = body
    }
}
