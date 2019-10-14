//
//  DictionarySerializer.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/04/06.
//
//

import Foundation
import NIOHTTP1
import XCTest
@testable import AWSSDKSwiftCore

class HTTPClientTests: XCTestCase {

      static var allTests : [(String, (HTTPClientTests) -> () throws -> Void)] {
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
        let client = HTTPClient()
        let head = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: "no_protocol.com")
        let request = HTTPClient.Request(head: head, body: Data())
        _ = try client.connect(request).wait()
        XCTFail("Should throw malformedURL error")
      } catch {
        if case HTTPClient.HTTPError.malformedURL = error {}
        else {
            XCTFail("Should throw malformedURL error")
        }
      }
    }

    func testInitWithValidRL() {
        let client = HTTPClient()
        do {
            let head = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: "https://kinesis.us-west-2.amazonaws.com/")
            let request = HTTPClient.Request(head: head, body: Data())
            _ = try client.connect(request).wait()
        } catch {
            XCTFail("Should not throw malformedURL error")
        }

        do {
            let head = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: "http://169.254.169.254/latest/meta-data/iam/security-credentials/")
            let request = HTTPClient.Request(head: head, body: Data())
            _ = try client.connect(request).wait()
        } catch HTTPClient.HTTPError.malformedURL{
            XCTFail("Should not throw malformedURL error")
        } catch {
        }
    }

    func testConnectSimpleGet() {
        let client = HTTPClient()
        let head = HTTPRequestHead(
                     version: HTTPVersion(major: 1, minor: 1),
                     method: .GET,
                     uri: "https://kinesis.us-west-2.amazonaws.com/"
                   )
        let request = HTTPClient.Request(head: head, body: Data())
        let future = client.connect(request)
        future.whenSuccess { response in }
        future.whenFailure { error in }
        future.whenComplete { _ in }

        do {
            _ = try future.wait()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testConnectGet() {
        let client = HTTPClient()
        let head = HTTPRequestHead(
                     version: HTTPVersion(major: 1, minor: 1),
                     method: .GET,
                     uri: "https://kinesis.us-west-2.amazonaws.com/"
                   )
        let request = HTTPClient.Request(head: head, body: Data())
        let future = client.connect(request)
        future.whenSuccess { response in }
        future.whenFailure { error in }
        future.whenComplete { _ in }

        do {
            _ = try future.wait()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testConnectPost() {
        let client = HTTPClient()
        let head = HTTPRequestHead(
                     version: HTTPVersion(major: 1, minor: 1),
                     method: .GET,
                     uri: "https://kinesis.us-west-2.amazonaws.com/"
                   )
        let request = HTTPClient.Request(head: head, body: Data())
        let future = client.connect(request)
        future.whenSuccess { response in }
        future.whenFailure { error in }
        future.whenComplete { _ in }

        do {
            _ = try future.wait()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }


}
