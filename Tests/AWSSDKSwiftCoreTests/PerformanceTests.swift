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

import AsyncHTTPClient
@testable import AWSSDKSwiftCore
import AWSSignerV4
import AWSTestUtils
import NIO
import NIOHTTP1
import XCTest

struct HeaderRequest: AWSEncodableShape {
    static var _encoding: [AWSMemberEncoding] = [
        AWSMemberEncoding(label: "Header1", location: .header(locationName: "Header1")),
        AWSMemberEncoding(label: "Header2", location: .header(locationName: "Header2")),
        AWSMemberEncoding(label: "Header3", location: .header(locationName: "Header3")),
        AWSMemberEncoding(label: "Header4", location: .header(locationName: "Header4")),
    ]

    let header1: String
    let header2: String
    let header3: String
    let header4: TimeStamp
}

struct StandardRequest: AWSEncodableShape {
    let item1: String
    let item2: Int
    let item3: Double
    let item4: TimeStamp
    let item5: [Int]
}

struct PayloadRequest: AWSEncodableShape & AWSShapeWithPayload {
    public static let _payloadPath: String = "payload"

    let payload: StandardRequest
}

struct MixedRequest: AWSEncodableShape {
    static var _encoding: [AWSMemberEncoding] = [
        AWSMemberEncoding(label: "item1", location: .header(locationName: "item1")),
    ]

    let item1: String
    let item2: Int
    let item3: Double
    let item4: TimeStamp
}

struct StandardResponse: AWSDecodableShape {
    let item1: String
    let item2: Int
    let item3: Double
    let item4: TimeStamp
    let item5: [Int]
}

class PerformanceTests: XCTestCase {
    @EnvironmentVariable("ENABLE_TIMING_TESTS", default: true) static var enableTimingTests: Bool

