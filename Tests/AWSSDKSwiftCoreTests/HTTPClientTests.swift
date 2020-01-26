//
//  DictionarySerializer.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/04/06.
//
//

import XCTest
import AsyncHTTPClient
import NIO
import NIOHTTP1
import NIOTransportServices
import NIOTestUtils

@testable import AWSSDKSwiftCore

extension AWSHTTPResponse {
    var bodyData: Data? {
        if let body = self.body {
            return body.getData(at: body.readerIndex, length: body.readableBytes, byteTransferStrategy: .noCopy)
        }
        return nil
    }
}

#if canImport(Network)

@available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)
class NIOTSHTTPClientTests: XCTestCase {

    var awsServer: AWSTestServer!
    var client: NIOTSHTTPClient!
    
    override func setUp() {
        self.awsServer = AWSTestServer(serviceProtocol: .json)
        self.client = NIOTSHTTPClient(eventLoopGroup: NIOTSEventLoopGroup())
    }
    
    override func tearDown() {
        XCTAssertNoThrow(try self.awsServer.stop())
        XCTAssertNoThrow(try self.client.syncShutdown())
    }
    
    func testInitWithInvalidURL() {
      do {
        let request = AWSHTTPRequest(url: URL(string:"no_protocol.com")!, method: .GET, headers: HTTPHeaders(), body: nil)
        _ = try client.execute(request: request, timeout: .seconds(5)).wait()
        XCTFail("Should throw malformedURL error")
      } catch {
        if case NIOTSHTTPClient.HTTPError.malformedURL = error {}
        else {
            XCTFail("Should throw malformedURL error")
        }
      }
    }

    func testConnectGet() {
        do {
            let request = AWSHTTPRequest(url: awsServer.address, method: .GET, headers: HTTPHeaders(), body: nil)
            let future = client.execute(request: request, timeout: .seconds(5))
            try awsServer.echo()
            _ = try future.wait()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testConnectPost() {
        do {
            let request = AWSHTTPRequest(url: awsServer.address, method: .POST, headers: HTTPHeaders(), body: nil)
            let future = client.execute(request: request, timeout: .seconds(5))
            try awsServer.echo()
            _ = try future.wait()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testGet() {
        HTTPClientTests(client).testGet()
    }

    func testHTTPS() {
        HTTPClientTests(client).testHTTPS()
    }

    func testHeaders() {
        HTTPClientTests(client).testHeaders()
    }

    func testBody() {
        HTTPClientTests(client).testBody()
    }
}

#endif //canImport(Network)

class AsyncHTTPClientTests: XCTestCase {
    var client: AsyncHTTPClient.HTTPClient!
    override func setUp() {
        self.client = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .createNew)
    }
    
    override func tearDown() {
        XCTAssertNoThrow(try self.client.syncShutdown())
    }
    
    deinit {
        try? client.syncShutdown()
    }

    func testGet() {
        HTTPClientTests(client).testGet()
    }

    func testHeaders() {
        HTTPClientTests(client).testHeaders()
    }

    func testBody() {
        HTTPClientTests(client).testBody()
    }

    static var allTests : [(String, (AsyncHTTPClientTests) -> () throws -> Void)] {
        return [
            ("testGet", testGet),
            ("testHeaders", testHeaders),
            ("testBody", testBody),
        ]
    }
}

/// HTTP Client tests, to be used with any HTTP client that conforms to AWSHTTPClient
class HTTPClientTests {

    struct HTTPBinResponse: Codable {
        let args: [String: String]
        let data: String?
        let headers: [String: String]
        let url: String
    }

    let client: AWSHTTPClient
    let awsServer: AWSTestServer

    init(_ client: AWSHTTPClient) {
        self.client = client
        self.awsServer = AWSTestServer(serviceProtocol: .json)
    }

    deinit {
        XCTAssertNoThrow(try self.awsServer.stop())
    }
    func execute(_ request: AWSHTTPRequest) throws -> EventLoopFuture<HTTPBinResponse> {
        return client.execute(request: request, timeout: .seconds(5))
            .flatMapThrowing { response in
                print(String(data: response.bodyData ?? Data(), encoding: .utf8)!)
                return try JSONDecoder().decode(HTTPBinResponse.self, from: response.bodyData ?? Data())
        }
    }

    func testGet() {
        do {
            let headers: HTTPHeaders = [:]
            let request = AWSHTTPRequest(url: awsServer.address.appendingPathComponent("get"), method: .GET, headers: headers, body: nil)
            let responseFuture = client.execute(request: request, timeout: .seconds(5))
            
            try awsServer.echo()

            let response = try responseFuture.wait()
            print(response)

            XCTAssertEqual(response.headers["echo-method"].first, "GET")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testHTTPS() {
        do {
            let headers: HTTPHeaders = [:]
            let request = AWSHTTPRequest(url: URL(string:"https://httpbin.org/get")!, method: .GET, headers: headers, body: nil)
            let response = try execute(request).wait()

            XCTAssertEqual(response.url, "https://httpbin.org/get")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testHeaders() {
        do {
            let headers: HTTPHeaders = [
                "Test-Header": "testValue"
            ]
            let request = AWSHTTPRequest(url: awsServer.address, method: .POST, headers: headers, body: nil)
            let responseFuture = client.execute(request: request, timeout: .seconds(5))
            
            try awsServer.echo()

            let response = try responseFuture.wait()

            XCTAssertEqual(response.headers["echo-method"].first, "POST")
            XCTAssertEqual(response.headers["Test-Header"].first, "testValue")
            
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testBody() {
        do {
            let headers: HTTPHeaders = [
                "Content-Type": "text/plain"
            ]
            let text = "thisisatest"
            var body = ByteBufferAllocator().buffer(capacity: text.utf8.count)
            body.writeString(text)
            let request = AWSHTTPRequest(url: awsServer.address, method: .POST, headers: headers, body: body)
            let responseFuture = client.execute(request: request, timeout: .seconds(5))
            
            try awsServer.echo()

            let response = try responseFuture.wait()

            let string = response.body?.getString(at: 0, length: response.body?.readableBytes ?? 0, encoding: .utf8)
            XCTAssertEqual(response.headers["echo-method"].first, "POST")
            XCTAssertEqual(string, "thisisatest")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
}

