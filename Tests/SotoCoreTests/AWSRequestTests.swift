//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2026 the Soto project authors
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
import Testing

@testable @_spi(SotoInternal) import SotoCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

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

class AWSRequestTests {
    struct E: AWSEncodableShape & Decodable {
        let Member = ["memberKey": "memberValue", "memberKey2": "memberValue2"]

        private enum CodingKeys: String, CodingKey {
            case Member
        }
    }

    @Test func testPartitionEndpoints() {
        let config = createServiceConfig(
            serviceEndpoints: ["aws-global": "service.aws.amazon.com"],
            partitionEndpoints: [.aws: (endpoint: "aws-global", region: .euwest1)]
        )

        #expect(config.region == .euwest1)

        var request: AWSHTTPRequest?
        #expect(throws: Never.self) { request = try AWSHTTPRequest(operation: "test", path: "/", method: .GET, configuration: config) }
        #expect(request?.url.absoluteString == "https://service.aws.amazon.com/")
    }

    @Test func testCreateAwsRequestWithKeywordInHeader() {
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
        #expect(throws: Never.self) {
            awsRequest = try AWSHTTPRequest(operation: "Keyword", path: "/", method: .POST, input: request, configuration: config)
        }
        #expect(awsRequest?.headers["repeat"].first == "Repeat")
    }

    @Test func testCreateAwsRequestWithKeywordInQuery() {
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
        #expect(throws: Never.self) {
            awsRequest = try AWSHTTPRequest(operation: "Keyword", path: "/", method: .POST, input: request, configuration: config)
        }
        #expect(awsRequest?.url == URL(string: "https://s3.ca-central-1.amazonaws.com/?throw=KeywordRequest")!)
    }

    @Test func testCreateNIORequest() throws {
        let input2 = E()

        let config = createServiceConfig(region: .useast1, service: "kinesis", serviceProtocol: .json(version: "1.1"))

        var awsRequest: AWSHTTPRequest = try AWSHTTPRequest(
            operation: "PutRecord",
            path: "/",
            method: .POST,
            input: input2,
            configuration: config
        )

        let signer = AWSSigner(
            credentials: StaticCredential(accessKeyId: "foo", secretAccessKey: "bar"),
            name: config.signingName,
            region: config.region.rawValue
        )

        awsRequest.signHeaders(signer: signer, serviceConfig: config)
        #expect(awsRequest.method == HTTPMethod.POST)
        #expect(awsRequest.headers["Host"].first == "kinesis.us-east-1.amazonaws.com")
        #expect(awsRequest.headers["Content-Type"].first == "application/x-amz-json-1.1")
    }

    @Test func testUnsignedClient() throws {
        let input = E()
        let config = createServiceConfig()

        var awsRequest: AWSHTTPRequest = try AWSHTTPRequest(
            operation: "CopyObject",
            path: "/",
            method: .PUT,
            input: input,
            configuration: config
        )

        let signer = AWSSigner(
            credentials: StaticCredential(accessKeyId: "", secretAccessKey: ""),
            name: config.signingName,
            region: config.region.rawValue
        )

        awsRequest.signHeaders(signer: signer, serviceConfig: config)
        #expect(awsRequest.headers["Authorization"].first == nil)
    }

    @Test func testSignedClient() throws {
        let input = E()
        let config = createServiceConfig()

        let signer = AWSSigner(
            credentials: StaticCredential(accessKeyId: "foo", secretAccessKey: "bar"),
            name: config.signingName,
            region: config.region.rawValue
        )

        for httpMethod in [HTTPMethod.GET, .HEAD, .PUT, .DELETE, .POST, .PATCH] {
            var awsRequest: AWSHTTPRequest = try AWSHTTPRequest(
                operation: "Test",
                path: "/",
                method: httpMethod,
                input: input,
                configuration: config
            )

            awsRequest.signHeaders(signer: signer, serviceConfig: config)
            #expect(awsRequest.headers["Authorization"].first != nil)
        }
    }

    @Test func testProtocolContentType() throws {
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
        #expect(throws: Never.self) {
            request = try AWSHTTPRequest(operation: "test", path: "/", method: .POST, input: object, configuration: config)
        }
        #expect(request?.headers["content-type"].first == "application/x-amz-json-1.1")

        let config2 = createServiceConfig(serviceProtocol: .restjson)
        var request2: AWSHTTPRequest?
        #expect(throws: Never.self) {
            request2 = try AWSHTTPRequest(operation: "test", path: "/", method: .POST, input: object, configuration: config2)
        }
        #expect(request2?.headers["content-type"].first == "application/json")
        var rawRequest2: AWSHTTPRequest?
        #expect(throws: Never.self) {
            rawRequest2 = try AWSHTTPRequest(operation: "test", path: "/", method: .POST, input: object2, configuration: config2)
        }
        #expect(rawRequest2?.headers["content-type"].first == "binary/octet-stream")

        let config3 = createServiceConfig(serviceProtocol: .query)
        var request3: AWSHTTPRequest?
        #expect(throws: Never.self) {
            request3 = try AWSHTTPRequest(operation: "test", path: "/", method: .POST, input: object, configuration: config3)
        }
        #expect(request3?.headers["content-type"].first == "application/x-www-form-urlencoded; charset=utf-8")

        let config4 = createServiceConfig(serviceProtocol: .ec2)
        var request4: AWSHTTPRequest?
        #expect(throws: Never.self) {
            request4 = try AWSHTTPRequest(operation: "test", path: "/", method: .POST, input: object, configuration: config4)
        }
        #expect(request4?.headers["content-type"].first == "application/x-www-form-urlencoded; charset=utf-8")

        let config5 = createServiceConfig(serviceProtocol: .restxml)
        var request5: AWSHTTPRequest?
        #expect(throws: Never.self) {
            request5 = try AWSHTTPRequest(operation: "test", path: "/", method: .POST, input: object, configuration: config5)
        }
        #expect(request5?.headers["content-type"].first == "application/octet-stream")
    }

    @Test func testHeaderEncoding() {
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
        #expect(throws: Never.self) { request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config) }
        #expect(request?.headers["header-member"].first == "TestHeader")
    }

    @Test func testHeaderDateEncoding() {
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
        #expect(throws: Never.self) { request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config) }
        #expect(request?.headers["date"].first == "Mon, 12 Jan 1970 13:46:40 GMT")
        #expect(request?.headers["iso8601-date"].first == "1970-01-12T13:46:40.000Z")
    }

    @Test func testQueryEncoding() {
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
        #expect(throws: Never.self) { request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config) }
        #expect(request?.url.absoluteString == "https://test.us-east-1.amazonaws.com/?puery=hmmm&query=%3D3%2B5897%5Esdfjh%26")
    }

    @Test func testQueryEncodedArray() {
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
        #expect(throws: Never.self) { request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config) }
        #expect(request?.url.absoluteString == "https://test.us-east-1.amazonaws.com/?query=%3D3%2B5897%5Esdfjh%26&query=test")
    }

    @Test func testQueryEncodedDictionary() {
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
        #expect(throws: Never.self) { request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config) }
        #expect(request?.url.absoluteString == "https://myservice.us-east-2.amazonaws.com/?one=1&two=2")
    }

    @Test func testQueryDate() {
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
        #expect(throws: Never.self) { request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config) }
        #expect(request?.url.absoluteString == "https://myservice.us-east-2.amazonaws.com/?d=1000000")
    }

    @Test func testQueryInPath() {
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
        #expect(throws: Never.self) {
            request = try AWSHTTPRequest(operation: "Test", path: "/?test=true", method: .GET, input: input, configuration: config)
        }
        #expect(request?.url.absoluteString == "https://test.us-east-1.amazonaws.com/?query=path&test=true")
    }

    @Test func testQueryProtocolEmptyRequest() {
        let config = createServiceConfig(region: .useast2, service: "myservice", serviceProtocol: .query)
        var request: AWSHTTPRequest?
        #expect(throws: Never.self) { request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, configuration: config) }
        #expect(request?.body.asString() == "Action=Test&Version=01-01-2001")
    }

    @Test func testURIEncoding() {
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
        #expect(throws: Never.self) {
            request = try AWSHTTPRequest(operation: "Test", path: "/{key}", method: .GET, input: input, configuration: config)
        }
        #expect(request?.url.absoluteString == "https://s3.ca-central-1.amazonaws.com/MyKey")
    }

    @Test func testCreateWithXMLNamespace() throws {
        struct Input: AWSEncodableShape {
            public static let _xmlNamespace: String? = "https://test.amazonaws.com/doc/2020-03-11/"
            let number: Int
        }
        let input = Input(number: 5)
        let xmlConfig = createServiceConfig(serviceProtocol: .restxml)
        var request: AWSHTTPRequest?
        #expect(throws: Never.self) {
            request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: xmlConfig)
        }
        guard case .byteBuffer(let buffer) = request?.body.storage else {
            Issue.record("Shouldn't get here")
            return
        }
        let element = try XML.Document(buffer: buffer).rootElement()
        #expect(element?.xmlString == "<Input xmlns=\"https://test.amazonaws.com/doc/2020-03-11/\"><number>5</number></Input>")
    }

    @Test func testServiceXMLNamespace() throws {
        struct Input: AWSEncodableShape {
            let number: Int
        }
        let input = Input(number: 5)
        let xmlConfig = createServiceConfig(serviceProtocol: .restxml, xmlNamespace: "https://test.amazonaws.com/doc/2020-03-11/")
        var request: AWSHTTPRequest?
        #expect(throws: Never.self) {
            request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: xmlConfig)
        }
        guard case .byteBuffer(let buffer) = request?.body.storage else {
            Issue.record("Shouldn't get here")
            return
        }
        let element = try XML.Document(buffer: buffer).rootElement()
        #expect(element?.xmlString == "<Input xmlns=\"https://test.amazonaws.com/doc/2020-03-11/\"><number>5</number></Input>")
    }

    @Test func testDataInJsonPayload() {
        struct DataContainer: AWSEncodableShape {
            let data: Data
        }
        struct J: AWSEncodableShape {
            var _payload: DataContainer { self.dataContainer }
            let dataContainer: DataContainer
        }
        let input = J(dataContainer: DataContainer(data: Data("test data".utf8)))
        let jsonConfig = createServiceConfig(serviceProtocol: .json(version: "1.1"))
        #expect(throws: Never.self) { try AWSHTTPRequest(operation: "PutRecord", path: "/", method: .POST, input: input, configuration: jsonConfig) }
    }

    @Test func testEC2ClientRequest() {
        struct Input: AWSEncodableShape {
            let array: [String]
        }
        let input = Input(array: ["entry1", "entry2"])
        let config = createServiceConfig(serviceProtocol: .ec2, apiVersion: "2013-12-02")
        var request: AWSHTTPRequest?
        #expect(throws: Never.self) { request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config) }
        #expect(request?.body.asString() == "Action=Test&Array.1=entry1&Array.2=entry2&Version=2013-12-02")
    }

    @Test func testPercentEncodePath() {
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
        #expect(throws: Never.self) {
            request = try AWSHTTPRequest(operation: "Test", path: "/{path+}", method: .GET, input: input, configuration: config)
        }
        #expect(request?.url == URL(string: "https://test.com/Test%20me/once%2B")!)
        #expect(throws: Never.self) {
            request = try AWSHTTPRequest(operation: "Test", path: "/{path}", method: .GET, input: input, configuration: config)
        }
        #expect(request?.url == URL(string: "https://test.com/Test%20me%2Fonce%2B")!)
    }

    @Test func testSortedArrayQuery() {
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
        #expect(throws: Never.self) { request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config) }
        #expect(request?.url == URL(string: "https://test.com/?item=apple&item=orange")!)
    }

    @Test func testCustomEncoderInQuery() {
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
        #expect(throws: Never.self) { request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config) }
        #expect(request?.url == URL(string: "https://test.com/?date=Sun%2C%2026%20Apr%201970%2017%3A46%3A40%20GMT")!)
    }

    /// JSON POST request require a body even if there is no data to POST
    @Test func testEmptyPostJsonObject() throws {
        struct Input: AWSEncodableShape {}
        let input = Input()
        let config = createServiceConfig(serviceProtocol: .json(version: "1.0"), endpoint: "https://test.com")
        let request = try AWSHTTPRequest(operation: "Test", path: "/", method: .POST, input: input, configuration: config)
        #expect(request.body.asString() == "{}")
        #expect(request.headers["content-type"].first == "application/x-amz-json-1.0")
    }

    /// JSON GET, HEAD, DELETE requests should not output a body if it is empty ie `{}`
    @Test func testEmptyGetJsonObject() throws {
        struct Input: AWSEncodableShape {}
        let input = Input()
        let config = createServiceConfig(serviceProtocol: .json(version: "1.0"), endpoint: "https://test.com")
        let request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config)
        #expect(request.body.asString() == "")
        #expect(request.headers["content-type"].first == nil)
        let request2 = try AWSHTTPRequest(operation: "Test", path: "/", method: .HEAD, input: input, configuration: config)
        #expect(request2.body.asString() == "")
        #expect(request2.headers["content-type"].first == nil)
        let request3 = try AWSHTTPRequest(operation: "Test", path: "/", method: .DELETE, input: input, configuration: config)
        #expect(request3.body.asString() == "")
        #expect(request3.headers["content-type"].first == nil)
    }

    /// Test host prefix
    @Test func testHostPrefix() throws {
        struct Input: AWSEncodableShape {}
        let input = Input()
        let config = createServiceConfig(serviceProtocol: .json(version: "1.0"), endpoint: "https://test.com")
        let request = try AWSHTTPRequest(
            operation: "Test",
            path: "/",
            method: .POST,
            input: input,
            hostPrefix: "foo.",
            configuration: config
        )
        #expect(request.url.absoluteString == "https://foo.test.com/")
    }

    /// Test host prefix
    @Test func testHostPrefixLabel() throws {
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
        let request = try AWSHTTPRequest(
            operation: "Test",
            path: "/",
            method: .POST,
            input: input,
            hostPrefix: "{AccountId}.",
            configuration: config
        )

        #expect(request.url.absoluteString == "https://12345678.test.com/")
    }

    @Test func testJSONPayload() throws {
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
        let request = try AWSHTTPRequest(
            operation: "Test",
            path: "/",
            method: .POST,
            input: input,
            configuration: config
        )

        #expect(request.body.asString() == #"{"number":12345678}"#)
    }

    @Test func testXMLPayload() throws {
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
        let request = try AWSHTTPRequest(
            operation: "Test",
            path: "/",
            method: .POST,
            input: input,
            configuration: config
        )

        #expect(request.body.asString() == #"<?xml version="1.0" encoding="UTF-8"?><Payload><number>12345678</number></Payload>"#)
    }

    @Test func testJSONPayloadAndHeader() throws {
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
        let request = try AWSHTTPRequest(
            operation: "Test",
            path: "/",
            method: .POST,
            input: input,
            configuration: config
        )

        #expect(request.body.asString() == #"{"number":12345678}"#)
        #expect(request.headers["content-type"].first == "image/jpeg")
    }

    /// Test disable S3 chunked upload flag works
    @Test func testDisableS3ChunkedUpload() throws {
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
        #expect(throws: Never.self) {
            optionalAWSRequest = try AWSHTTPRequest(operation: "Test", path: "/", method: .POST, input: input, configuration: config)
        }
        var awsRequest = try #require(optionalAWSRequest)
        awsRequest.signHeaders(signer: signer, serviceConfig: config)
        #expect(awsRequest.headers["x-amz-decoded-content-length"].first == nil)
    }

    @Test func testRequiredMD5Checksum() {
        struct Input: AWSEncodableShape {
            static let _options: AWSShapeOptions = .checksumRequired
            let q: [String]
        }
        let input = Input(q: ["one", "two", "three", "four"])
        let config = createServiceConfig(region: .useast2, service: "myservice")
        var request: AWSHTTPRequest?
        #expect(throws: Never.self) { request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config) }
        #expect(request?.headers["Content-MD5"].first == "3W1MVcXgkODdv+m6VeZqdQ==")
    }

    @Test func testMD5ChecksumHeader() {
        struct Input: AWSEncodableShape {
            static let _options: AWSShapeOptions = .md5ChecksumHeader
            let q: [String]
        }
        let input = Input(q: ["one", "two", "three", "four"])
        let config = createServiceConfig(region: .useast2, service: "myservice", options: .calculateMD5)
        var request: AWSHTTPRequest?
        #expect(throws: Never.self) { request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config) }
        #expect(request?.headers["Content-MD5"].first == "3W1MVcXgkODdv+m6VeZqdQ==")

        let config2 = createServiceConfig(region: .useast2, service: "myservice")
        var request2: AWSHTTPRequest?
        #expect(throws: Never.self) {
            request2 = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config2)
        }
        #expect(request2?.headers["Content-MD5"].first == nil)
    }

    @Test func testMD5ChecksumSetAlready() {
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
        #expect(throws: Never.self) { request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config) }
        #expect(request?.headers["Content-MD5"].first == "Set already")
    }

    @Test func testSHA1Checksum() {
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
        #expect(throws: Never.self) { request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config) }
        #expect(request?.headers["x-amz-checksum-sha1"].first == "wVl5w+ffNcoxzbahfTthTZsuivs=")
    }

    @Test func testCRC32Checksum() {
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
        #expect(throws: Never.self) { request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config) }
        #expect(request?.headers["x-amz-checksum-crc32"].first == "BNgzYg==")
    }

    @Test func testCRC32CChecksum() {
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
        #expect(throws: Never.self) { request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config) }
        #expect(request?.headers["x-amz-checksum-crc32c"].first == "CJR8DA==")
    }

    @Test func testSHA256Checksum() {
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
        #expect(throws: Never.self) { request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config) }
        #expect(request?.headers["x-amz-checksum-sha256"].first == "QTQclc9fXffjuWqvYJnh/EUMgSdZcp1uOoUeq4SmiFY=")
    }

    @Test func testHeaderPrefix() {
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
        #expect(throws: Never.self) { request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: input, configuration: config) }
        #expect(request?.headers["x-aws-metadata-one"].first == "first")
        #expect(request?.headers["x-aws-metadata-two"].first == "second")
    }

    @Test func testDocument() throws {
        struct Input: AWSEncodableShape {
            let doc: AWSDocument
        }
        let config = createServiceConfig(region: .useast2, service: "myservice", serviceProtocol: .restjson)
        var request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: Input(doc: "Hello"), configuration: config)
        #expect(request.body.asString() == #"{"doc":"Hello"}"#)
        request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: Input(doc: .integer(4)), configuration: config)
        #expect(request.body.asString() == #"{"doc":4}"#)
        request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: Input(doc: .double(5.25)), configuration: config)
        #expect(request.body.asString() == #"{"doc":5.25}"#)
        request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: Input(doc: .double(5.25)), configuration: config)
        #expect(request.body.asString() == #"{"doc":5.25}"#)
        request = try AWSHTTPRequest(operation: "Test", path: "/", method: .GET, input: Input(doc: false), configuration: config)
        #expect(request.body.asString() == #"{"doc":false}"#)
        request = try AWSHTTPRequest(
            operation: "Test",
            path: "/",
            method: .GET,
            input: Input(doc: .array([.string("Hello"), .string("World")])),
            configuration: config
        )
        #expect(request.body.asString() == #"{"doc":["Hello","World"]}"#)
        request = try AWSHTTPRequest(
            operation: "Test",
            path: "/",
            method: .GET,
            input: Input(doc: .map(["first": .integer(1), "second": 2])),
            configuration: config
        )
        #expect(request.body.asString() == #"{"doc":{"first":1,"second":2}}"# || request.body.asString() == #"{"doc":{"second":2,"first":1}}"#)
    }
}
