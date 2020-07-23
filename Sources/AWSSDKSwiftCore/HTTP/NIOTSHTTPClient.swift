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

// Informed by Vapor's HTTP client
// https://github.com/vapor/http/tree/master/Sources/HTTPKit/Client
// and the swift-server's swift-nio-http-client
// https://github.com/swift-server/swift-nio-http-client
//
#if canImport(Network)

import Foundation
import Logging
import Network
import NIO
import NIOConcurrencyHelpers
import NIOFoundationCompat
import NIOHTTP1
import NIOTransportServices

/// HTTP Client class providing API for sending HTTP requests
@available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)
public final class NIOTSHTTPClient {

    /// Specifies how `EventLoopGroup` will be created and establishes lifecycle ownership.
    public enum EventLoopGroupProvider {
        /// `EventLoopGroup` will be provided by the user. Owner of this group is responsible for its lifecycle.
        case shared(NIOTSEventLoopGroup)
        /// `EventLoopGroup` will be created by the client. When `syncShutdown` is called, created `EventLoopGroup` will be shut down as well.
        case createNew
    }

    /// Request structure to send
    public struct Request {
        public var head: HTTPRequestHead
        public var body: ByteBuffer?
    }

    /// Response structure received back
    public struct Response {
        public let head: HTTPResponseHead
        public let body: ByteBuffer?
    }

    /// Errors returned from HTTPClient when parsing responses
    public enum HTTPError: Error {
        case malformedHead
        case malformedBody
        case malformedURL(url: String)
        case alreadyShutdown
    }

    /// Initialise HTTPClient
    public init(eventLoopGroupProvider: EventLoopGroupProvider) {
        self.eventLoopGroupProvider = eventLoopGroupProvider
        switch self.eventLoopGroupProvider {
        case .shared(let group):
            self.eventLoopGroup = group
        case .createNew:
            self.eventLoopGroup = NIOTSEventLoopGroup()
        }
    }

    deinit {
        assert(self.isShutdown.load(), "Client not shut down before the deinit. Please call client.syncShutdown() when no longer needed.")
    }

    /// Shuts down the client and `EventLoopGroup` if it was created by the client.
    public func syncShutdown() throws {
        switch self.eventLoopGroupProvider {
        case .shared:
            self.isShutdown.store(true)
            return
        case .createNew:
            if self.isShutdown.compareAndExchange(expected: false, desired: true) {
                try self.eventLoopGroup.syncShutdownGracefully()
            } else {
                throw HTTPError.alreadyShutdown
            }
        }
    }

    /// send request to HTTP client, return a future holding the Response
    public func connect(url: URL, _ request: Request, timeout: TimeAmount, on eventLoop: EventLoop) -> EventLoopFuture<Response> {
        //let eventLoop = eventLoop ?? eventLoopGroup.next()
        // extract details from request URL
        //guard let url = URL(string:request.head.uri) else { return eventLoop.makeFailedFuture(HTTPError.malformedURL(url: request.head.uri)) }
        guard let scheme = url.scheme else { return eventLoop.makeFailedFuture(HTTPError.malformedURL(url: request.head.uri)) }
        guard let hostname = url.host else { return eventLoop.makeFailedFuture(HTTPError.malformedURL(url: request.head.uri)) }

        let port : Int
        let headerHostname : String
        if url.port != nil {
            port = url.port!
            headerHostname = "\(hostname):\(port)"
        } else {
            let isSecure = (scheme == "https")
            port = isSecure ? 443 : 80
            headerHostname = hostname
        }


        let response: EventLoopPromise<Response> = eventLoop.makePromise()

        var bootstrap = NIOTSConnectionBootstrap(group: eventLoop)
            .connectTimeout(timeout)
            .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)

        if port == 443 {
            bootstrap = bootstrap.tlsOptions(NWProtocolTLS.Options())
        }

        bootstrap.channelInitializer { channel in
            return channel.pipeline.addHTTPClientHandlers()
                .flatMap {
                    let handlers : [ChannelHandler] = [
                        HTTPClientRequestSerializer(hostname: headerHostname),
                        HTTPClientResponseHandler(promise: response)
                    ]
                    return channel.pipeline.addHandlers(handlers)
            }
        }
        .connect(host: hostname, port: port)
        .flatMap { channel -> EventLoopFuture<Void> in
            return channel.writeAndFlush(request)
        }
        .whenFailure { error in
            response.fail(error)
        }

