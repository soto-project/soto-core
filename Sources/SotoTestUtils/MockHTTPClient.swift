//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// Mock AWS HTTP Client for testing

import HTTPTypes
import Logging
import NIOCore
import SotoCore
import SotoXML

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

package enum MockHTTPClientError: Error {
    case corruptChunkedData
}

package struct MockHTTPClient: AWSHTTPClient {
    private let requestHandler: @Sendable (AWSHTTPRequest) async throws -> AWSHTTPResponse

    package init(
        requestHandler: @escaping (@Sendable (AWSHTTPRequest) async throws -> AWSHTTPResponse) = { _ in .init(response: .init(status: .ok)) }
    ) {
        self.requestHandler = requestHandler
    }

    package struct AWSError: Error {
        let status: HTTPResponse.Status
        let code: String?
        let message: String?

        package init(status: HTTPResponse.Status, code: String? = nil, message: String? = nil) {
            self.status = status
            self.code = code
            self.message = message
        }

        package func response(for serviceProtocol: ServiceProtocol) -> AWSHTTPResponse {
            guard let code = self.code else {
                return AWSHTTPResponse(response: .init(status: status))
            }
            return switch serviceProtocol {
            case .json:
                if let message {
                    AWSHTTPResponse(
                        response: .init(status: status),
                        body: .init(string: "{\"__type\":\"\(code)\", \"message\": \"\(message)\"}")
                    )
                } else {
                    AWSHTTPResponse(response: .init(status: status), body: .init(string: "{\"__type\":\"\(code)\"}"))
                }
            case .restjson:
                if let message {
                    AWSHTTPResponse(response: .init(status: status), body: .init(string: "{\"code\":\"\(code)\", \"message\": \"\(message)\"}"))
                } else {
                    AWSHTTPResponse(response: .init(status: status), body: .init(string: "{\"code\":\"\(code)\"}"))
                }
            case .restxml:
                if let message {
                    AWSHTTPResponse(
                        response: .init(status: status),
                        body: .init(string: "<Error><Code>\(code)</Code><Message>\(message)</Message></Error>")
                    )
                } else {
                    AWSHTTPResponse(response: .init(status: status), body: .init(string: "<Error><Code>\(code)</Code></Error>"))
                }
            default:
                fatalError("Protocol is not supported")
            }
        }
    }

    package init<Input: Decodable & Sendable, Output: Encodable & Sendable>(
        serviceProtocol: ServiceProtocol = .restjson,
        shapeHandler: @escaping (@Sendable (Input) async throws -> Output)
    ) {
        self.requestHandler = { request in
            let inputData = try await request.body.collect(upTo: .max)
            let input: Input
            switch serviceProtocol {
            case .json, .restjson:
                input = try JSONDecoder().decode(Input.self, from: inputData)
            case .restxml:
                guard let xmlNode = try XML.Document(string: String(buffer: inputData)).rootElement() else {
                    return AWSError(status: .internalServerError, code: "InvalidData").response(for: .restxml)
                }
                input = try XMLDecoder().decode(Input.self, from: xmlNode)
            default:
                fatalError("Protocol is not supported")
            }

            do {
                // process
                let response = try await shapeHandler(input)

                // Convert to Output AWSShape
                let outputBuffer: ByteBuffer

                switch serviceProtocol {
                case .json, .restjson:
                    let outputData = try JSONEncoder().encode(response)
                    outputBuffer = ByteBuffer(data: outputData)
                case .restxml:
                    let outputString = try XMLEncoder().encode(response)?.xmlString ?? ""
                    outputBuffer = ByteBuffer(string: outputString)
                default:
                    fatalError("Protocol is not supported")
                }
                return .init(response: .init(status: .ok), body: .init(buffer: outputBuffer))
            } catch let error as AWSError {
                return error.response(for: serviceProtocol)
            }
        }
    }

    package func execute(
        request: AWSHTTPRequest,
        timeout: Duration,
        logger: Logger
    ) async throws -> AWSHTTPResponse {
        let response: AWSHTTPResponse
        do {
            if request.headers[.contentEncoding] == "aws-chunked" {
                let request = AWSHTTPRequest(
                    request: request.request,
                    body: .init(asyncSequence: AWSChunkedBufferStream(base: request.body), length: nil)
                )
                response = try await requestHandler(request)
            } else {
                response = try await requestHandler(request)
            }
        } catch {
            response = .init(
                response: .init(status: .internalServerError),
                body: .init(string: "{\"__type\":\"InternalFailure\", \"message\": \"\(error)\"}")
            )
        }
        var responseHead = response.response
        if let length = response.body.length {
            responseHead.headerFields[.contentLength] = String(length)
        } else if responseHead.headerFields[.contentLength] == nil {
            responseHead.headerFields[.transferEncoding] = "chunked"
        }
        return AWSHTTPResponse(response: responseHead, body: response.body)
    }
}

