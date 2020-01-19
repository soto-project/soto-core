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

    let client = NIOTSHTTPClient(eventLoopGroup: NIOTSEventLoopGroup())

    deinit {
        try? client.syncShutdown()
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

    func testInitWithValidRL() {
        do {
            let request = AWSHTTPRequest(url: URL(string:"https://kinesis.us-west-2.amazonaws.com/")!, method: .GET, headers: HTTPHeaders(), body: nil)
            _ = try client.execute(request: request, timeout: .seconds(5)).wait()
        } catch {
            XCTFail("Should not throw malformedURL error")
        }

        do {
            let request = AWSHTTPRequest(url: URL(string:"http://169.254.169.254/latest/meta-data/iam/security-credentials/")!, method: .GET, headers: HTTPHeaders(), body: nil)
            _ = try client.execute(request: request, timeout: .seconds(5)).wait()
        } catch NIOTSHTTPClient.HTTPError.malformedURL{
            XCTFail("Should not throw malformedURL error")
        } catch {
        }
    }

    func testConnectGet() {
        do {
            let request = AWSHTTPRequest(url: URL(string:"https://kinesis.us-west-2.amazonaws.com/")!, method: .GET, headers: HTTPHeaders(), body: nil)
            let future = client.execute(request: request, timeout: .seconds(5))

            _ = try future.wait()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testConnectPost() {
        do {
            let request = AWSHTTPRequest(url: URL(string:"https://kinesis.us-west-2.amazonaws.com/")!, method: .POST, headers: HTTPHeaders(), body: nil)
            let future = client.execute(request: request, timeout: .seconds(5))

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
    let client = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .createNew)
    
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
    
    init(_ client: AWSHTTPClient) {
        self.client = client
    }
    
    func execute(_ request: AWSHTTPRequest) throws -> Future<HTTPBinResponse> {
        return client.execute(request: request, timeout: .seconds(5))
            .flatMapThrowing { response in
                print(String(data: response.bodyData ?? Data(), encoding: .utf8)!)
                return try JSONDecoder().decode(HTTPBinResponse.self, from: response.bodyData ?? Data())
        }
    }
    
    func testGet() {
        do {
            let headers: HTTPHeaders = [:]
            let request = AWSHTTPRequest(url: URL(string:"http://httpbin.org/get?arg=1")!, method: .GET, headers: headers, body: nil)
            let response = try execute(request).wait()
            
            XCTAssertEqual(response.args["arg"], "1")
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
                "Content-Type": "application/json",
                "Test-Header": "testValue"
            ]
            let request = AWSHTTPRequest(url: URL(string:"http://httpbin.org/post")!, method: .POST, headers: headers, body: nil)
            let response = try execute(request).wait()
            
            XCTAssertEqual(response.headers["Test-Header"], "testValue")
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
            let request = AWSHTTPRequest(url: URL(string:"http://httpbin.org/post")!, method: .POST, headers: headers, body: body)
            let response = try execute(request).wait()
            
            XCTAssertEqual(response.data, "thisisatest")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
}

