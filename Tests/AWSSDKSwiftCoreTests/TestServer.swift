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
        let body: ByteBuffer
    }
    // result from process
    struct Result<Output>{
        let output: Output
        let continueProcessing: Bool
    }
    
    let eventLoopGroup: EventLoopGroup
    let web: NIOHTTP1TestServer
    let serviceProtocol: ServiceProtocol
    var serverPort: Int { return web.serverPort }
    var address: URL { return URL(string: "http://localhost:\(web.serverPort)")!}
    let byteBufferAllocator: ByteBufferAllocator

    
    init(serviceProtocol: ServiceProtocol) {
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.web = NIOHTTP1TestServer(group: self.eventLoopGroup)
        self.serviceProtocol = serviceProtocol
        self.byteBufferAllocator = ByteBufferAllocator()
        print("Starting serving on localhost:\(serverPort)")
    }
    
    /// run server reading request, convert from to an input shape processing them and converting the result back to a response.
    func process<Input: AWSShape, Output: AWSShape>(_ process: (Input) throws -> Result<Output>) throws {
        while(try processSingleRequest(process)) { }
    }
    
    /// run server reading request, convert from to an input shape processing them and converting the result back to a response. Return an error after so many requests
    func ProcessWithErrors<Input: AWSShape, Output: AWSShape>(_ process: (Input) throws -> Result<Output>, error: ErrorType, errorAfter: Int) throws {
        var count = errorAfter
        repeat {
            if count == 0 {
                _ = try readRequest()
                try writeError(error)
                return
            }
            count -= 1
        } while(try processSingleRequest(process))
    }

    /// run server reading requests, processing them and returning responses
    func process(_ process: (Request) throws -> Result<Response>) throws {
        while(try processSingleRequest(process)) { }
    }
    
    /// run server reading requests, processing them and returning responses. Return an error after so many requests
    func ProcessWithErrors(_ process: (Request) throws -> Result<Response>, error: ErrorType, errorAfter: Int) throws {
        var count = errorAfter
        repeat {
            if count == 0 {
                _ = try readRequest()
                try writeError(error)
                return
            }
            count -= 1
        } while(try processSingleRequest(process))
    }
    

    /// read one request and return it back
    func echo() throws {
        let request = try readRequest()
        var headers = request.headers
        headers["echo-uri"] = request.uri
        headers["echo-method"] =  request.method.rawValue
        try writeResponse(Response(httpStatus: .ok, headers: headers, body: request.body))
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
    func processSingleRequest<Input: AWSShape, Output: AWSShape>(_ process: (Input) throws -> Result<Output>) throws -> Bool {
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
        if response.body.writableBytes > 0 {
            XCTAssertNoThrow(try web.writeOutbound(.body(.byteBuffer(response.body))))
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
