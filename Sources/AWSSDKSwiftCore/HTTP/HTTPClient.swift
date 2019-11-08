//
//  HTTPClient.swift
//  AWSSDKSwiftCore
//
//  Created by Adam Fowler on 2019/11/8
//

import Foundation
import NIO
import NIOHTTP1

/// HTTP Request
struct AWSHTTPRequest {
    let url: URL
    let method: HTTPMethod
    let headers: HTTPHeaders
    let bodyData: Data?
}

/// HTTP Response
protocol AWSHTTPResponse {
    var status: HTTPResponseStatus { get }
    var headers: HTTPHeaders { get }
    var bodyData: Data? { get }
}

/// Protocol defining requirements for a HTTPClient
protocol AWSHTTPClient {
    /// Execute HTTP request and return a future holding a HTTP Response
    func execute(request: AWSHTTPRequest, timeout: TimeAmount) -> Future<AWSHTTPResponse>
    
    /// This should be called before an HTTP Client can be de-initialised
    func syncShutdown() throws
    
    /// Event loop group used by client
    var eventLoopGroup: EventLoopGroup {get}
}
