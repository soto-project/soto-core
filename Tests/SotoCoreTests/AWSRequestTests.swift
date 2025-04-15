//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import NIOHTTP1
import SotoSignerV4
import SotoTestUtils
import SotoXML
import XCTest

import struct Foundation.Data

@testable @_spi(SotoInternal) import SotoCore

extension AWSHTTPBody {
    func asString() -> String? {
        switch self.storage {
        case .byteBuffer(let buffer):
            return String(buffer: buffer)
        case .asyncSequence:
            return nil
        }
    }
}

class AWSRequestTests: XCTestCase {
    struct E: AWSEncodableShape & Decodable {
        let Member = ["memberKey": "memberValue", "memberKey2": "memberValue2"]

        private enum CodingKeys: String, CodingKey {
            case Member
        }
    }

    func testPartitionEndpoints() {
        let config = createServiceConfig(
            serviceEndpoints: ["aws-global": "service.aws.amazon.com"],
            partitionEndpoints: [.aws: (endpoint: "aws-global", region: .euwest1)]
        )

        XCTAssertEqual(config.region, .euwest1)

        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "test", path: "/", method: .GET, configuration: config))
        XCTAssertEqual(request?.url.absoluteString, "https://service.aws.amazon.com/")
    }

    func testCreateAwsRequestWithKeywordInHeader() {
        struct KeywordRequest: AWSEncodableShape {
            let `repeat`: String

            func encode(to encoder: Encoder) throws {
                _ = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodeHeader(self.repeat, key: "repeat")
            }

            private enum CodingKeys: CodingKey {}
        }
        let config = createServiceConfig()
        let request = KeywordRequest(repeat: "Repeat")
        var awsRequest: AWSHTTPRequest?
        XCTAssertNoThrow(awsRequest = try AWSHTTPRequest(operation: "Keyword", path: "/", method: .POST, input: request, configuration: config))
        XCTAssertEqual(awsRequest?.headers["repeat"].first, "Repeat")
    }

    func testCreateAwsRequestWithKeywordInQuery() {
        struct KeywordRequest: AWSEncodableShape {
            let `throw`: String

            func encode(to encoder: Encoder) throws {
                _ = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodeQuery(self.throw, key: "throw")
            }

            private enum CodingKeys: CodingKey {}
        }
        let config = createServiceConfig(region: .cacentral1, service: "s3")

        let request = KeywordRequest(throw: "KeywordRequest")
        var awsRequest: AWSHTTPRequest?
        XCTAssertNoThrow(awsRequest = try AWSHTTPRequest(operation: "Keyword", path: "/", method: .POST, input: request, configuration: config))
        XCTAssertEqual(awsRequest?.url, URL(string: "https://s3.ca-central-1.amazonaws.com/?throw=KeywordRequest")!)
    }

    func testCreateNIORequest() {
        let input2 = E()

        let config = createServiceConfig(region: .useast1, service: "kinesis", serviceProtocol: .json(version: "1.1"))

        var awsRequest: AWSHTTPRequest?
        XCTAssertNoThrow(
            awsRequest = try AWSHTTPRequest(
                operation: "PutRecord",
                path: "/",
                method: .POST,
                input: input2,
                configuration: config
            )
        )

        let signer = AWSSigner(
            credentials: StaticCredential(accessKeyId: "foo", secretAccessKey: "bar"),
            name: config.signingName,
            region: config.region.rawValue
        )

        awsRequest?.signHeaders(signer: signer, serviceConfig: config)
        XCTAssertNotNil(awsRequest)
        XCTAssertEqual(awsRequest?.method, HTTPMethod.POST)
        XCTAssertEqual(awsRequest?.headers["Host"].first, "kinesis.us-east-1.amazonaws.com")
        XCTAssertEqual(awsRequest?.headers["Content-Type"].first, "application/x-amz-json-1.1")
    }

    func testUnsignedClient() {
        let input = E()
        let config = createServiceConfig()

        var awsRequest: AWSHTTPRequest?
        XCTAssertNoThrow(
            awsRequest = try AWSHTTPRequest(
                operation: "CopyObject",
                path: "/",
                method: .PUT,
                input: input,
                configuration: config
            )
        )

        let signer = AWSSigner(
            credentials: StaticCredential(accessKeyId: "", secretAccessKey: ""),
            name: config.signingName,
            region: config.region.rawValue
        )

        awsRequest?.signHeaders(signer: signer, serviceConfig: config)
        XCTAssertNil(awsRequest?.headers["Authorization"].first)
    }

    func testSignedClient() {
        let input = E()
        let config = createServiceConfig()

        let signer = AWSSigner(
            credentials: StaticCredential(accessKeyId: "foo", secretAccessKey: "bar"),
            name: config.signingName,
            region: config.region.rawValue
        )

        for httpMethod in [HTTPMethod.GET, .HEAD, .PUT, .DELETE, .POST, .PATCH] {
            var awsRequest: AWSHTTPRequest?

            XCTAssertNoThrow(
                awsRequest = try AWSHTTPRequest(
                    operation: "Test",
                    path: "/",
                    method: httpMethod,
                    input: input,
                    configuration: config
                )
            )

            awsRequest?.signHeaders(signer: signer, serviceConfig: config)
            XCTAssertNotNil(awsRequest?.headers["Authorization"].first)
        }
    }

    func testProtocolContentType() throws {
        struct Object: AWSEncodableShape {
            let string: String
        }
        struct Object2: AWSEncodableShape {
            var _payload: any AWSEncodableShape { self.payload }
            let payload: AWSHTTPBody

            func encode(to encoder: Encoder) throws {
                try self.payload.encode(to: encoder)
            }
        }
        let object = Object(string: "Name")
        let object2 = Object2(payload: .init(string: "Payload"))

        let config = createServiceConfig(serviceProtocol: .json(version: "1.1"))
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "test", path: "/", method: .POST, input: object, configuration: config))
        XCTAssertEqual(request?.headers["content-type"].first, "application/x-amz-json-1.1")

        let config2 = createServiceConfig(serviceProtocol: .restjson)
        var request2: AWSHTTPRequest?
        XCTAssertNoThrow(request2 = try AWSHTTPRequest(operation: "test", path: "/", method: .POST, input: object, configuration: config2))
        XCTAssertEqual(request2?.headers["content-type"].first, "application/json")
        var rawRequest2: AWSHTTPRequest?
        XCTAssertNoThrow(rawRequest2 = try AWSHTTPRequest(operation: "test", path: "/", method: .POST, input: object2, configuration: config2))
        XCTAssertEqual(rawRequest2?.headers["content-type"].first, "binary/octet-stream")

        let config3 = createServiceConfig(serviceProtocol: .query)
        var request3: AWSHTTPRequest?
        XCTAssertNoThrow(request3 = try AWSHTTPRequest(operation: "test", path: "/", method: .POST, input: object, configuration: config3))
        XCTAssertEqual(request3?.headers["content-type"].first, "application/x-www-form-urlencoded; charset=utf-8")

        let config4 = createServiceConfig(serviceProtocol: .ec2)
        var request4: AWSHTTPRequest?
        XCTAssertNoThrow(request4 = try AWSHTTPRequest(operation: "test", path: "/", method: .POST, input: object, configuration: config4))
        XCTAssertEqual(request4?.headers["content-type"].first, "application/x-www-form-urlencoded; charset=utf-8")

        let config5 = createServiceConfig(serviceProtocol: .restxml)
        var request5: AWSHTTPRequest?
        XCTAssertNoThrow(request5 = try AWSHTTPRequest(operation: "test", path: "/", method: .POST, input: object, configuration: config5))
        XCTAssertEqual(request5?.headers["content-type"].first, "application/octet-stream")
    }

    func testHeaderEncoding() {
        struct Input: AWSEncodableShape {
            let h: String
            func encode(to encoder: Encoder) throws {
                _ = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodeHeader(self.h, key: "header-member")
            }

            private enum CodingKeys: CodingKey {}
        }
        let input = Input(h: "TestHeader")
        let config = createServiceConfig()
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.headers["header-member"].first, "TestHeader")
    }

    func testHeaderDateEncoding() {
        struct Input: AWSEncodableShape {
            let httpDate: Date
            @OptionalCustomCoding<ISO8601DateCoder>
            var iso8601Date: Date?

            func encode(to encoder: Encoder) throws {
                _ = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodeHeader(self.httpDate, key: "date")
                requestContainer.encodeHeader(self._iso8601Date, key: "iso8601-date")
            }

            private enum CodingKeys: CodingKey {}
        }
        let input = Input(
            httpDate: Date(timeIntervalSince1970: 1_000_000),
            iso8601Date: Date(timeIntervalSince1970: 1_000_000)
        )
        let config = createServiceConfig()
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.headers["date"].first, "Mon, 12 Jan 1970 13:46:40 GMT")
        XCTAssertEqual(request?.headers["iso8601-date"].first, "1970-01-12T13:46:40.000Z")
    }

    func testQueryEncoding() {
        struct Input: AWSEncodableShape {
            let p: String?
            let q: String
            let r: String?
            func encode(to encoder: Encoder) throws {
                _ = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodeQuery(self.p, key: "puery")
                requestContainer.encodeQuery(self.q, key: "query")
                requestContainer.encodeQuery(self.r, key: "ruery")
            }

            private enum CodingKeys: CodingKey {}
        }
        let input = Input(p: "hmmm", q: "=3+5897^sdfjh&", r: nil)
        let config = createServiceConfig(region: .useast1)
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.url.absoluteString, "https://test.us-east-1.amazonaws.com/?puery=hmmm&query=%3D3%2B5897%5Esdfjh%26")
    }

    func testQueryEncodedArray() {
        struct Input: AWSEncodableShape {
            let q: [String]?
            func encode(to encoder: Encoder) throws {
                _ = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodeQuery(self.q, key: "query")
            }

            private enum CodingKeys: CodingKey {}
        }
        let input = Input(q: ["=3+5897^sdfjh&", "test"])
        let config = createServiceConfig(region: .useast1)

        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.url.absoluteString, "https://test.us-east-1.amazonaws.com/?query=%3D3%2B5897%5Esdfjh%26&query=test")
    }

    func testQueryEncodedDictionary() {
        struct Input: AWSEncodableShape {
            let q: [String: Int]?
            func encode(to encoder: Encoder) throws {
                _ = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodeQuery(self.q)
            }

            private enum CodingKeys: CodingKey {}
        }
        let input = Input(q: ["one": 1, "two": 2])
        let config = createServiceConfig(region: .useast2, service: "myservice")
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.url.absoluteString, "https://myservice.us-east-2.amazonaws.com/?one=1&two=2")
    }

    func testQueryDate() {
        struct Input: AWSEncodableShape {
            let d: Date?
            func encode(to encoder: Encoder) throws {
                _ = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodeQuery(self.d, key: "d")
            }

            private enum CodingKeys: CodingKey {}
        }
        let input = Input(d: Date(timeIntervalSince1970: 1_000_000))
        let config = createServiceConfig(region: .useast2, service: "myservice")
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.url.absoluteString, "https://myservice.us-east-2.amazonaws.com/?d=1000000")
    }

    func testQueryInPath() {
        struct Input: AWSEncodableShape {
            let q: String
            func encode(to encoder: Encoder) throws {
                _ = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodeQuery(self.q, key: "query")
            }

            private enum CodingKeys: CodingKey {}
        }
        let input = Input(q: "path")
        let config = createServiceConfig(region: .useast1)
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/?test=true", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.url.absoluteString, "https://test.us-east-1.amazonaws.com/?query=path&test=true")
    }

    func testQueryProtocolEmptyRequest() {
        let config = createServiceConfig(region: .useast2, service: "myservice", serviceProtocol: .query)
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, configuration: config))
        XCTAssertEqual(request?.body.asString(), "Action=Test&Version=01-01-2001")
    }

    func testURIEncoding() {
        struct Input: AWSEncodableShape {
            let u: String
            func encode(to encoder: Encoder) throws {
                _ = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodePath(self.u, key: "key")
            }

            private enum CodingKeys: CodingKey {}
        }
        let input = Input(u: "MyKey")
        let config = createServiceConfig(region: .cacentral1, service: "s3")
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/{key}", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.url.absoluteString, "https://s3.ca-central-1.amazonaws.com/MyKey")
    }

    func testCreateWithXMLNamespace() throws {
        struct Input: AWSEncodableShape {
            public static let _xmlNamespace: String? = "https://test.amazonaws.com/doc/2020-03-11/"
            let number: Int
        }
        let input = Input(number: 5)
        let xmlConfig = createServiceConfig(serviceProtocol: .restxml)
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: xmlConfig))
        guard case .byteBuffer(let buffer) = request?.body.storage else {
            return XCTFail("Shouldn't get here")
        }
        let element = try XML.Document(buffer: buffer).rootElement()
        XCTAssertEqual(element?.xmlString, "<Input xmlns=\"https://test.amazonaws.com/doc/2020-03-11/\"><number>5</number></Input>")
    }

    func testServiceXMLNamespace() throws {
        struct Input: AWSEncodableShape {
            let number: Int
        }
        let input = Input(number: 5)
        let xmlConfig = createServiceConfig(serviceProtocol: .restxml, xmlNamespace: "https://test.amazonaws.com/doc/2020-03-11/")
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: xmlConfig))
        guard case .byteBuffer(let buffer) = request?.body.storage else {
            return XCTFail("Shouldn't get here")
        }
        let element = try XML.Document(buffer: buffer).rootElement()
        XCTAssertEqual(element?.xmlString, "<Input xmlns=\"https://test.amazonaws.com/doc/2020-03-11/\"><number>5</number></Input>")
    }

    func testDataInJsonPayload() {
        struct DataContainer: AWSEncodableShape {
            let data: Data
        }
        struct J: AWSEncodableShape {
            var _payload: DataContainer { self.dataContainer }
            let dataContainer: DataContainer
        }
        let input = J(dataContainer: DataContainer(data: Data("test data".utf8)))
        let jsonConfig = createServiceConfig(serviceProtocol: .json(version: "1.1"))
        XCTAssertNoThrow(try AWSHTTPRequest(operation: "PutRecord", path: "/", method: .POST, input: input, configuration: jsonConfig))
    }

    func testEC2ClientRequest() {
        struct Input: AWSEncodableShape {
            let array: [String]
        }
        let input = Input(array: ["entry1", "entry2"])
        let config = createServiceConfig(serviceProtocol: .ec2, apiVersion: "2013-12-02")
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.body.asString(), "Action=Test&Array.1=entry1&Array.2=entry2&Version=2013-12-02")
    }

    func testPercentEncodePath() {
        struct Input: AWSEncodableShape {
            let path: String
            func encode(to encoder: Encoder) throws {
                _ = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodePath(self.path, key: "path")
            }

            private enum CodingKeys: CodingKey {}
        }
        let input = Input(path: "Test me/once+")
        let config = createServiceConfig(endpoint: "https://test.com")
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/{path+}", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.url, URL(string: "https://test.com/Test%20me/once%2B")!)
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/{path}", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.url, URL(string: "https://test.com/Test%20me%2Fonce%2B")!)
    }

    func testSortedArrayQuery() {
        struct Input: AWSEncodableShape {
            let items: [String]
            func encode(to encoder: Encoder) throws {
                _ = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodeQuery(self.items, key: "item")
            }

            private enum CodingKeys: CodingKey {}
        }
        let input = Input(items: ["orange", "apple"])
        let config = createServiceConfig(endpoint: "https://test.com")
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.url, URL(string: "https://test.com/?item=apple&item=orange")!)
    }

    func testCustomEncoderInQuery() {
        struct Input: AWSEncodableShape {
            @OptionalCustomCoding<HTTPHeaderDateCoder>
            var date: Date?
            @CustomCoding<StandardArrayCoder>
            var values: [Int]
            func encode(to encoder: Encoder) throws {
                _ = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodeQuery(self._date, key: "date")
                requestContainer.encodeQuery(self._values, key: "values")
            }

            private enum CodingKeys: CodingKey {}
        }
        let input = Input(date: Date(timeIntervalSince1970: 10_000_000), values: [1])
        let config = createServiceConfig(endpoint: "https://test.com")
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.url, URL(string: "https://test.com/?date=Sun%2C%2026%20Apr%201970%2017%3A46%3A40%20GMT")!)
    }

    /// JSON POST request require a body even if there is no data to POST
    func testEmptyPostJsonObject() throws {
        struct Input: AWSEncodableShape {}
        let input = Input()
        let config = createServiceConfig(serviceProtocol: .json(version: "1.0"), endpoint: "https://test.com")
        let request = try AWSHTTPRequest(operation: "Test", path: "/", method: .POST, input: input, configuration: config)
        XCTAssertEqual(request.body.asString(), "{}")
        XCTAssertEqual(request.headers["content-type"].first, "application/x-amz-json-1.0")
    }

    /// JSON POST request require a body even if there is no data to POST
    func testEmptyGetJsonObject() throws {
        struct Input: AWSEncodableShape {}
        let input = Input()
        let config = createServiceConfig(serviceProtocol: .json(version: "1.0"), endpoint: "https://test.com")
        let request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config)
        XCTAssertEqual(request.body.asString(), "")
        XCTAssertNil(request.headers["content-type"].first)
    }

    /// Test host prefix
    func testHostPrefix() {
        struct Input: AWSEncodableShape {}
        let input = Input()
        let config = createServiceConfig(serviceProtocol: .json(version: "1.0"), endpoint: "https://test.com")
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(
            request = try AWSHTTPRequest(
                operation: "Test",
                path: "/",
                method: .POST,
                input: input,
                hostPrefix: "foo.",
                configuration: config
            )
        )
        XCTAssertEqual(request?.url.absoluteString, "https://foo.test.com/")
    }

    /// Test host prefix
    func testHostPrefixLabel() {
        struct Input: AWSEncodableShape {
            let accountId: String
            func encode(to encoder: Encoder) throws {
                _ = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodeHostPrefix(self.accountId, key: "AccountId")
            }

            private enum CodingKeys: CodingKey {}
        }
        let input = Input(accountId: "12345678")
        let config = createServiceConfig(serviceProtocol: .json(version: "1.0"), endpoint: "https://test.com")
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(
            request = try AWSHTTPRequest(
                operation: "Test",
                path: "/",
                method: .POST,
                input: input,
                hostPrefix: "{AccountId}.",
                configuration: config
            )
        )
        XCTAssertEqual(request?.url.absoluteString, "https://12345678.test.com/")
    }

    func testJSONPayload() throws {
        struct Payload: AWSEncodableShape {
            let number: Int
        }
        struct Input: AWSEncodableShape {
            var _payload: Payload { self.payload }
            let payload: Payload

            func encode(to encoder: Encoder) throws {
                try self.payload.encode(to: encoder)
            }
        }
        let input = Input(payload: .init(number: 12_345_678))
        let config = createServiceConfig(serviceProtocol: .json(version: "1.0"))
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(
            request = try AWSHTTPRequest(
                operation: "Test",
                path: "/",
                method: .POST,
                input: input,
                configuration: config
            )
        )
        XCTAssertEqual(request?.body.asString(), #"{"number":12345678}"#)
    }

    func testXMLPayload() throws {
        struct Payload: AWSEncodableShape {
            let number: Int
        }
        struct Input: AWSEncodableShape {
            static let _xmlRootNodeName: String? = "Payload"
            let payload: Payload

            func encode(to encoder: Encoder) throws {
                try self.payload.encode(to: encoder)
            }
        }
        let input = Input(payload: .init(number: 12_345_678))
        let config = createServiceConfig(serviceProtocol: .restxml)
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(
            request = try AWSHTTPRequest(
                operation: "Test",
                path: "/",
                method: .POST,
                input: input,
                configuration: config
            )
        )
        XCTAssertEqual(request?.body.asString(), #"<?xml version="1.0" encoding="UTF-8"?><Payload><number>12345678</number></Payload>"#)
    }

    func testJSONPayloadAndHeader() throws {
        struct Payload: AWSEncodableShape {
            let number: Int
        }
        struct Input: AWSEncodableShape {
            var _payload: Payload { self.payload }
            let payload: Payload
            let contentType: String

            func encode(to encoder: Encoder) throws {
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodeHeader(self.contentType, key: "content-type")
                try self.payload.encode(to: encoder)
            }
        }
        let input = Input(payload: .init(number: 12_345_678), contentType: "image/jpeg")
        let config = createServiceConfig(serviceProtocol: .json(version: "1.0"))
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(
            request = try AWSHTTPRequest(
                operation: "Test",
                path: "/",
                method: .POST,
                input: input,
                configuration: config
            )
        )
        XCTAssertEqual(request?.body.asString(), #"{"number":12345678}"#)
        XCTAssertEqual(request?.headers["content-type"].first, "image/jpeg")
    }

    /// Test disable S3 chunked upload flag works
    func testDisableS3ChunkedUpload() throws {
        struct Input: AWSEncodableShape {
            var _payload: AWSHTTPBody { self.payload }
            public static let _options: AWSShapeOptions = [.rawPayload, .allowStreaming]
            public static let _payloadPath: String = "payload"
            let payload: AWSHTTPBody
            let member: String

            private enum CodingKeys: String, CodingKey {
                case member
            }
        }
        let config = createServiceConfig(service: "s3", signingName: "s3", serviceProtocol: .restxml, options: .s3DisableChunkedUploads)
        let signer = AWSSigner(
            credentials: StaticCredential(accessKeyId: "foo", secretAccessKey: "bar"),
            name: config.signingName,
            region: config.region.rawValue
        )
        let buffer = ByteBuffer(string: "This is a test")
        let stream = AWSHTTPBody(asyncSequence: buffer.asyncSequence(chunkSize: 16), length: buffer.readableBytes)
        let input = Input(payload: stream, member: "test")
        var optionalAWSRequest: AWSHTTPRequest?
        XCTAssertNoThrow(optionalAWSRequest = try AWSHTTPRequest(operation: "Test", path: "/", method: .POST, input: input, configuration: config))
        var awsRequest = try XCTUnwrap(optionalAWSRequest)
        awsRequest.signHeaders(signer: signer, serviceConfig: config)
        XCTAssertNil(awsRequest.headers["x-amz-decoded-content-length"].first)
    }

    func testRequiredMD5Checksum() {
        struct Input: AWSEncodableShape {
            static let _options: AWSShapeOptions = .checksumRequired
            let q: [String]
        }
        let input = Input(q: ["one", "two", "three", "four"])
        let config = createServiceConfig(region: .useast2, service: "myservice")
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.headers["Content-MD5"].first, "3W1MVcXgkODdv+m6VeZqdQ==")
    }

    func testMD5ChecksumHeader() {
        struct Input: AWSEncodableShape {
            static let _options: AWSShapeOptions = .md5ChecksumHeader
            let q: [String]
        }
        let input = Input(q: ["one", "two", "three", "four"])
        let config = createServiceConfig(region: .useast2, service: "myservice", options: .calculateMD5)
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.headers["Content-MD5"].first, "3W1MVcXgkODdv+m6VeZqdQ==")

        let config2 = createServiceConfig(region: .useast2, service: "myservice")
        var request2: AWSHTTPRequest?
        XCTAssertNoThrow(request2 = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config2))
        XCTAssertNil(request2?.headers["Content-MD5"].first)
    }

    func testMD5ChecksumSetAlready() {
        struct Input: AWSEncodableShape {
            static let _options: AWSShapeOptions = .checksumRequired
            let checksum: String?
            let q: [String: Int]
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodeHeader(self.checksum, key: "Content-MD5")
                try container.encode(self.q, forKey: .q)
            }

            private enum CodingKeys: String, CodingKey {
                case q
            }
        }
        let input = Input(checksum: "Set already", q: ["one": 1, "two": 2])
        let config = createServiceConfig(region: .useast2, service: "myservice")
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.headers["Content-MD5"].first, "Set already")
    }

    func testSHA1Checksum() {
        struct Input: AWSEncodableShape {
            static let _options: AWSShapeOptions = .checksumHeader
            let q: [String]
            let checksum: String
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodeHeader(self.checksum, key: "x-amz-sdk-checksum-algorithm")
                try container.encode(self.q, forKey: .q)
            }

            private enum CodingKeys: String, CodingKey {
                case q
            }
        }
        let input = Input(q: ["one", "two", "three", "four"], checksum: "SHA1")
        let config = createServiceConfig(region: .useast2, service: "myservice", serviceProtocol: .restxml)
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.headers["x-amz-checksum-sha1"].first, "wVl5w+ffNcoxzbahfTthTZsuivs=")
    }

    func testCRC32Checksum() {
        struct Input: AWSEncodableShape {
            static let _options: AWSShapeOptions = .checksumHeader
            let q: [String]
            let checksum: String
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodeHeader(self.checksum, key: "x-amz-sdk-checksum-algorithm")
                try container.encode(self.q, forKey: .q)
            }

            private enum CodingKeys: String, CodingKey {
                case q
            }
        }
        let input = Input(q: ["one", "two", "three", "four"], checksum: "CRC32")
        let config = createServiceConfig(region: .useast2, service: "myservice", serviceProtocol: .restxml)
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.headers["x-amz-checksum-crc32"].first, "BNgzYg==")
    }

    func testCRC32CChecksum() {
        struct Input: AWSEncodableShape {
            static let _options: AWSShapeOptions = .checksumHeader
            let q: [String]
            let checksum: String
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodeHeader(self.checksum, key: "x-amz-sdk-checksum-algorithm")
                try container.encode(self.q, forKey: .q)
            }

            private enum CodingKeys: String, CodingKey {
                case q
            }
        }
        let input = Input(q: ["one", "two", "three", "four"], checksum: "CRC32C")
        let config = createServiceConfig(region: .useast2, service: "myservice", serviceProtocol: .restxml)
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.headers["x-amz-checksum-crc32c"].first, "CJR8DA==")
    }

    func testSHA256Checksum() {
        struct Input: AWSEncodableShape {
            static let _options: AWSShapeOptions = .checksumHeader
            let q: [String]
            let checksum: String
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodeHeader(self.checksum, key: "x-amz-sdk-checksum-algorithm")
                try container.encode(self.q, forKey: .q)
            }

            private enum CodingKeys: String, CodingKey {
                case q
            }
        }
        let input = Input(q: ["one", "two", "three", "four"], checksum: "SHA256")
        let config = createServiceConfig(region: .useast2, service: "myservice", serviceProtocol: .restxml)
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.headers["x-amz-checksum-sha256"].first, "QTQclc9fXffjuWqvYJnh/EUMgSdZcp1uOoUeq4SmiFY=")
    }

    func testHeaderPrefix() {
        struct Input: AWSEncodableShape {
            let content: [String: String]
            func encode(to encoder: Encoder) throws {
                _ = encoder.container(keyedBy: CodingKeys.self)
                let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
                requestContainer.encodeHeader(self.content, key: "x-aws-metadata-")
            }

            private enum CodingKeys: CodingKey {}
        }
        let input = Input(content: ["one": "first", "two": "second"])
        let config = createServiceConfig(region: .useast2, service: "myservice", serviceProtocol: .restxml)
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config))
        XCTAssertEqual(request?.headers["x-aws-metadata-one"].first, "first")
        XCTAssertEqual(request?.headers["x-aws-metadata-two"].first, "second")
    }

    func testDocument() throws {
        struct Input: AWSEncodableShape {
            let doc: AWSDocument
        }
        let config = createServiceConfig(region: .useast2, service: "myservice", serviceProtocol: .restjson)
        var request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: Input(doc: "Hello"), configuration: config)
        XCTAssertEqual(request.body.asString(), #"{"doc":"Hello"}"#)
        request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: Input(doc: .integer(4)), configuration: config)
        XCTAssertEqual(request.body.asString(), #"{"doc":4}"#)
        request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: Input(doc: .double(5.25)), configuration: config)
        XCTAssertEqual(request.body.asString(), #"{"doc":5.25}"#)
        request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: Input(doc: .double(5.25)), configuration: config)
        XCTAssertEqual(request.body.asString(), #"{"doc":5.25}"#)
        request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: Input(doc: false), configuration: config)
        XCTAssertEqual(request.body.asString(), #"{"doc":false}"#)
        request = try AWSHTTPRequest(
            operation: "Test",
            path: "/",
            method: .GET,
            input: Input(doc: .array([.string("Hello"), .string("World")])),
            configuration: config
        )
        XCTAssertEqual(request.body.asString(), #"{"doc":["Hello","World"]}"#)
        request = try AWSHTTPRequest(
            operation: "Test",
            path: "/",
            method: .GET,
            input: Input(doc: .map(["first": .integer(1), "second": 2])),
            configuration: config
        )
        XCTAssert(request.body.asString() == #"{"doc":{"first":1,"second":2}}"# || request.body.asString() == #"{"doc":{"second":2,"first":1}}"#)
    }
}
