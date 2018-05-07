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
import NIOOpenSSL
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

extension ByteBuffer {
    // MARK: Data APIs

    /// Return `length` bytes starting at `index` and return the result as `Data`. This will not change the reader index.
    ///
    /// - parameters:
    ///     - index: The starting index of the bytes of interest into the `ByteBuffer`
    ///     - length: The number of bytes of interest
    /// - returns: A `Data` value containing the bytes of interest or `nil` if the `ByteBuffer` doesn't contain those bytes.
    public func getData(at index: Int, length: Int) -> Data? {
        precondition(length >= 0, "length must not be negative")
        precondition(index >= 0, "index must not be negative")
        guard index <= self.capacity - length else {
            return nil
        }
        return self.withVeryUnsafeBytesWithStorageManagement { ptr, storageRef in
            _ = storageRef.retain()
            return Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: ptr.baseAddress!.advanced(by: index)),
                        count: Int(length),
                        deallocator: .custom { _, _ in storageRef.release() })
        }
    }

    /// Read `length` bytes off this `ByteBuffer`, move the reader index forward by `length` bytes and return the result
    /// as `Data`.
    ///
    /// - parameters:
    ///     - length: The number of bytes to be read from this `ByteBuffer`.
    /// - returns: A `Data` value containing `length` bytes or `nil` if there aren't at least `length` bytes readable.
    public mutating func readData(length: Int) -> Data? {
        precondition(length >= 0, "length must not be negative")
        guard self.readableBytes >= length else {
            return nil
        }
        let data = self.getData(at: self.readerIndex, length: length)! /* must work, enough readable bytes */
        self.moveReaderIndex(forwardBy: length)
        return data
    }
}

public enum HTTPClientError: Error {
    case malformedHead, malformedBody, error(Error)
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

    func errorCaught(ctx: ChannelHandlerContext, error: Error) {
        promise.fail(error: HTTPClientError.error(error))
        ctx.fireErrorCaught(error)
    }

    public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            switch state {
            case .ready: state = .parsingBody(head, nil)
            case .parsingBody: promise.fail(error: HTTPClientError.malformedHead)
            }
        case .body(var body):
            switch state {
            case .ready: promise.fail(error: HTTPClientError.malformedBody)
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
            case .ready: promise.fail(error: HTTPClientError.malformedHead)
            case .parsingBody(let head, let data):
                let res = Response(head: head, body: data ?? Data())
                if ctx.channel.isActive {
                    ctx.fireChannelRead(wrapOutboundOut(res))
                }
                promise.succeed(result: res)
                state = .ready
            }
        }
    }
}

public final class HTTPClient {
    private let hostname: String
    private let port: Int
    private let eventGroup: EventLoopGroup

    public init(hostname: String, port: Int = 80, eventGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numThreads: System.coreCount)) {
        self.hostname = hostname
        self.port = port
        self.eventGroup = eventGroup
    }

    public func connect(
        head: HTTPRequestHead = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: "/"),
        body: Data = Data()
        ) throws -> EventLoopFuture<Response> {
        var head = head
        head.headers.add(name: "User-Agent", value: "AWS SDK Swift Core")

        var preHandlers = [ChannelHandler]()
        if (port == 443) {
            do {
                let tlsConfiguration = TLSConfiguration.forClient()
                let sslContext = try SSLContext(configuration: tlsConfiguration)
                let tlsHandler = try OpenSSLClientHandler(context: sslContext, serverHostname: hostname)
                preHandlers.append(tlsHandler)
            } catch {
                print("Unable to setup TLS: \(error)")
            }
        }
        let response: EventLoopPromise<Response> = eventGroup.next().newPromise()

        _ = ClientBootstrap(group: eventGroup)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                let accumulation = HTTPClientResponseHandler(promise: response)
                let results = preHandlers.map { channel.pipeline.add(handler: $0) }
                return EventLoopFuture<Void>.andAll(results, eventLoop: channel.eventLoop).then {
                    channel.pipeline.addHTTPClientHandlers().then {
                        channel.pipeline.add(handler: accumulation)
                    }
                }
            }
            .connect(host: hostname, port: port)
            .then { channel -> EventLoopFuture<Void> in
                channel.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)
                return channel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)))
        }
        return response.futureResult
    }
    
    public func close(_ callback: @escaping (Error?) -> Void) {
        eventGroup.shutdownGracefully(callback)
    }
}