    func testHeaderRequest() {
        guard Self.enableTimingTests == true else { return }
        let config = createServiceConfig(
            region: .useast1,
            service: "Test",
            serviceProtocol: .restxml,
            apiVersion: "1.0"
        )
        let date = Date()
        let request = HeaderRequest(header1: "Header1", header2: "Header2", header3: "Header3", header4: TimeStamp(date))
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try AWSRequest(operation: "Test", path: "/", httpMethod: .POST, input: request, configuration: config)
                }
            } catch {
                XCTFail("Unexpected Error: \(error.localizedDescription)")
            }
        }
    }

    func testXMLRequest() {
        guard Self.enableTimingTests == true else { return }
        let config = createServiceConfig(
            region: .useast1,
            service: "Test",
            serviceProtocol: .restxml,
            apiVersion: "1.0"
        )
        let date = Date()
        let request = StandardRequest(item1: "item1", item2: 45, item3: 3.14, item4: TimeStamp(date), item5: [1, 2, 3, 4, 5])
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try AWSRequest(operation: "Test", path: "/", httpMethod: .POST, input: request, configuration: config)
                }
            } catch {
                XCTFail("Unexpected Error: \(error.localizedDescription)")
            }
        }
    }

    func testXMLPayloadRequest() {
        guard Self.enableTimingTests == true else { return }
        let config = createServiceConfig(
            region: .useast1,
            service: "Test",
            serviceProtocol: .restxml,
            apiVersion: "1.0"
        )
        let date = Date()
        let request = PayloadRequest(payload: StandardRequest(item1: "item1", item2: 45, item3: 3.14, item4: TimeStamp(date), item5: [1, 2, 3, 4, 5]))
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try AWSRequest(operation: "Test", path: "/", httpMethod: .POST, input: request, configuration: config)
                }
            } catch {
                XCTFail("\(error)")
            }
        }
    }

    func testJSONRequest() {
        guard Self.enableTimingTests == true else { return }
        let config = createServiceConfig(
            region: .useast1,
            service: "Test",
            serviceProtocol: .restjson,
            apiVersion: "1.0"
        )
        let date = Date()
        let request = StandardRequest(item1: "item1", item2: 45, item3: 3.14, item4: TimeStamp(date), item5: [1, 2, 3, 4, 5])
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try AWSRequest(operation: "Test", path: "/", httpMethod: .POST, input: request, configuration: config)
                }
            } catch {
                XCTFail("\(error)")
            }
        }
    }

    func testJSONPayloadRequest() {
        guard Self.enableTimingTests == true else { return }
        let config = createServiceConfig(
            region: .useast1,
            service: "Test",
            serviceProtocol: .restjson,
            apiVersion: "1.0"
        )
        let date = Date()
        let request = PayloadRequest(payload: StandardRequest(item1: "item1", item2: 45, item3: 3.14, item4: TimeStamp(date), item5: [1, 2, 3, 4, 5]))
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try AWSRequest(operation: "Test", path: "/", httpMethod: .POST, input: request, configuration: config)
                }
            } catch {
                XCTFail("\(error)")
            }
        }
    }

    func testQueryRequest() {
        guard Self.enableTimingTests == true else { return }
        let config = createServiceConfig(
            region: .useast1,
            service: "Test",
            serviceProtocol: .query,
            apiVersion: "1.0"
        )
        let date = Date()
        let request = StandardRequest(item1: "item1", item2: 45, item3: 3.14, item4: TimeStamp(date), item5: [1, 2, 3, 4, 5])
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try AWSRequest(operation: "Test", path: "/", httpMethod: .POST, input: request, configuration: config)
                }
            } catch {
                XCTFail("\(error)")
            }
        }
    }

    func testUnsignedRequest() {
        guard Self.enableTimingTests == true else { return }
        let config = createServiceConfig(
            region: .useast1,
            service: "Test",
            serviceProtocol: .json(version: "1.1"),
            apiVersion: "1.0"
        )

        let request = try! AWSRequest(
            operation: "Test",
            path: "/",
            httpMethod: .GET,
            configuration: config
        )

        let signer = AWSSigner(
            credentials: StaticCredential(accessKeyId: "", secretAccessKey: ""),
            name: config.service,
            region: config.region.rawValue
        )
        measure {
            for _ in 0..<1000 {
                _ = request.createHTTPRequest(signer: signer)
            }
        }
    }

    func testSignedURLRequest() {
        guard Self.enableTimingTests == true else { return }
        let config = createServiceConfig()
        let client = createAWSClient(credentialProvider: .static(accessKeyId: "MyAccessKeyId", secretAccessKey: "MySecretAccessKey"))
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
        }
        let awsRequest = try! AWSRequest(
            operation: "Test",
            path: "/",
            httpMethod: .GET,
            configuration: config
        ).applyMiddlewares(config.middlewares + client.middlewares)

        let signer = try! client.createSigner(config: config, logger: AWSClient.loggingDisabled).wait()
        measure {
            for _ in 0..<1000 {
                _ = awsRequest.createHTTPRequest(signer: signer)
            }
        }
    }

    func testSignedHeadersRequest() {
        guard Self.enableTimingTests == true else { return }
        let config = createServiceConfig(
            region: .useast1,
            service: "Test",
            serviceProtocol: .json(version: "1.1"),
            apiVersion: "1.0"
        )
        let date = Date()
        let request = StandardRequest(item1: "item1", item2: 45, item3: 3.14, item4: TimeStamp(date), item5: [1, 2, 3, 4, 5])
        let awsRequest = try! AWSRequest(operation: "Test", path: "/", httpMethod: .POST, input: request, configuration: config)
        let signer = AWSSigner(
            credentials: StaticCredential(accessKeyId: "", secretAccessKey: ""),
            name: config.service,
            region: config.region.rawValue
        )
        measure {
            for _ in 0..<1000 {
                _ = awsRequest.createHTTPRequest(signer: signer)
            }
        }
    }

    func testValidateXMLResponse() {
        guard Self.enableTimingTests == true else { return }
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString("<Output><item1>Hello</item1><item2>5</item2><item3>3.141</item3><item4>2001-12-23T15:34:12.590Z</item4><item5>3</item5><item5>6</item5><item5>325</item5></Output>")
        let response = HTTPClient.Response(
            host: "localhost",
            status: .ok,
            version: .init(major: 1, minor: 1),
            headers: HTTPHeaders(),
            body: buffer
        )

        measure {
            do {
                for _ in 0..<1000 {
                    let awsResponse = try AWSResponse(from: response, serviceProtocol: .restxml, raw: false)
                    let _: StandardResponse = try awsResponse.generateOutputShape(operation: "Test")
                }
            } catch {
                XCTFail("\(error)")
            }
        }
    }

    func testValidateJSONResponse() {
        guard Self.enableTimingTests == true else { return }
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString("{\"item1\":\"Hello\", \"item2\":5, \"item3\":3.14, \"item4\":\"2001-12-23T15:34:12.590Z\", \"item5\": [1,56,3,7]}")
        let response = HTTPClient.Response(
            host: "localhost",
            status: .ok,
            version: .init(major: 1, minor: 1),
            headers: HTTPHeaders(),
            body: buffer
        )
        measure {
            do {
                for _ in 0..<1000 {
                    let awsResponse = try AWSResponse(from: response, serviceProtocol: .restjson, raw: false)
                    let _: StandardResponse = try awsResponse.generateOutputShape(operation: "Test")
                }
            } catch {
                XCTFail("\(error)")
            }
        }
    }
}
