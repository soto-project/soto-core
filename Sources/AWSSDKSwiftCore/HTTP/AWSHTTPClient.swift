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
public struct AWSHTTPRequest {
    public let url: URL
    public let method: HTTPMethod
    public let headers: HTTPHeaders
    public let body: ByteBuffer?
}

/// HTTP Response
public protocol AWSHTTPResponse {
    var status: HTTPResponseStatus { get }
    var headers: HTTPHeaders { get }
    var body: ByteBuffer? { get }
}

/// Protocol defining requirements for a HTTPClient
public protocol AWSHTTPClient {
    /// Execute HTTP request and return a future holding a HTTP Response
    func execute(request: AWSHTTPRequest, timeout: TimeAmount) -> Future<AWSHTTPResponse>
    
    /// This should be called before an HTTP Client can be de-initialised
    func syncShutdown() throws
    
    /// Event loop group used by client
    var eventLoopGroup: EventLoopGroup {get}
}
