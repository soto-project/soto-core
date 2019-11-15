//
//  HTTPClient.swift
//  AWSSDKSwiftCore
//
//  Created by Joseph Mehdi Smith on 4/21/18.
//
// Informed by Vapor's HTTP client
// https://github.com/vapor/http/tree/master/Sources/HTTPKit/Client
// and the swift-server's swift-nio-http-client
// https://github.com/swift-server/swift-nio-http-client
//
#if canImport(Network)

import Foundation
import Network
import NIO
import NIOConcurrencyHelpers
import NIOFoundationCompat
import NIOHTTP1
import NIOTransportServices

/// HTTP Client class providing API for sending HTTP requests
@available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)
public final class NIOTSHTTPClient {

    /// Request structure to send
    public struct Request {
        var head: HTTPRequestHead
        var body: ByteBuffer?
    }

    /// Response structure received back
    public struct Response {
        let head: HTTPResponseHead
        let body: ByteBuffer?
    }

    /// Errors returned from HTTPClient when parsing responses
    public enum HTTPError: Error {
        case malformedHead
        case malformedBody
        case malformedURL(url: String)
        case alreadyShutdown
    }

    /// Specifies how `EventLoopGroup` will be created and establishes lifecycle ownership.
    public enum EventLoopGroupProvider {
        /// `EventLoopGroup` will be provided by the user. Owner of this group is responsible for its lifecycle.
        case shared(EventLoopGroup)
        /// `EventLoopGroup` will be created by the client. When `syncShutdown` is called, created `EventLoopGroup` will be shut down as well.
        case createNew
    }

    /// has HTTPClient been shutdown
    let isShutdown = Atomic<Bool>(value: false)

    /// Initialise HTTPClient
    public init(eventLoopGroupProvider: EventLoopGroupProvider = .createNew) {
        self.eventLoopGroupProvider = eventLoopGroupProvider
        switch eventLoopGroupProvider {
        case .shared(let group):
            self.eventLoopGroup = group
        case .createNew:
            self.eventLoopGroup = NIOTSEventLoopGroup()
        }
    }

    deinit {
        assert(self.isShutdown.load(), "Client not shut down before the deinit. Please call client.syncShutdown() when no longer needed.")
    }

    /// send request to HTTP client, return a future holding the Response
    public func connect(_ request: Request, timeout: TimeAmount) -> EventLoopFuture<Response> {
        // extract details from request URL
        guard let url = URL(string:request.head.uri) else { return eventLoopGroup.next().makeFailedFuture(HTTPError.malformedURL(url: request.head.uri)) }
        guard let scheme = url.scheme else { return eventLoopGroup.next().makeFailedFuture(HTTPError.malformedURL(url: request.head.uri)) }
        guard let hostname = url.host else { return eventLoopGroup.next().makeFailedFuture(HTTPError.malformedURL(url: request.head.uri)) }

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


        let response: EventLoopPromise<Response> = self.eventLoopGroup.next().makePromise()

        var bootstrap = NIOTSConnectionBootstrap(group: self.eventLoopGroup)
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

    /// Shuts down the client and `EventLoopGroup` if it was created by the client.
    public func syncShutdown() throws {
        switch self.eventLoopGroupProvider {
        case .shared:
            self.isShutdown.store(true)
        case .createNew:
            if self.isShutdown.compareAndExchange(expected: false, desired: true) {
                try self.eventLoopGroup.syncShutdownGracefully()
            } else {
                throw HTTPError.alreadyShutdown
            }
        }
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
            head.headers.replaceOrAdd(name: "User-Agent", value: "AWS SDK Swift Core")
            head.headers.replaceOrAdd(name: "Accept", value: "*/*")
            if let body = request.body {
                head.headers.replaceOrAdd(name: "Content-Length", value: body.readableBytes.description)
            }
            // TODO implement keep-alive
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

    internal let eventLoopGroup: EventLoopGroup
    private let eventLoopGroupProvider: EventLoopGroupProvider
}

/// comply with AWSHTTPClient protocol
@available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)
extension NIOTSHTTPClient: AWSHTTPClient {

    func execute(request: AWSHTTPRequest, timeout: TimeAmount) -> EventLoopFuture<AWSHTTPResponse> {
        var head = HTTPRequestHead(
          version: HTTPVersion(major: 1, minor: 1),
          method: request.method,
          uri: request.url.absoluteString
        )
        head.headers = request.headers
        let request = Request(head: head, body: request.body)

        return connect(request, timeout: timeout).map { return $0 }
    }
}

@available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)
extension NIOTSHTTPClient.Response: AWSHTTPResponse {
    var status: HTTPResponseStatus { return head.status }
    var headers: HTTPHeaders { return head.headers }
}

#endif
