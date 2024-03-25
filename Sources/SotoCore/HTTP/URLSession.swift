//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if !os(Linux)
import AsyncAlgorithms
import AsyncHTTPClient
import Foundation
import Logging
import NIOConcurrencyHelpers
import NIOFoundationCompat
import NIOHTTP1

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension URLSession: AWSHTTPClient {
    public struct SotoError: Error, Equatable {
        enum Internal {
            case unexpectedResponse
            case requestStreamFailed
            case streamingError
        }

        let value: Internal
        private init(_ value: Internal) { self.value = value }

        /// Unexpected resposne from URLSession request
        public static var unexpectedResponse: Self { .init(.unexpectedResponse) }
        /// Create a stream failed
        public static var requestStreamFailed: Self { .init(.requestStreamFailed) }
        /// Error occurred while streaming
        public static var streamingError: Self { .init(.streamingError) }
    }

    /// Execute HTTP request
    /// - Parameters:
    ///   - request: HTTP request
    ///   - timeout: If execution is idle for longer than timeout then throw error
    ///   - eventLoop: eventLoop to run request on
    /// - Returns: EventLoopFuture that will be fulfilled with request response
    public func execute(
        request: AWSHTTPRequest,
        timeout: TimeAmount,
        logger: Logger
    ) async throws -> AWSHTTPResponse {
        enum ExecuteTaskReturnValue {
            case void
            case response(AWSHTTPResponse)
        }
        return try await withThrowingTaskGroup(of: ExecuteTaskReturnValue.self) { group in
            var urlRequest = URLRequest(url: request.url)
            urlRequest.httpMethod = request.method.rawValue
            for header in request.headers {
                urlRequest.addValue(header.value, forHTTPHeaderField: header.name)
            }
            switch request.body.storage {
            case .byteBuffer(let byteBuffer):
                urlRequest.httpBody = Data(buffer: byteBuffer)
            case .asyncSequence(let byteBufferSequence, _):
                guard let stream = AsyncSequenceStream(byteBufferSequence: byteBufferSequence) else {
                    throw SotoError.requestStreamFailed
                }
                urlRequest.httpBodyStream = stream.inputStream
                // add task to write async sequence to OutputStream
                group.addTask {
                    try await stream.write()
                    return .void
                }
            }
            let readonlyURLRequest = urlRequest
            // add task to perform HTTP request and process response
            group.addTask {
                let (bytes, urlResponse) = try await self.bytes(for: readonlyURLRequest)
                guard let httpURLResponse = urlResponse as? HTTPURLResponse else { throw SotoError.unexpectedResponse }

                let statusCode = HTTPResponseStatus(statusCode: httpURLResponse.statusCode)
                var headers = HTTPHeaders()
                for header in httpURLResponse.allHeaderFields {
                    guard let name = header.key as? String, let value = header.value as? String else { continue }
                    headers.add(name: name, value: value)
                }
                let body = AWSHTTPBody(asyncSequence: bytes.chunks(ofCount: 16384).map { ByteBuffer(bytes: $0) }, length: nil)

                return .response(.init(status: statusCode, headers: headers, body: body))
            }
            for try await result in group {
                if case .response(let response) = result {
                    // we have a response, we should cancel the streaming task if it is still running
                    group.cancelAll()
                    return response
                }
            }
            preconditionFailure("Cannot get here")
        }
    }
}

/// Create an InputStream whose source is an AsyncSequnce of ByteBuffers
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
class AsyncSequenceStream<BufferSequence: AsyncSequence>: NSObject, StreamDelegate where BufferSequence.Element == ByteBuffer {
    let inputStream: InputStream
    let outputStream: OutputStream
    let byteBufferSequence: BufferSequence
    let maxBufferSize: Int
    let cont: NIOLockedValueBox<CheckedContinuation<Void, Error>?>

    init?(byteBufferSequence: BufferSequence, bufferSize: Int = 16384) {
        self.byteBufferSequence = byteBufferSequence
        self.maxBufferSize = bufferSize
        self.cont = .init(nil)
        // bind an input stream and output stream together.
        var inputStream: InputStream? = nil
        var outputStream: OutputStream? = nil
        Stream.getBoundStreams(
            withBufferSize: self.maxBufferSize,
            inputStream: &inputStream,
            outputStream: &outputStream
        )
        guard let inputStream = inputStream, let outputStream = outputStream else { return nil }
        self.inputStream = inputStream
        self.outputStream = outputStream
        super.init()
        // configure and open output stream
        self.outputStream.delegate = self
        self.outputStream.schedule(in: RunLoop.main, forMode: .default)
        self.outputStream.open()
    }

    /// Write contents of AsyncSequence to output stream
    func write() async throws {
        defer {
            self.outputStream.close()
        }
        for try await buffer in self.byteBufferSequence {
            var bufferSize = buffer.readableBytes
            var offset = 0
            while bufferSize > 0 {
                let size = min(bufferSize, self.maxBufferSize)
                if !self.outputStream.hasSpaceAvailable {
                    try await withTaskCancellationHandler {
                        if Task.isCancelled {
                            throw CancellationError()
                        }
                        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                            self.cont.withLockedValue { $0 = cont }
                        }
                    } onCancel: {
                        self.cont.withLockedValue { cont in
                            cont?.resume(throwing: CancellationError())
                            cont = nil
                        }
                    }
                }
                let bytesWritten = buffer.withUnsafeReadableBytes { buffer in
                    let address = buffer.baseAddress! + offset
                    return self.outputStream.write(address, maxLength: size)
                }
                bufferSize -= bytesWritten
                offset += bytesWritten
            }
        }
    }

    deinit {
        assert(cont.withLockedValue { $0 } == nil)
    }

    func stream(_: Stream, handle event: Stream.Event) {
        switch event {
        case .hasSpaceAvailable:
            self.cont.withLockedValue { cont in
                if let cont = cont {
                    cont.resume()
                }
                cont = nil
            }

        case .errorOccurred:
            self.cont.withLockedValue { cont in
                if let cont = cont {
                    cont.resume(throwing: URLSession.SotoError.streamingError)
                }
                cont = nil
            }

        default:
            break
        }
    }
}

#endif // !os(Linux)
