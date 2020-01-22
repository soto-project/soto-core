//TestServer.swift
//
//

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
        case json
        case xml
    }
    // http incoming request
    struct Request {
        let headers: [String: String]
        let body: ByteBuffer
    }
    // http outgoing response
    struct Response {
        let httpStatus: HTTPResponseStatus
        let headers: [String: String]
        let body: ByteBuffer
    }
    // result from process
    struct Result<Output>{
        let output: Output
        let continueProcessing: Bool
    }
    
    let web: NIOHTTP1TestServer
    let serviceProtocol: ServiceProtocol
    var serverPort: Int { return web.serverPort }
    let byteBufferAllocator: ByteBufferAllocator

    
    init(serviceProtocol: ServiceProtocol, eventLoopGroup: EventLoopGroup) {
        self.web = NIOHTTP1TestServer(group: eventLoopGroup)
        self.serviceProtocol = serviceProtocol
        self.byteBufferAllocator = ByteBufferAllocator()
    }
    
    func process<Input: AWSShape, Output: AWSShape>(_ process: (Input) throws -> Result<Output>) throws {
        var continueProcessing =  true
        while(continueProcessing) {
            // read inbound
            let head = try web.readInbound()
            guard case .head(_) = head else {throw Error.notHead}
            let body = try web.readInbound()
            guard case .body(let buffer) = body else {throw Error.notBody}
            let end = try web.readInbound()
            guard case .end(_) = end else {throw Error.notEnd}
            guard let data = buffer.getData(at: 0, length: buffer.readableBytes) else {throw Error.emptyBody}
            
            let input: Input
            switch serviceProtocol {
            case .json:
                input = try JSONDecoder().decode(Input.self, from: data)
            case .xml:
                guard let xmlNode = try XML.Document(data: data).rootElement() else {throw Error.noXMLBody}
                input = try XMLDecoder().decode(Input.self, from: xmlNode)
            }
            
            // process
            let result = try process(input)
            
            continueProcessing = result.continueProcessing
            
            // write outbound
            let outputData: Data
            switch serviceProtocol {
            case .json:
                outputData = try JSONEncoder().encode(result.output)
            case .xml:
                outputData = try XMLEncoder().encode(result.output).xmlString.data(using: .utf8) ?? Data()
            }

            var byteBuffer = byteBufferAllocator.buffer(capacity: 0)
            byteBuffer.writeBytes(outputData)
            XCTAssertNoThrow(try web.writeOutbound(.head(.init(version: .init(major: 1, minor: 1),
                                                               status: .ok))))
            XCTAssertNoThrow(try web.writeOutbound(.body(.byteBuffer(byteBuffer))))
            XCTAssertNoThrow(try web.writeOutbound(.end(nil)))
        }
    }
    
    func process(_ process: (Request) throws -> Result<Response>) throws {
        var continueProcessing =  true
        while(continueProcessing) {
            // read inbound
            guard case .head(let head) = try web.readInbound() else {throw Error.notHead}
            guard case .body(let buffer) = try web.readInbound() else {throw Error.notBody}
            guard case .end(_) = try web.readInbound() else {throw Error.notEnd}
            
            var requestHeaders: [String: String] = [:]
            for (key, value) in head.headers {
                requestHeaders[key.description] = value
            }

            let request = Request(headers: requestHeaders, body: buffer)
            
            // process
            let result = try process(request)
            
            continueProcessing = result.continueProcessing
            
            XCTAssertNoThrow(try web.writeOutbound(.head(.init(version: .init(major: 1, minor: 1),
                                                               status: result.output.httpStatus,
                                                               headers: HTTPHeaders(result.output.headers.map { ($0,$1) })))))
            XCTAssertNoThrow(try web.writeOutbound(.body(.byteBuffer(result.output.body))))
            XCTAssertNoThrow(try web.writeOutbound(.end(nil)))
        }
    }
    
    func echo() throws {
        var byteBuffers: [ByteBuffer] = []
        // read inbound
        guard case .head(let head) = try web.readInbound() else {throw Error.notHead}
        // read body
        while(true) {
            let inbound = try web.readInbound()
            if case .body(let buffer) = inbound {
                byteBuffers.append(buffer)
            } else if case .end(_) = inbound {
                break
            } else {
                throw Error.notEnd
            }
        }
        
        // write outbound
        XCTAssertNoThrow(try web.writeOutbound(.head(.init(version: head.version,
                                                           status: .ok,
                                                           headers: head.headers))))
        try byteBuffers.forEach {
            XCTAssertNoThrow(try web.writeOutbound(.body(.byteBuffer($0))))
        }
        XCTAssertNoThrow(try web.writeOutbound(.end(nil)))
    }
    
    func stop() throws {
        try web.stop()
    }
}

