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
import NIOFoundationCompat
import NIOHTTP1
#if canImport(NIOSSL)
import NIOSSL
#elseif canImport(NIOTransportServices)
import Network
import NIOTransportServices
#endif

public final class HTTPClient {
    
    public struct Request {
        var head: HTTPRequestHead
        var body: Data
    }
    
    public struct Response {
        let head: HTTPResponseHead
        let body: Data
    }
    
    public enum ClientError: Error {
        case malformedHead
        case malformedBody
        case malformedURL(url: String)
        case alreadyShutdown
        case error(Error)
    }

    /// Specifies how `EventLoopGroup` will be created and establishes lifecycle ownership.
    public enum EventLoopGroupProvider {
        /// `EventLoopGroup` will be provided by the user. Owner of this group is responsible for its lifecycle.
        case shared(EventLoopGroup)
        /// `EventLoopGroup` will be created by the client. When `syncShutdown` is called, created `EventLoopGroup` will be shut down as well.
        case createNew
    }
    
    public init(eventLoopGroupProvider: EventLoopGroupProvider = .createNew) {
        self.eventLoopGroupProvider = eventLoopGroupProvider
        switch eventLoopGroupProvider {
        case .shared(let group):
            self.eventLoopGroup = group
        case .createNew:
            #if canImport(NIOSSL)
                self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            #elseif canImport(NIOTransportServices)
                self.eventLoopGroup = NIOTSEventLoopGroup()
            #else
                fatalError("HTTPClient: needs to link with NIOSSL or NIOTransportServices")
            #endif
        }
    }

    #if canImport(NIOSSL)
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
    #endif
    
    /// send request to HTTP client, return a future holding the Response
    public func connect(_ request: Request) -> EventLoopFuture<Response> {
        guard let url = URL(string:request.head.uri) else { return eventLoopGroup.next().makeFailedFuture(HTTPClient.ClientError.malformedURL(url: request.head.uri)) }
        guard let scheme = url.scheme else { return eventLoopGroup.next().makeFailedFuture(HTTPClient.ClientError.malformedURL(url: request.head.uri)) }
        guard let hostname = url.host else { return eventLoopGroup.next().makeFailedFuture(HTTPClient.ClientError.malformedURL(url: request.head.uri)) }
        
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
        
        #if canImport(NIOSSL)
        
        let bootstrap = ClientBootstrap(group: self.eventLoopGroup)
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
        
        #elseif canImport(NIOTransportServices)
        
        let bootstrap = NIOTSConnectionBootstrap(group: self.eventLoopGroup)
            .connectTimeout(TimeAmount.seconds(5))
            .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .tlsOptions(NWProtocolTLS.Options())
            .channelInitializer { channel in
                return channel.pipeline.addHTTPClientHandlers()
                    .flatMap {
                        let handlers : [ChannelHandler] = [
                            HTTPClientRequestSerializer(hostname: headerHostname),
                            HTTPClientResponseHandler(promise: response)
                        ]
                        return channel.pipeline.addHandlers(handlers)
                }
        }
        
        #endif

        bootstrap.connect(host: hostname, port: port)
            .flatMap { channel -> EventLoopFuture<Void> in
                return channel.writeAndFlush(request)
            }
            .whenFailure { error in
                response.fail(error)
        }
        
        return response.futureResult
    }
    
   /// shutdown the event group
    public func close(_ callback: @escaping (Error?) -> Void) {
        switch self.eventLoopGroupProvider {
        case .shared:
            callback(nil)
        case .createNew:
            self.eventLoopGroup.shutdownGracefully(callback)
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
                case .parsingBody: promise.fail(HTTPClient.ClientError.malformedHead)
                }
            case .body(var body):
                switch state {
                case .ready: promise.fail(HTTPClient.ClientError.malformedBody)
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
                case .ready: promise.fail(HTTPClient.ClientError.malformedHead)
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
