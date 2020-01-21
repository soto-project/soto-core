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
    enum ServiceProtocol {
        case json
        case xml
    }
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
    
    func stop() throws {
        try web.stop()
    }
}

