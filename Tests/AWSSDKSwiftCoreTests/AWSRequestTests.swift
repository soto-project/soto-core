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

@testable import AWSSDKSwiftCore
import AWSSignerV4
import AWSTestUtils
import NIOHTTP1
import XCTest

class AWSRequestTests: XCTestCase {
    struct E: AWSEncodableShape & Decodable {
        let Member = ["memberKey": "memberValue", "memberKey2": "memberValue2"]

        private enum CodingKeys: String, CodingKey {
            case Member
        }
    }

    func testPartitionEndpoints() {
        let context = createServiceContext(
            serviceEndpoints: ["aws-global": "service.aws.amazon.com"],
            partitionEndpoints: [.aws: (endpoint: "aws-global", region: .euwest1)]
        )

        XCTAssertEqual(context.region, .euwest1)

        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "test", path: "/", httpMethod: .GET, configuration: context))
        XCTAssertEqual(request?.url.absoluteString, "https://service.aws.amazon.com/")
    }

    func testCreateAwsRequestWithKeywordInHeader() {
        struct KeywordRequest: AWSEncodableShape {
            static var _encoding: [AWSMemberEncoding] = [
                AWSMemberEncoding(label: "repeat", location: .header(locationName: "repeat")),
            ]
            let `repeat`: String
        }
        let context = createServiceContext()
        let request = KeywordRequest(repeat: "Repeat")
        var awsRequest: AWSRequest?
        XCTAssertNoThrow(awsRequest = try AWSRequest(operation: "Keyword", path: "/", httpMethod: .POST, input: request, configuration: context))
        XCTAssertEqual(awsRequest?.httpHeaders["repeat"].first, "Repeat")
        XCTAssertTrue(try XCTUnwrap(awsRequest).body.asPayload().isEmpty)
    }

    func testCreateAwsRequestWithKeywordInQuery() {
        struct KeywordRequest: AWSEncodableShape {
            static var _encoding: [AWSMemberEncoding] = [
                AWSMemberEncoding(label: "self", location: .querystring(locationName: "self")),
            ]
            let `self`: String
        }
        let context = createServiceContext(region: .cacentral1, service: "s3")

        let request = KeywordRequest(self: "KeywordRequest")
        var awsRequest: AWSRequest?
        XCTAssertNoThrow(awsRequest = try AWSRequest(operation: "Keyword", path: "/", httpMethod: .POST, input: request, configuration: context))
        XCTAssertEqual(awsRequest?.url, URL(string: "https://s3.ca-central-1.amazonaws.com/?self=KeywordRequest")!)
        XCTAssertEqual(try XCTUnwrap(awsRequest).body.asByteBuffer(), nil)
    }

    func testCreateNIORequest() {
        let input2 = E()

        let context = createServiceContext(region: .useast1, service: "kinesis", serviceProtocol: .json(version: "1.1"))

        var awsRequest: AWSRequest?
        XCTAssertNoThrow(awsRequest = try AWSRequest(
            operation: "PutRecord",
            path: "/",
            httpMethod: .POST,
            input: input2,
            configuration: context
        )
        )

        let signer = AWSSigner(
            credentials: StaticCredential(accessKeyId: "foo", secretAccessKey: "bar"),
            name: context.service,
            region: context.region.rawValue
        )

        let signedRequest = awsRequest?.createHTTPRequest(signer: signer)
        XCTAssertNotNil(signedRequest)
        XCTAssertEqual(signedRequest?.method, HTTPMethod.POST)
        XCTAssertEqual(signedRequest?.headers["Host"].first, "kinesis.us-east-1.amazonaws.com")
        XCTAssertEqual(signedRequest?.headers["Content-Type"].first, "application/x-amz-json-1.1")
    }

    func testUnsignedClient() {
        let input = E()
        let context = createServiceContext()

        var awsRequest: AWSRequest?
        XCTAssertNoThrow(awsRequest = try AWSRequest(
            operation: "CopyObject",
            path: "/",
            httpMethod: .PUT,
            input: input,
            configuration: context
        ))

        let signer = AWSSigner(
            credentials: StaticCredential(accessKeyId: "", secretAccessKey: ""),
            name: context.service,
            region: context.region.rawValue
        )

        let request = awsRequest?.createHTTPRequest(signer: signer)
        XCTAssertNil(request?.headers["Authorization"].first)
    }

    func testSignedClient() {
        let input = E()
        let context = createServiceContext()

        let signer = AWSSigner(
            credentials: StaticCredential(accessKeyId: "foo", secretAccessKey: "bar"),
            name: context.service,
            region: context.region.rawValue
        )

        for httpMethod in [HTTPMethod.GET, .HEAD, .PUT, .DELETE, .POST, .PATCH] {
            var awsRequest: AWSRequest?

            XCTAssertNoThrow(awsRequest = try AWSRequest(
                operation: "Test",
                path: "/",
                httpMethod: httpMethod,
                input: input,
                configuration: context
            ))

            let request = awsRequest?.createHTTPRequest(signer: signer)
            XCTAssertNotNil(request?.headers["Authorization"].first)
        }
    }

    func testProtocolContentType() throws {
        struct Object: AWSEncodableShape {
            let string: String
        }
        struct Object2: AWSEncodableShape & AWSShapeWithPayload {
            static var _payloadPath = "payload"
            let payload: AWSPayload
            private enum CodingKeys: CodingKey {}
        }
        let object = Object(string: "Name")
        let object2 = Object2(payload: .string("Payload"))

        let context = createServiceContext(serviceProtocol: .json(version: "1.1"))
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "test", path: "/", httpMethod: .POST, input: object, configuration: context))
        XCTAssertEqual(request?.httpHeaders["content-type"].first, "application/x-amz-json-1.1")

        let config2 = createServiceContext(serviceProtocol: .restjson)
        var request2: AWSRequest?
        XCTAssertNoThrow(request2 = try AWSRequest(operation: "test", path: "/", httpMethod: .POST, input: object, configuration: config2))
        XCTAssertEqual(request2?.httpHeaders["content-type"].first, "application/json")
        var rawRequest2: AWSRequest?
        XCTAssertNoThrow(rawRequest2 = try AWSRequest(operation: "test", path: "/", httpMethod: .POST, input: object2, configuration: config2))
        XCTAssertEqual(rawRequest2?.httpHeaders["content-type"].first, "binary/octet-stream")

        let config3 = createServiceContext(serviceProtocol: .query)
        var request3: AWSRequest?
        XCTAssertNoThrow(request3 = try AWSRequest(operation: "test", path: "/", httpMethod: .POST, input: object, configuration: config3))
        XCTAssertEqual(request3?.httpHeaders["content-type"].first, "application/x-www-form-urlencoded; charset=utf-8")

        let config4 = createServiceContext(serviceProtocol: .ec2)
        var request4: AWSRequest?
        XCTAssertNoThrow(request4 = try AWSRequest(operation: "test", path: "/", httpMethod: .POST, input: object, configuration: config4))
        XCTAssertEqual(request4?.httpHeaders["content-type"].first, "application/x-www-form-urlencoded; charset=utf-8")

        let config5 = createServiceContext(serviceProtocol: .restxml)
        var request5: AWSRequest?
        XCTAssertNoThrow(request5 = try AWSRequest(operation: "test", path: "/", httpMethod: .POST, input: object, configuration: config5))
        XCTAssertEqual(request5?.httpHeaders["content-type"].first, "application/octet-stream")
    }

    func testHeaderEncoding() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "h", location: .header(locationName: "header-member"))]
            let h: String
        }
        let input = Input(h: "TestHeader")
        let context = createServiceContext()
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: .GET, input: input, configuration: context))
        XCTAssertEqual(request?.httpHeaders["header-member"].first, "TestHeader")
    }

    func testQueryEncoding() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "q", location: .querystring(locationName: "query"))]
            let q: String
        }
        let input = Input(q: "=3+5897^sdfjh&")
        let context = createServiceContext(region: .useast1)
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: .GET, input: input, configuration: context))
        XCTAssertEqual(request?.url.absoluteString, "https://test.us-east-1.amazonaws.com/?query=%3D3%2B5897%5Esdfjh%26")
    }

    func testQueryEncodedArray() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "q", location: .querystring(locationName: "query"))]
            let q: [String]
        }
        let input = Input(q: ["=3+5897^sdfjh&", "test"])
        let context = createServiceContext(region: .useast1)

        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: .GET, input: input, configuration: context))
        XCTAssertEqual(request?.url.absoluteString, "https://test.us-east-1.amazonaws.com/?query=%3D3%2B5897%5Esdfjh%26&query=test")
    }

    func testQueryEncodedDictionary() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "q", location: .querystring(locationName: "query"))]
            let q: [String: Int]
        }
        let input = Input(q: ["one": 1, "two": 2])
        let context = createServiceContext(region: .useast2, service: "myservice")
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: .GET, input: input, configuration: context))
        XCTAssertEqual(request?.url.absoluteString, "https://myservice.us-east-2.amazonaws.com/?one=1&two=2")
    }

    func testURIEncoding() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "u", location: .uri(locationName: "key"))]
            let u: String
        }
        let input = Input(u: "MyKey")
        let context = createServiceContext(region: .cacentral1, service: "s3")
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/{key}", httpMethod: .GET, input: input, configuration: context))
        XCTAssertEqual(request?.url.absoluteString, "https://s3.ca-central-1.amazonaws.com/MyKey")
    }

    func testCreateWithXMLNamespace() {
        struct Input: AWSEncodableShape {
            public static let _xmlNamespace: String? = "https://test.amazonaws.com/doc/2020-03-11/"
            let number: Int
        }
        let input = Input(number: 5)
        let xmlConfig = createServiceContext(serviceProtocol: .restxml)
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: .GET, input: input, configuration: xmlConfig))
        guard case .xml(let element) = request?.body else {
            return XCTFail("Shouldn't get here")
        }
        XCTAssertEqual(element.xmlString, "<Input xmlns=\"https://test.amazonaws.com/doc/2020-03-11/\"><number>5</number></Input>")
    }

    func testCreateWithPayloadAndXMLNamespace() {
        struct Payload: AWSEncodableShape {
            public static let _xmlNamespace: String? = "https://test.amazonaws.com/doc/2020-03-11/"
            let number: Int
        }
        struct Input: AWSEncodableShape & AWSShapeWithPayload {
            public static let _payloadPath: String = "payload"
            let payload: Payload
        }
        let input = Input(payload: Payload(number: 5))
        let xmlConfig = createServiceContext(serviceProtocol: .restxml)
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: .GET, input: input, configuration: xmlConfig))
        guard case .xml(let element) = request?.body else {
            return XCTFail("Shouldn't get here")
        }
        XCTAssertEqual(element.xmlString, "<Payload xmlns=\"https://test.amazonaws.com/doc/2020-03-11/\"><number>5</number></Payload>")
    }

    func testDataInJsonPayload() {
        struct DataContainer: AWSEncodableShape {
            let data: Data
        }
        struct J: AWSEncodableShape & AWSShapeWithPayload {
            public static let _payloadPath: String = "dataContainer"
            let dataContainer: DataContainer
        }
        let input = J(dataContainer: DataContainer(data: Data("test data".utf8)))
        let jsonConfig = createServiceContext(serviceProtocol: .json(version: "1.1"))
        XCTAssertNoThrow(try AWSRequest(operation: "PutRecord", path: "/", httpMethod: .POST, input: input, configuration: jsonConfig))
    }

    func testEC2ClientRequest() {
        struct Input: AWSEncodableShape {
            let array: [String]
        }
        let input = Input(array: ["entry1", "entry2"])
        let context = createServiceContext(serviceProtocol: .ec2, apiVersion: "2013-12-02")
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: .GET, input: input, configuration: context))
        XCTAssertEqual(request?.body.asString(), "Action=Test&Array.1=entry1&Array.2=entry2&Version=2013-12-02")
    }
}
