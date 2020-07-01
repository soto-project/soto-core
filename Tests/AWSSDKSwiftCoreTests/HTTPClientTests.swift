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

import XCTest
import AsyncHTTPClient
import NIO
import NIOHTTP1
import NIOTransportServices
import AWSTestUtils

@testable import AWSSDKSwiftCore

#if canImport(Network)

@available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)
class NIOTSHTTPClientTests: XCTestCase {

    var awsServer: AWSTestServer!
    var client: NIOTSHTTPClient!

    override func setUp() {
        self.awsServer = AWSTestServer(serviceProtocol: .json)
        self.client = NIOTSHTTPClient(eventLoopGroupProvider: .shared(NIOTSEventLoopGroup()))
    }

    override func tearDown() {
        XCTAssertNoThrow(try self.awsServer.stop())
        XCTAssertNoThrow(try self.client.syncShutdown())
    }

    func testInitWithInvalidURL() {
      do {
        let request = AWSHTTPRequest(url: URL(string:"no_protocol.com")!, method: .GET, headers: HTTPHeaders())
        _ = try client.execute(request: request, timeout: .seconds(5), on: client.eventLoopGroup.next(), logger: AWSClient.loggingDisabled).wait()
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
            let request = AWSHTTPRequest(url: awsServer.addressURL, method: .GET, headers: HTTPHeaders())
            let future = client.execute(request: request, timeout: .seconds(5), on: client.eventLoopGroup.next(), logger: AWSClient.loggingDisabled)
            try awsServer.httpBin()
            _ = try future.wait()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testConnectPost() {
        do {
            let request = AWSHTTPRequest(url: awsServer.addressURL, method: .POST, headers: HTTPHeaders())
            let future = client.execute(request: request, timeout: .seconds(5), on: client.eventLoopGroup.next(), logger: AWSClient.loggingDisabled)
            try awsServer.httpBin()
            _ = try future.wait()
        } catch {
            XCTFail(error.localizedDescription)
        }
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
}

#endif //canImport(Network)

/// HTTP Client tests, to be used with any HTTP client that conforms to AWSHTTPClient
class HTTPClientTests {

    let client: AWSHTTPClient

    init(_ client: AWSHTTPClient) {
        self.client = client
    }

    func execute(_ request: AWSHTTPRequest) -> EventLoopFuture<AWSTestServer.HTTPBinResponse> {
        return client.execute(request: request, timeout: .seconds(5), on: client.eventLoopGroup.next(), logger: AWSClient.loggingDisabled)
            .flatMapThrowing { response in
                guard let body = response.body else { throw AWSTestServer.Error.emptyBody }
                return try JSONDecoder().decode(AWSTestServer.HTTPBinResponse.self, from: body)
        }
    }

    func testGet() {
        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            defer {
                XCTAssertNoThrow(try awsServer.stop())
            }
            let headers: HTTPHeaders = [:]
            let request = AWSHTTPRequest(url: URL(string: "\(awsServer.address)/get?test=2")!, method: .GET, headers: headers, body: .empty)
            let responseFuture = execute(request)

            try awsServer.httpBin()

            let response = try responseFuture.wait()
            print(response)

            XCTAssertEqual(response.method, "GET")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testHeaders() {
        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            defer {
                XCTAssertNoThrow(try awsServer.stop())
            }
            let headers: HTTPHeaders = [
                "Test-Header": "testValue"
            ]
            let request = AWSHTTPRequest(url: awsServer.addressURL, method: .POST, headers: headers, body: .empty)
            let responseFuture = execute(request)

            try awsServer.httpBin()

            let response = try responseFuture.wait()
            print(response)

            XCTAssertEqual(response.method, "POST")
            XCTAssertEqual(response.headers["Test-Header"], "testValue")

        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testBody() {
        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            defer {
                XCTAssertNoThrow(try awsServer.stop())
            }
            let headers: HTTPHeaders = [
                "Content-Type": "text/plain"
            ]
            let text = "thisisatest"
            var body = ByteBufferAllocator().buffer(capacity: text.utf8.count)
            body.writeString(text)
            let request = AWSHTTPRequest(url: awsServer.addressURL, method: .POST, headers: headers, body: .byteBuffer(body))
            let responseFuture = execute(request)

            try awsServer.httpBin()

            let response = try responseFuture.wait()
            print(response)

            XCTAssertEqual(response.data, "thisisatest")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
}