        return response.futureResult
    }

    /// Channel Handler for serializing request header and data
    private class HTTPClientRequestSerializer : ChannelOutboundHandler {
        typealias OutboundIn = Request
        typealias OutboundOut = HTTPClientRequestPart

        private let hostname: String

        init(hostname: String) {
            self.hostname = hostname
        }

        func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
            let request = unwrapOutboundIn(data)
            var head = request.head

            head.headers.replaceOrAdd(name: "Host", value: hostname)
            head.headers.replaceOrAdd(name: "Content-Length", value: request.body?.readableBytes.description ?? "0")
            head.headers.replaceOrAdd(name: "Connection", value: "Close")


            context.write(wrapOutboundOut(.head(head)), promise: nil)
            if let body = request.body, body.readableBytes > 0 {
                context.write(self.wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
            }
            context.write(self.wrapOutboundOut(.end(nil)), promise: promise)
        }
    }

    /// Channel Handler for parsing response from server
    private class HTTPClientResponseHandler: ChannelInboundHandler {
        typealias InboundIn = HTTPClientResponsePart
        typealias OutboundOut = Response

        private enum ResponseState {
            /// Waiting to parse the next response.
            case ready
            /// Received the head.
            case head(HTTPResponseHead)
            /// Currently parsing the response's body.
            case body(HTTPResponseHead, ByteBuffer)
        }

        private var state: ResponseState = .ready
        private let promise : EventLoopPromise<Response>

        init(promise: EventLoopPromise<Response>) {
            self.promise = promise
        }

        func errorCaught(context: ChannelHandlerContext, error: Error) {
            context.fireErrorCaught(error)
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            switch unwrapInboundIn(data) {
            case .head(let head):
                switch state {
                case .ready: state = .head(head)
                case .head, .body: promise.fail(HTTPError.malformedHead)
                }
            case .body(let part):
                switch state {
                case .ready: promise.fail(HTTPError.malformedBody)
                case .head(let head):
                    state = .body(head, part)
                case .body(let head, var body):
                    var part = part
                    body.writeBuffer(&part)
                    state = .body(head, body)
                }
            case .end:
                switch state {
                case .ready: promise.fail(HTTPError.malformedHead)
                case .head(let head):
                    let res = Response(head: head, body: nil)
                    if context.channel.isActive {
                        context.fireChannelRead(wrapOutboundOut(res))
                    }
                    promise.succeed(res)
                    state = .ready
                case .body(let head, let body):
                    let res = Response(head: head, body: body)
                    if context.channel.isActive {
                        context.fireChannelRead(wrapOutboundOut(res))
                    }
                    promise.succeed(res)
                    state = .ready
                }
            }
        }
    }

    public let eventLoopGroup: EventLoopGroup
    let eventLoopGroupProvider: EventLoopGroupProvider
    let isShutdown = NIOAtomic<Bool>.makeAtomic(value: false)
}

/// comply with AWSHTTPClient protocol
@available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)
extension NIOTSHTTPClient: AWSHTTPClient {

    public func execute(request: AWSHTTPRequest, timeout: TimeAmount, on eventLoop: EventLoop, logger: Logger) -> EventLoopFuture<AWSHTTPResponse> {
        var head = HTTPRequestHead(
          version: HTTPVersion(major: 1, minor: 1),
          method: request.method,
          uri: request.url.uri
        )
        head.headers = request.headers

        let requestBody: ByteBuffer?
        switch request.body.payload {
        case .byteBuffer(let byteBuffer):
            requestBody = byteBuffer
        case .stream:
            preconditionFailure("NIOTSHTTPClient does not support request streaming")
        case .empty:
            requestBody = nil
        }
        let url = request.url
        let request = Request(head: head, body: requestBody)

        return connect(url: url, request, timeout: timeout, on: eventLoop).map { return $0 }
    }
}

@available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)
extension NIOTSHTTPClient.Response: AWSHTTPResponse {
    public var status: HTTPResponseStatus { return head.status }
    public var headers: HTTPHeaders { return head.headers }
}

// copied from AsyncHTTPClient
extension URL {
    var percentEncodedPath: String {
        if self.path.isEmpty {
            return "/"
        }
        return self.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self.path
    }

    var pathHasTrailingSlash: Bool {
        if #available(OSX 10.11, iOS 9.0, tvOS 9.0, watchOS 2.0, *) {
            return self.hasDirectoryPath
        } else {
            // Most platforms should use `self.hasDirectoryPath`, but on older darwin platforms
            // we have this approximation instead.
            let url = self.absoluteString

            var pathEndIndex = url.index(before: url.endIndex)
            if let queryIndex = url.firstIndex(of: "?") {
                pathEndIndex = url.index(before: queryIndex)
            } else if let fragmentIndex = url.suffix(from: url.firstIndex(of: "@") ?? url.startIndex).lastIndex(of: "#") {
                pathEndIndex = url.index(before: fragmentIndex)
            }

            return url[pathEndIndex] == "/"
        }
    }

    var uri: String {
        var uri = self.percentEncodedPath
        if self.pathHasTrailingSlash, uri != "/" {
            uri += "/"
        }
        
        if let query = self.query {
            uri += "?" + query
        }

        return uri
    }
}

#endif
