//
//  DictionarySerializer.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/04/06.
//
//
#if canImport(Network)

import Foundation
import NIOHTTP1
import XCTest
@testable import AWSSDKSwiftCore

@available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)
class NIOTSHTTPClientTests: XCTestCase {

    let client = NIOTSHTTPClient()

    deinit {
        try? client.syncShutdown()
    }
    
    static var allTests : [(String, (NIOTSHTTPClientTests) -> () throws -> Void)] {
        return [
            ("testInitWithInvalidURL", testInitWithInvalidURL),
            ("testInitWithValidRL", testInitWithValidRL),
            ("testConnectSimpleGet", testConnectSimpleGet),
            ("testConnectGet", testConnectGet),
            ("testConnectPost", testConnectPost)
        ]
    }

    func testInitWithInvalidURL() {
      do {
        let head = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: "no_protocol.com")
        let request = NIOTSHTTPClient.Request(head: head, body: Data())
        _ = try client.connect(request, timeout: .seconds(5)).wait()
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
            let head = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: "https://kinesis.us-west-2.amazonaws.com/")
            let request = NIOTSHTTPClient.Request(head: head, body: Data())
            _ = try client.connect(request, timeout: .seconds(5)).wait()
        } catch {
            XCTFail("Should not throw malformedURL error")
        }

        do {
            let head = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: "http://169.254.169.254/latest/meta-data/iam/security-credentials/")
            let request = NIOTSHTTPClient.Request(head: head, body: Data())
            _ = try client.connect(request, timeout: .seconds(5)).wait()
        } catch NIOTSHTTPClient.HTTPError.malformedURL{
            XCTFail("Should not throw malformedURL error")
        } catch {
        }
    }

    func testConnectSimpleGet() {
        do {
            let head = HTTPRequestHead(
                         version: HTTPVersion(major: 1, minor: 1),
                         method: .GET,
                         uri: "https://kinesis.us-west-2.amazonaws.com/"
                       )
            let request = NIOTSHTTPClient.Request(head: head, body: Data())
            let future = client.connect(request, timeout: .seconds(5))
            future.whenSuccess { response in }
            future.whenFailure { error in }
            future.whenComplete { _ in }

            _ = try future.wait()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testConnectGet() {
        do {
            let head = HTTPRequestHead(
                         version: HTTPVersion(major: 1, minor: 1),
                         method: .GET,
                         uri: "https://kinesis.us-west-2.amazonaws.com/"
                       )
            let request = NIOTSHTTPClient.Request(head: head, body: Data())
            let future = client.connect(request, timeout: .seconds(5))
            future.whenSuccess { response in }
            future.whenFailure { error in }
            future.whenComplete { _ in }

            _ = try future.wait()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testConnectPost() {
        do {
            let head = HTTPRequestHead(
                         version: HTTPVersion(major: 1, minor: 1),
                         method: .GET,
                         uri: "https://kinesis.us-west-2.amazonaws.com/"
                       )
            let request = NIOTSHTTPClient.Request(head: head, body: Data())
            let future = client.connect(request, timeout: .seconds(5))
            future.whenSuccess { response in }
            future.whenFailure { error in }
            future.whenComplete { _ in }

            _ = try future.wait()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }


}

#endif //canImport(Network)