package struct AWSChunkedBufferStream<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable where Base.Element == ByteBuffer {
    package typealias Element = ByteBuffer

    enum ReadChunkStatus {
        case none
        case readingSize(String = "")
        case readingSignature(Int, Int)
        case readingChunk(Int)
        case readingEnd(String = "")
        case finishing(String = "")
        case finished
    }

    let base: Base

    package struct AsyncIterator: AsyncIteratorProtocol {
        var baseIterator: Base.AsyncIterator
        var status: ReadChunkStatus = .none

        mutating package func next() async throws -> ByteBuffer? {
            guard var buffer = try await baseIterator.next() else { return nil }
            var outputBuffer = ByteBuffer()
            self.status = try readChunkedData(status: self.status, input: &buffer, output: &outputBuffer)
            return outputBuffer
        }

        func readChunkedData(status: ReadChunkStatus, input: inout ByteBuffer, output: inout ByteBuffer) throws -> ReadChunkStatus {
            var status = status

            func _readChunkSize(chunkSize: String, input: inout ByteBuffer) throws -> ReadChunkStatus {
                var chunkSize = chunkSize
                while input.readableBytes > 0 {
                    guard let char = input.readString(length: 1) else { throw MockHTTPClientError.corruptChunkedData }
                    chunkSize += char
                    if chunkSize.hasSuffix(";") {
                        let hexChunkSize = String(chunkSize.dropLast(1))
                        guard let chunkSize = Int(hexChunkSize, radix: 16) else { throw MockHTTPClientError.corruptChunkedData }
                        return .readingSignature(16 + 64 + 2, chunkSize)  // "chunk-signature=" + hex(sha256) + "\r\n"
                    }
                }
                return .readingSize(chunkSize)
            }

            func _readChunkEnd(chunkEnd: String, input: inout ByteBuffer) throws -> ReadChunkStatus {
                var chunkEnd = chunkEnd
                while input.readableBytes > 0 {
                    guard let char = input.readString(length: 1) else { throw MockHTTPClientError.corruptChunkedData }
                    chunkEnd += char
                    if chunkEnd == "\r\n" {
                        return .none
                    } else if chunkEnd.count > 2 {
                        throw MockHTTPClientError.corruptChunkedData
                    }
                }
                return .readingEnd(chunkEnd)
            }

            while input.readableBytes > 0 {
                switch status {
                case .none:
                    status = try _readChunkSize(chunkSize: "", input: &input)

                case .readingSize(let chunkSize):
                    status = try _readChunkSize(chunkSize: chunkSize, input: &input)

                case .readingSignature(let size, let chunkSize):
                    let blockSize = Swift.min(size, input.readableBytes)
                    _ = input.readSlice(length: blockSize)
                    if blockSize == size {
                        if chunkSize == 0 {
                            status = .finishing()
                        } else {
                            status = .readingChunk(chunkSize)
                        }
                    } else {
                        status = .readingSignature(size - blockSize, chunkSize)
                    }

                case .readingChunk(let size):
                    let blockSize = Swift.min(size, input.readableBytes)
                    var slice = input.readSlice(length: blockSize)!
                    output.writeBuffer(&slice)
                    if blockSize == size {
                        status = .readingEnd()
                    } else {
                        status = .readingChunk(size - blockSize)
                    }

                case .readingEnd(let chunkEnd):
                    status = try _readChunkEnd(chunkEnd: chunkEnd, input: &input)

                case .finishing(let chunkEnd):
                    status = try _readChunkEnd(chunkEnd: chunkEnd, input: &input)
                    if case .none = status {
                        status = .finished
                    }

                case .finished:
                    throw MockHTTPClientError.corruptChunkedData
                }
            }
            return status
        }

    }

    package func makeAsyncIterator() -> AsyncIterator {
        .init(baseIterator: base.makeAsyncIterator())
    }
}
