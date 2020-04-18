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

import NIO
import NIOFoundationCompat
import NIOHTTP1
import NIOTestUtils
import XCTest
@testable import AWSSDKSwiftCore

/// Test server for AWSClient. Input and Output shapes are defined by process function
class AWSTestServer {

    enum Error: Swift.Error {
        case notHead
        case notBody
        case notEnd
        case emptyBody
        case noXMLBody
    }
    // what are we returning
    enum ServiceProtocol {
        case restjson
        case json
        case xml
    }
    // http incoming request
    struct Request {
        let method: HTTPMethod
        let uri: String
        let headers: [String: String]
        let body: ByteBuffer
    }
    // http outgoing response
    struct Response {
        let httpStatus: HTTPResponseStatus
        let headers: [String: String]
        let body: ByteBuffer?

        init(httpStatus: HTTPResponseStatus, headers: [String: String] = [:], body: ByteBuffer? = nil) {
            self.httpStatus = httpStatus
            self.headers = headers
            self.body = body
        }

        static let ok = Response(httpStatus: .ok)
    }

    // result from process
    struct Result<Output>{
        let output: Output
        let continueProcessing: Bool
    }
    // httpBin function response
    struct HTTPBinResponse: Codable {
        let method: String?
        let data: String?
        let headers: [String: String]
        let url: String
    }

    let eventLoopGroup: EventLoopGroup
    let web: NIOHTTP1TestServer
    let serviceProtocol: ServiceProtocol
    var serverPort: Int { return web.serverPort }
    var address: String { return "http://localhost:\(web.serverPort)"}
    var addressURL: URL { return URL(string: "http://localhost:\(web.serverPort)")!}
    let byteBufferAllocator: ByteBufferAllocator


    init(serviceProtocol: ServiceProtocol) {
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.web = NIOHTTP1TestServer(group: self.eventLoopGroup)
        self.serviceProtocol = serviceProtocol
        self.byteBufferAllocator = ByteBufferAllocator()
        print("Starting serving on localhost:\(serverPort)")
    }

    /// run server reading request, convert from to an input shape processing them and converting the result back to a response.
    func process<Input: Decodable, Output: Encodable>(_ process: (Input) throws -> Result<Output>) throws {
        while(try processSingleRequest(process)) { }
    }

    /// run server reading request, convert from to an input shape processing them and converting the result back to a response. Return an error after so many requests
    func processWithErrors<Input: Decodable, Output: Encodable>(_ process: (Input) throws -> Result<Output>, errors: (Int) -> Result<ErrorType?>) throws {
        var count = 0
        var continueProcessing = true
        repeat {
            let errorResult = errors(count)
            if let error = errorResult.output {
                _ = try readRequest()
                try writeError(error)
                continueProcessing = errorResult.continueProcessing
            } else if errorResult.continueProcessing == false {
                continueProcessing = false
            } else {
                continueProcessing = try processSingleRequest(process)
            }
            count += 1
        } while(continueProcessing)
    }

    /// run server reading requests, processing them and returning responses
    func process(_ process: (Request) throws -> Result<Response>) throws {
        while(try processSingleRequest(process)) { }
    }

    /// run server reading requests, processing them and returning responses. Return an error after so many requests
    func processWithErrors(process: (Request) throws -> Result<Response>, errors: (Int) -> Result<ErrorType?>) throws {
        var count = 0
        var continueProcessing = true
        repeat {
            let errorResult = errors(count)
            if let error = errorResult.output {
                _ = try readRequest()
                try writeError(error)
                continueProcessing = errorResult.continueProcessing
            } else if errorResult.continueProcessing == false {
                continueProcessing = false
            } else {
                continueProcessing = try processSingleRequest(process)
            }
            count += 1
        } while(continueProcessing)
    }


    /// read one request and return details back in body
    func httpBin() throws {
        let request = try readRequest()

        let data = request.body.getString(at: 0, length: request.body.readableBytes, encoding: .utf8)
        let httpBinResponse = HTTPBinResponse(
            method: request.method.rawValue,
            data: data,
            headers: request.headers,
            url: request.uri)
        let responseBody = try JSONEncoder().encodeAsByteBuffer(httpBinResponse, allocator: ByteBufferAllocator())
        try writeResponse(Response(httpStatus: .ok, headers: [:], body: responseBody))
    }

    func stop() throws {
        print("Stop serving on localhost:\(serverPort)")
        try web.stop()
        try eventLoopGroup.syncShutdownGracefully()
    }
}

// errors
extension AWSTestServer {
    struct ErrorType {
        let status: Int
        let errorCode: String
        let message: String

