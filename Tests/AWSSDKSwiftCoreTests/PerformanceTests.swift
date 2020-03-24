//
//  PerformanceTests.swift
//  AWSSDKSwiftCoreTests
//
//  Created by Adam Fowler on 2018/10/13.
//
//

import XCTest
import NIO
import NIOHTTP1
import AsyncHTTPClient
@testable import AWSSDKSwiftCore

struct HeaderRequest: AWSShape {
    static var _encoding: [AWSMemberEncoding] = [
        AWSMemberEncoding(label: "Header1", location: .header(locationName: "Header1")),
        AWSMemberEncoding(label: "Header2", location: .header(locationName: "Header2")),
        AWSMemberEncoding(label: "Header3", location: .header(locationName: "Header3")),
        AWSMemberEncoding(label: "Header4", location: .header(locationName: "Header4"))
    ]

    let header1: String
    let header2: String
    let header3: String
    let header4: TimeStamp
}

struct StandardRequest: AWSShape {
    let item1: String
    let item2: Int
    let item3: Double
    let item4: TimeStamp
    let item5: [Int]
}

struct PayloadRequest: AWSShape {
    public static let payloadPath: String? = "payload"

    let payload: StandardRequest
}

struct MixedRequest: AWSShape {
    static var _encoding: [AWSMemberEncoding] = [
        AWSMemberEncoding(label: "item1", location: .header(locationName: "item1")),
    ]

    let item1: String
    let item2: Int
    let item3: Double
    let item4: TimeStamp
}


class PerformanceTests: XCTestCase {
    @EnvironmentVariable("ENABLE_TIMING_TESTS", default: true) static var enableTimingTests: Bool
    
    func testHeaderRequest() {
        guard Self.enableTimingTests == true else { return }
        let client = AWSClient(
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .restxml),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        let date = Date()
        let request = HeaderRequest(header1: "Header1", header2: "Header2", header3: "Header3", header4: TimeStamp(date))
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try client.createAWSRequest(operation: "Test", path: "/", httpMethod: "POST", input: request)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }

    func testXMLRequest() {
        guard Self.enableTimingTests == true else { return }
        let client = AWSClient(
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .restxml),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        let date = Date()
        let request = StandardRequest(item1: "item1", item2: 45, item3: 3.14, item4: TimeStamp(date), item5: [1,2,3,4,5])
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try client.createAWSRequest(operation: "Test", path: "/", httpMethod: "POST", input: request)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }

    func testXMLPayloadRequest() {
        guard Self.enableTimingTests == true else { return }
        let client = AWSClient(
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .restxml),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        let date = Date()
        let request = PayloadRequest(payload: StandardRequest(item1: "item1", item2: 45, item3: 3.14, item4: TimeStamp(date), item5: [1,2,3,4,5]))
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try client.createAWSRequest(operation: "Test", path: "/", httpMethod: "POST", input: request)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }

    func testJSONRequest() {
        guard Self.enableTimingTests == true else { return }
        let client = AWSClient(
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .restjson),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        let date = Date()
        let request = StandardRequest(item1: "item1", item2: 45, item3: 3.14, item4: TimeStamp(date), item5: [1,2,3,4,5])
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try client.createAWSRequest(operation: "Test", path: "/", httpMethod: "POST", input: request)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }

    func testJSONPayloadRequest() {
        guard Self.enableTimingTests == true else { return }
        let client = AWSClient(
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .restjson),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        let date = Date()
        let request = PayloadRequest(payload: StandardRequest(item1: "item1", item2: 45, item3: 3.14, item4: TimeStamp(date), item5: [1,2,3,4,5]))
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try client.createAWSRequest(operation: "Test", path: "/", httpMethod: "POST", input: request)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }

    func testQueryRequest() {
        guard Self.enableTimingTests == true else { return }
        let client = AWSClient(
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .query),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        let date = Date()
        let request = StandardRequest(item1: "item1", item2: 45, item3: 3.14, item4: TimeStamp(date), item5: [1,2,3,4,5])
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try client.createAWSRequest(operation: "Test", path: "/", httpMethod: "POST", input: request)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }

    func testUnsignedRequest() {
        guard Self.enableTimingTests == true else { return }
        let client = AWSClient(
            accessKeyId: "",
            secretAccessKey: "",
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .json),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        let awsRequest = try! client.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET")
        let signer = try! client.signer.wait()
        measure {
            for _ in 0..<1000 {
                _ = awsRequest.createHTTPRequest(signer: signer)
            }
        }
    }

    func testSignedURLRequest() {
        guard Self.enableTimingTests == true else { return }
        let client = AWSClient(
            accessKeyId: "MyAccessKeyId",
            secretAccessKey: "MySecretAccessKey",
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .json),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        let awsRequest = try! client.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET")
        let signer = try! client.signer.wait()
        measure {
            for _ in 0..<1000 {
                _ = awsRequest.createHTTPRequest(signer: signer)
            }
        }
    }

    func testSignedHeadersRequest() {
        guard Self.enableTimingTests == true else { return }
        let client = AWSClient(
            accessKeyId: "MyAccessKeyId",
            secretAccessKey: "MySecretAccessKey",
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .json),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        let date = Date()
        let request = StandardRequest(item1: "item1", item2: 45, item3: 3.14, item4: TimeStamp(date), item5: [1,2,3,4,5])
        let awsRequest = try! client.createAWSRequest(operation: "Test", path: "/", httpMethod: "POST", input: request)
        let signer = try! client.signer.wait()
        measure {
            for _ in 0..<1000 {
                _ = awsRequest.createHTTPRequest(signer: signer)
            }
        }
    }

    func testValidateXMLResponse() {
        guard Self.enableTimingTests == true else { return }
        let client = AWSClient(
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .restxml),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString("<Output><item1>Hello</item1><item2>5</item2><item3>3.141</item3><item4>2001-12-23T15:34:12.590Z</item4><item5>3</item5><item5>6</item5><item5>325</item5></Output>")
        let response = HTTPClient.Response(
            host: "localhost",
            status: .ok,
            headers: HTTPHeaders(),
            body: buffer
        )
        measure {
            do {
                for _ in 0..<1000 {
                    let _: StandardRequest = try client.validate(operation: "Output", response: response)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }

    func testValidateJSONResponse() {
        guard Self.enableTimingTests == true else { return }
        let client = AWSClient(
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .restjson),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString("{\"item1\":\"Hello\", \"item2\":5, \"item3\":3.14, \"item4\":\"2001-12-23T15:34:12.590Z\", \"item5\": [1,56,3,7]}")
        let response = HTTPClient.Response(
            host: "localhost",
            status: .ok,
            headers: HTTPHeaders(),
            body: buffer
        )
        measure {
            do {
                for _ in 0..<1000 {
                    let _: StandardRequest = try client.validate(operation: "Output", response: response)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }

    static var allTests : [(String, (PerformanceTests) -> () throws -> Void)] {
        return [
            ("testHeaderRequest", testHeaderRequest),
            ("testXMLRequest", testXMLRequest),
            ("testXMLPayloadRequest", testXMLPayloadRequest),
            ("testJSONRequest", testJSONRequest),
            ("testJSONPayloadRequest", testJSONPayloadRequest),
            ("testQueryRequest", testQueryRequest),
            ("testUnsignedRequest", testUnsignedRequest),
            ("testSignedURLRequest", testSignedURLRequest),
            ("testSignedHeadersRequest", testSignedHeadersRequest),
            ("testValidateXMLResponse", testValidateXMLResponse),
            ("testValidateJSONResponse", testValidateJSONResponse),
        ]
    }
}
