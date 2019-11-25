//
//  DictionarySerializer.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/04/06.
//
//

import Foundation
import NIO
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
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    func testInitWithInvalidURL() {
      do {
          _ = try HTTPClient(url: URL(string: "no_protocol.com")!, eventGroup: eventLoopGroup)
          XCTFail("Should throw malformedURL error")
      } catch {
        if case HTTPClient.HTTPError.malformedURL = error {}
        else {
            XCTFail("Should throw malformedURL error")
        }
      }
    }

    func testInitWithValidRL() {
      do {
          _ = try HTTPClient(url: URL(string: "https://kinesis.us-west-2.amazonaws.com/")!, eventGroup: eventLoopGroup)
      } catch {
          XCTFail("Should not throw malformedURL error")
      }

      do {
          _ = try HTTPClient(url: URL(string: "http://169.254.169.254/latest/meta-data/iam/security-credentials/")!, eventGroup: eventLoopGroup)
      } catch {
          XCTFail("Should not throw malformedURL error")
      }
    }

    func testInitWithHostAndPort() {
        let url = URL(string: "https://kinesis.us-west-2.amazonaws.com/")!
        _ = HTTPClient(hostname: url.host!, port: 443, eventGroup: eventLoopGroup)
    }

    func testConnectSimpleGet() {
        let url = URL(string: "https://kinesis.us-west-2.amazonaws.com/")!
        let client = HTTPClient(hostname: url.host!, port: 443, eventGroup: eventLoopGroup)
        let head = HTTPRequestHead(
                     version: HTTPVersion(major: 1, minor: 1),
                     method: .GET,
                     uri: url.path
                   )
        let request = HTTPClient.Request(head: head, body: Data())
        let future = client.connect(request)
        future.whenSuccess { response in }
        future.whenFailure { error in }
        future.whenComplete { }

        do {
            _ = try HTTPClient(url: URL(string: "http://169.254.169.254/latest/meta-data/iam/security-credentials/")!, eventGroup: eventLoopGroup)
        } catch {
            XCTFail("Should not throw malformedURL error")
        }
    }

    func testConnectGet() {

        let url = URL(string: "https://kinesis.us-west-2.amazonaws.com/")!
        let client = HTTPClient(hostname: url.host!, port: 443, eventGroup: eventLoopGroup)
        let head = HTTPRequestHead(
                     version: HTTPVersion(major: 1, minor: 1),
                     method: .GET,
                     uri: url.path
                   )
        let request = HTTPClient.Request(head: head, body: Data())
        let future = client.connect(request)
        future.whenSuccess { response in }
        future.whenFailure { error in }
        future.whenComplete { }

        do {
            _ = try HTTPClient(url: URL(string: "http://169.254.169.254/latest/meta-data/iam/security-credentials/")!, eventGroup: eventLoopGroup)
        } catch {
            XCTFail("Should not throw malformedURL error")
        }
    }

    func testConnectPost() {
        let url = URL(string: "https://kinesis.us-west-2.amazonaws.com/")!
        let client = HTTPClient(hostname: url.host!, port: 443, eventGroup: eventLoopGroup)
        let head = HTTPRequestHead(
                     version: HTTPVersion(major: 1, minor: 1),
                     method: .GET,
                     uri: url.path
                   )
        let request = HTTPClient.Request(head: head, body: Data())
        let future = client.connect(request)
        future.whenSuccess { response in }
        future.whenFailure { error in }
        future.whenComplete { }

        do {
            _ = try HTTPClient(url: URL(string: "http://169.254.169.254/latest/meta-data/iam/security-credentials/")!, eventGroup: eventLoopGroup)
        } catch {
            XCTFail("Should not throw malformedURL error")
        }
    }


}