        var json: String { return "{\"__type\":\"\(errorCode)\", \"message\": \"\(message)\"}"}
        var xml: String { return "<Error><Code>\(errorCode)</Code><Message>\(message)</Message></Error>"}

        static let badRequest = ErrorType(status: 400, errorCode: "BadRequest", message: "AWSTestServer_ErrorType_BadRequest")
        static let accessDenied = ErrorType(status: 401, errorCode: "AccessDenied", message: "AWSTestServer_ErrorType_AccessDenied")
        static let notFound = ErrorType(status: 404, errorCode: "NotFound", message: "AWSTestServer_ErrorType_NotFound")
        static let tooManyRequests = ErrorType(status: 429, errorCode: "TooManyRequests", message: "AWSTestServer_ErrorType_TooManyRequests")

        static let `internal` = ErrorType(status: 500, errorCode: "InternalError", message: "AWSTestServer_ErrorType_InternalError")
        static let notImplemented = ErrorType(status: 501, errorCode: "NotImplemented", message: "AWSTestServer_ErrorType_NotImplemented")
        static let serviceUnavailable = ErrorType(status: 503, errorCode: "ServiceUnavailable", message: "AWSTestServer_ErrorType_ServiceUnavailable")
    }
}

extension AWSTestServer {
    /// read one request, process it then return the respons
    func processSingleRequest(_ process: (Request) throws -> Result<Response>) throws -> Bool {
        let request = try readRequest()
        let result = try process(request)
        try writeResponse(result.output)

        return result.continueProcessing
    }

    /// read one request, convert it from to an input shape, processing it and convert the result back to a response.
    func processSingleRequest<Input: Decodable, Output: Encodable>(_ process: (Input) throws -> Result<Output>) throws -> Bool {
        let request = try readRequest()

        // Convert to Input AWSShape
        guard let inputData = request.body.getData(at: 0, length: request.body.readableBytes) else {throw Error.emptyBody}
        let input: Input
        switch serviceProtocol {
        case .json, .restjson:
            input = try JSONDecoder().decode(Input.self, from: inputData)
        case .xml:
            guard let xmlNode = try XML.Document(data: inputData).rootElement() else {throw Error.noXMLBody}
            input = try XMLDecoder().decode(Input.self, from: xmlNode)
        }

        // process
        let result = try process(input)

        // Convert to Output AWSShape
        let outputData: Data
        switch serviceProtocol {
        case .json, .restjson:
            outputData = try JSONEncoder().encode(result.output)
        case .xml:
            outputData = try XMLEncoder().encode(result.output).xmlString.data(using: .utf8) ?? Data()
        }
        var byteBuffer = byteBufferAllocator.buffer(capacity: 0)
        byteBuffer.writeBytes(outputData)

        try writeResponse(Response(httpStatus: .ok, headers: [:], body: byteBuffer))

        return result.continueProcessing
    }

    /// read inbound request
    func readRequest() throws -> Request {
        var byteBuffer = byteBufferAllocator.buffer(capacity: 0)

        // read inbound
        guard case .head(let head) = try web.readInbound() else {throw Error.notHead}
        // read body
        while(true) {
            let inbound = try web.readInbound()
            if case .body(var buffer) = inbound {
                byteBuffer.writeBuffer(&buffer)
            } else if case .end(_) = inbound {
                break
            } else {
                throw Error.notEnd
            }
        }
        var requestHeaders: [String: String] = [:]
        for (key, value) in head.headers {
            requestHeaders[key.description] = value
        }
        return Request(method: head.method, uri: head.uri, headers: requestHeaders, body: byteBuffer)
    }

    /// write outbound response
    func writeResponse(_ response: Response) throws {
        XCTAssertNoThrow(try web.writeOutbound(.head(.init(version: .init(major: 1, minor: 1),
                                                           status: response.httpStatus,
                                                           headers: HTTPHeaders(response.headers.map { ($0,$1) })))))
        if let body = response.body, body.readableBytes > 0 {
            XCTAssertNoThrow(try web.writeOutbound(.body(.byteBuffer(body))))
        }
        XCTAssertNoThrow(try web.writeOutbound(.end(nil)))
    }

    /// write error
    func writeError(_ error: ErrorType) throws {
        let errorString: String
        var headers: [String: String] = [:]
        switch serviceProtocol {
        case .json:
            errorString = error.json
        case .restjson:
            errorString = error.json
            headers["x-amzn-ErrorType"] = error.errorCode
        case .xml:
            errorString = error.xml
        }

        var byteBuffer = byteBufferAllocator.buffer(capacity: 0)
        byteBuffer.writeString(errorString)

        try writeResponse(Response(httpStatus: HTTPResponseStatus(statusCode:error.status), headers: headers, body: byteBuffer))
    }
}
