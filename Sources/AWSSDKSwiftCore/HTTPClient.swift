//
//  HTTPClient.swift
//  AWSSDKSwiftCore
//
//  Created by Joseph Mehdi Smith on 4/21/18.
//
// Informed by the Swift NIO
// [`testSimpleGet`](https://github.com/apple/swift-nio/blob/a4318d5e752f0e11638c0271f9c613e177c3bab8/Tests/NIOHTTP1Tests/HTTPServerClientTest.swift#L348)
// and heavily built off Vapor's HTTP client library,
// [`HTTPClient`](https://github.com/vapor/http/blob/2cb664097006e3fda625934079b51c90438947e1/Sources/HTTP/Responder/HTTPClient.swift)

import NIO
import NIOHTTP1
import NIOSSL
import NIOFoundationCompat
import Foundation

public struct Request {
    var head: HTTPRequestHead
    var body: Data = Data()
}

public struct Response {
    let head: HTTPResponseHead
    let body: Data

    public func contentType() -> String? {
        return head.headers.filter { $0.name.lowercased() == "content-type" }.first?.value
    }
}

private enum HTTPClientState {
    /// Waiting to parse the next response.
    case ready
    /// Currently parsing the response's body.
    case parsingBody(HTTPResponseHead, Data?)
}

public enum HTTPClientError: Error {
    case malformedHead, malformedBody, malformedURL, error(Error)
}

private class HTTPClientResponseHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = Response

    private var receiveds: [HTTPClientResponsePart] = []
    private var state: HTTPClientState = .ready
    private var promise: EventLoopPromise<Response>

    public init(promise: EventLoopPromise<Response>) {
        self.promise = promise
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise.fail(HTTPClientError.error(error))
        context.fireErrorCaught(error)
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            switch state {
            case .ready: state = .parsingBody(head, nil)
            case .parsingBody: promise.fail(HTTPClientError.malformedHead)
            }
        case .body(var body):
            switch state {
            case .ready: promise.fail(HTTPClientError.malformedBody)
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
            case .ready: promise.fail(HTTPClientError.malformedHead)
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

public final class HTTPClient {
    private let hostname: String
    private let port: Int
    private let eventGroup: EventLoopGroup

    public init(url: URL,
                eventGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)) throws {
        guard let scheme = url.scheme else {
            throw HTTPClientError.malformedURL
        }
        guard let hostname = url.host else {
            throw HTTPClientError.malformedURL
        }
        var port: Int {
            let isSecure = scheme == "https" || scheme == "wss"
            return isSecure ? 443 : Int(url.port ?? 80)
        }
        self.hostname = hostname
        self.port = port
        self.eventGroup = eventGroup
    }

    public init(hostname: String,
                port: Int,
                eventGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)) {
        self.hostname = hostname
        self.port = port
        self.eventGroup = eventGroup
    }

    public func connect(_ request: Request) throws -> EventLoopFuture<Response> {
        var head = request.head
        let body = request.body

        head.headers.replaceOrAdd(name: "Host", value: hostname)
        head.headers.replaceOrAdd(name: "User-Agent", value: "AWS SDK Swift Core")
        head.headers.replaceOrAdd(name: "Accept", value: "*/*")
        head.headers.replaceOrAdd(name: "Content-Length", value: body.count.description)

        // TODO implement Keep-alive
        head.headers.replaceOrAdd(name: "Connection", value: "Close")

        var preHandlers = [ChannelHandler]()
        if (port == 443) {
            do {
                let tlsConfiguration = TLSConfiguration.forClient()
                let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
                let tlsHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: hostname)
                preHandlers.append(tlsHandler)
            } catch {
                print("Unable to setup TLS: \(error)")
            }
        }
        let response: EventLoopPromise<Response> = eventGroup.next().makePromise()

        _ = ClientBootstrap(group: eventGroup)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                let accumulation = HTTPClientResponseHandler(promise: response)
                let results = preHandlers.map { channel.pipeline.addHandler($0) }
                return EventLoopFuture<Void>.andAllSucceed(results, on: channel.eventLoop).flatMap { _ in
                    channel.pipeline.addHTTPClientHandlers().flatMap { _ in
                        channel.pipeline.addHandler(accumulation)
                    }
                }
            }
            .connect(host: hostname, port: port)
            .flatMap { channel -> EventLoopFuture<Void> in
                channel.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)
                var buffer = ByteBufferAllocator().buffer(capacity: body.count)
                buffer.writeBytes(body)
                channel.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(buffer))), promise: nil)
                return channel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)))
        }
        return response.futureResult
    }

    public func close(_ callback: @escaping (Error?) -> Void) {
        eventGroup.shutdownGracefully(callback)
    }
}
