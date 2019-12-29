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

import Foundation
import NIO
import NIOConcurrencyHelpers
import NIOFoundationCompat
import NIOHTTP1
import NIOSSL
#if canImport(Network)
import Network
import NIOTransportServices
#endif

/// HTTP Client class providing API for sending HTTP requests
public final class HTTPClient {

    /// Request structure to send
    public struct Request {
        var head: HTTPRequestHead
        var body: Data
    }

    /// Response structure received back
    public struct Response {
        let head: HTTPResponseHead
        let body: Data
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
    let isShutdown = NIOAtomic<Bool>.makeAtomic(value: false)

    /// Initialise HTTPClient
    public init(eventLoopGroupProvider: EventLoopGroupProvider = .createNew) {
        self.eventLoopGroupProvider = eventLoopGroupProvider
        switch eventLoopGroupProvider {
        case .shared(let group):
            self.eventLoopGroup = group
        case .createNew:
            #if canImport(Network)
                if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
                    self.eventLoopGroup = NIOTSEventLoopGroup()
                } else {
                    self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
                }
            #else
                self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            #endif
        }
    }
    
    deinit {
        assert(self.isShutdown.load(), "Client not shut down before the deinit. Please call client.close() when no longer needed.")
    }

    /// add SSL Handler to channel pipeline if the port is 443
    func addSSLHandlerIfNeeded(_ pipeline : ChannelPipeline, hostname: String, port: Int) -> EventLoopFuture<Void> {
        if (port == 443) {
            do {
                let tlsConfiguration = TLSConfiguration.forClient()
                let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
                let tlsHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: hostname)
                return pipeline.addHandler(tlsHandler, position:.first)
            } catch {
                return pipeline.eventLoop.makeFailedFuture(error)
            }
        }
        return pipeline.eventLoop.makeSucceededFuture(())
    }

    /// setup client bootstrap for HTTP request
    func clientBootstrap(hostname: String, port: Int, headerHostname: String, request: Request, response: EventLoopPromise<Response>) {
        _ = ClientBootstrap(group: self.eventLoopGroup)
            .connectTimeout(TimeAmount.seconds(5))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
            .channelInitializer { channel in
                return channel.pipeline.addHTTPClientHandlers()
                    .flatMap {
                        return self.addSSLHandlerIfNeeded(channel.pipeline, hostname: hostname, port: port)
                    }
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
    }

    /// setup client bootstrap for HTTP request using NIO transport services
    #if canImport(Network)
    @available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)
    func tsConnectionBootstrap(hostname: String, port: Int, headerHostname: String, request: Request, response: EventLoopPromise<Response>) {
        var bootstrap = NIOTSConnectionBootstrap(group: self.eventLoopGroup)
            .connectTimeout(TimeAmount.seconds(5))
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
    }
    #endif
    
    /// send request to HTTP client, return a future holding the Response
    public func connect(_ request: Request) -> EventLoopFuture<Response> {
        // extract details from request URL
        guard let url = URL(string:request.head.uri) else { return eventLoopGroup.next().makeFailedFuture(HTTPClient.HTTPError.malformedURL(url: request.head.uri)) }
        guard let scheme = url.scheme else { return eventLoopGroup.next().makeFailedFuture(HTTPClient.HTTPError.malformedURL(url: request.head.uri)) }
        guard let hostname = url.host else { return eventLoopGroup.next().makeFailedFuture(HTTPClient.HTTPError.malformedURL(url: request.head.uri)) }

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

        #if canImport(Network)
            if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *), eventLoopGroup is NIOTSEventLoopGroup {
                tsConnectionBootstrap(hostname: hostname, port: port, headerHostname: headerHostname, request: request, response: response)
            } else {
                clientBootstrap(hostname: hostname, port: port, headerHostname: headerHostname, request: request, response: response)
            }
        #else
            clientBootstrap(hostname: hostname, port: port, headerHostname: headerHostname, request: request, response: response)
        #endif
        
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
            head.headers.replaceOrAdd(name: "Content-Length", value: request.body.count.description)
            // TODO implement keep-alive
            head.headers.replaceOrAdd(name: "Connection", value: "Close")


            context.write(wrapOutboundOut(.head(head)), promise: nil)
            if request.body.count > 0 {
                var buffer = ByteBufferAllocator().buffer(capacity: request.body.count)
                buffer.writeBytes(request.body)
                context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
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
            /// Currently parsing the response's body.
            case parsingBody(HTTPResponseHead, Data?)
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
                case .ready: state = .parsingBody(head, nil)
                case .parsingBody: promise.fail(HTTPClient.HTTPError.malformedHead)
                }
            case .body(var body):
                switch state {
                case .ready: promise.fail(HTTPClient.HTTPError.malformedBody)
                case .parsingBody(let head, let existingData):
                    let data: Data
                    if var existing = existingData {
                        existing += body.readData(length: body.readableBytes) ?? Data()
                        data = existing
                    } else {
                        data = body.readData(length: body.readableBytes) ?? Data()
                    }
                    state = .parsingBody(head, data)
                }
            case .end(let tailHeaders):
                assert(tailHeaders == nil, "Unexpected tail headers")
                switch state {
                case .ready: promise.fail(HTTPClient.HTTPError.malformedHead)
                case .parsingBody(let head, let data):
                    let res = Response(head: head, body: data ?? Data())
                    if context.channel.isActive {
                        context.fireChannelRead(wrapOutboundOut(res))
                    }
                    promise.succeed(res)
                    state = .ready
                }
            }
        }
    }
    
    private let eventLoopGroup: EventLoopGroup
    private let eventLoopGroupProvider: EventLoopGroupProvider
}
