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
import NIO
import NIOFoundationCompat
import NIOHTTP1
import NIOSSL
import Foundation

public final class HTTPClient {
    
    public struct Request {
        var head: HTTPRequestHead
        var body: Data
    }
    
    public struct Response {
        let head: HTTPResponseHead
        let body: Data
        
        public func contentType() -> String? {
            return head.headers.filter { $0.name.lowercased() == "content-type" }.first?.value
        }
    }
    
    public enum ClientError: Error {
        case malformedHead
        case malformedBody
        case malformedURL
        case error(Error)
    }
    
    public init(url: URL,
                eventGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)) throws {
        // work out if secure port is required from url
        guard let scheme = url.scheme else { throw ClientError.malformedURL }
        guard let hostname = url.host else { throw ClientError.malformedURL }
        let isSecure = scheme == "https" || scheme == "wss"

        self.hostname = hostname
        self.port = isSecure ? 443 : Int(url.port ?? 80)
        self.eventGroup = eventGroup
    }
    
    public init(hostname: String,
                port: Int,
                eventGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)) {
        self.hostname = hostname
        self.port = port
        self.eventGroup = eventGroup
    }
    
    /// add SSL Handler to channel pipeline if the port is 443
    public func addSSLHandlerIfNeeded(_ pipeline : ChannelPipeline) -> EventLoopFuture<Void> {
        if (self.port == 443) {
            do {
                let tlsConfiguration = TLSConfiguration.forClient()
                let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
                let tlsHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: self.hostname)
                return pipeline.addHandler(tlsHandler, position:.first)
            } catch {
                return pipeline.eventLoop.makeFailedFuture(error)
            }
        }
        return pipeline.eventLoop.makeSucceededFuture(())
    }
    
    /// send request to HTTP client, return a future holding the Response
    public func connect(_ request: Request) -> EventLoopFuture<Response> {
        
        let response: EventLoopPromise<Response> = eventGroup.next().makePromise()
        let bootstrap = ClientBootstrap(group: eventGroup)
            .connectTimeout(TimeAmount.seconds(5))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                return channel.pipeline.addHTTPClientHandlers()
                    .flatMap {
                        return self.addSSLHandlerIfNeeded(channel.pipeline)
                    }
                    .flatMap {
                        let handlers : [ChannelHandler] = [
                            HTTPClientRequestSerializer(hostname: self.hostname),
                            HTTPClientResponseHandler(promise: response)
                        ]
                        return channel.pipeline.addHandlers(handlers)
                }
            }
            
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
        eventGroup.shutdownGracefully(callback)
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
            context.write(self.wrapOutboundOut(.end(nil)), promise: nil)
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

    private let hostname: String
    private let port: Int
    private let eventGroup: EventLoopGroup
}
