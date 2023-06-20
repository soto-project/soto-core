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
@testable import SotoCore
import SotoTestUtils
import SotoXML
import XCTest

/// Helper functions for creating response bodies
extension AWSHTTPResponse.Body {
    /// create empty body
    init() {
        self.init {
            return { return nil }
        }
    }

    /// create body from one ByteBuffer
    init(_ byteBuffer: ByteBuffer) {
        self.init {
            var served = false
            return {
                if !served {
                    served = true
                    return byteBuffer
                }
                return nil
            }
        }
    }
}

class AWSResponseTests: XCTestCase {
    func testHeaderResponseDecoding() async throws {
        struct Output: AWSDecodableShape {
            static let _encoding = [AWSMemberEncoding(label: "h", location: .header("header-member"))]
            let h: String
            private enum CodingKeys: String, CodingKey {
                case h = "header-member"
            }
        }
        let response = AWSHTTPResponse(
            status: .ok,
            headers: ["header-member": "test-header"]
        )

        // XML        var awsXMLResponse: awsResponse
        var xmlResult: Output?
        let awsXMLResponse = try await AWSResponse(from: response, serviceProtocol: .query, raw: false)
        XCTAssertNoThrow(xmlResult = try awsXMLResponse.generateOutputShape(operation: "Test"))
        XCTAssertEqual(xmlResult?.h, "test-header")

        // JSON
        var jsonResult: Output?
        let awsJSONResponse = try await AWSResponse(from: response, serviceProtocol: .restjson, raw: false)
        XCTAssertNoThrow(jsonResult = try awsJSONResponse.generateOutputShape(operation: "Test"))
        XCTAssertEqual(jsonResult?.h, "test-header")
    }

    func testHeaderResponseTypeDecoding() async throws {
        struct Output: AWSDecodableShape {
            static let _encoding = [
                AWSMemberEncoding(label: "string", location: .header("string")),
                AWSMemberEncoding(label: "string2", location: .header("string2")),
                AWSMemberEncoding(label: "double", location: .header("double")),
                AWSMemberEncoding(label: "integer", location: .header("integer")),
                AWSMemberEncoding(label: "bool", location: .header("bool")),
            ]
            let string: String
            let string2: String
            let double: Double
            let integer: Int
            let bool: Bool
        }
        let response = AWSHTTPResponse(
            status: .ok,
            headers: [
                "string": "test-header",
                "string2": "23",
                "double": "3.14",
                "integer": "901",
                "bool": "false",
            ]
        )

        // JSON        var awsJSONResponse: awsResponse
        var jsonResult: Output?
        let awsJSONResponse = try await AWSResponse(from: response, serviceProtocol: .restjson, raw: false)
        XCTAssertNoThrow(jsonResult = try awsJSONResponse.generateOutputShape(operation: "Test"))
        XCTAssertEqual(jsonResult?.string, "test-header")
        XCTAssertEqual(jsonResult?.string2, "23")
        XCTAssertEqual(jsonResult?.double, 3.14)
        XCTAssertEqual(jsonResult?.integer, 901)
        XCTAssertEqual(jsonResult?.bool, false)
    }

    func testStatusCodeResponseDecoding() async throws {
        struct Output: AWSDecodableShape {
            static let _encoding = [AWSMemberEncoding(label: "status", location: .statusCode)]
            let status: Int
        }
        let response = AWSHTTPResponse(
            status: .ok,
            headers: HTTPHeaders()
        )

        // XML
        var xmlResult: Output?
        let awsXMLResponse = try await AWSResponse(from: response, serviceProtocol: .query, raw: false)
        XCTAssertNoThrow(xmlResult = try awsXMLResponse.generateOutputShape(operation: "Test"))
        XCTAssertEqual(xmlResult?.status, 200)

        // JSON
        var jsonResult: Output?
        let awsJSONResponse = try await AWSResponse(from: response, serviceProtocol: .restjson, raw: false)
        XCTAssertNoThrow(jsonResult = try awsJSONResponse.generateOutputShape(operation: "Test"))
        XCTAssertEqual(jsonResult?.status, 200)
    }

    // MARK: XML tests

    func testValidateXMLResponse() async throws {
        struct Output: AWSDecodableShape {
            let name: String
        }
        let responseBody = "<Output><name>hello</name></Output>"
        let response = AWSHTTPResponse(
            status: .ok,
            headers: HTTPHeaders(),
            body: .init(ByteBuffer(string: responseBody))
        )

        var output: Output?
        let awsResponse = try await AWSResponse(from: response, serviceProtocol: .restxml, raw: false)
        XCTAssertNoThrow(output = try awsResponse.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.name, "hello")
    }

    func testValidateXMLCodablePayloadResponse() async throws {
        struct Output: AWSDecodableShape & AWSShapeWithPayload {
            static let _encoding = [AWSMemberEncoding(label: "contentType", location: .header("content-type"))]
            static let _payloadPath: String = "name"
            let name: String
            let contentType: String

            private enum CodingKeys: String, CodingKey {
                case name
                case contentType = "content-type"
            }
        }
        let response = AWSHTTPResponse(
            status: .ok,
            headers: ["Content-Type": "application/xml"],
            body: .init(ByteBuffer(string: "<name>hello</name>"))
        )

        var output: Output?
        let awsResponse = try await AWSResponse(from: response, serviceProtocol: .restxml, raw: false)
        XCTAssertNoThrow(output = try awsResponse.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.name, "hello")
        XCTAssertEqual(output?.contentType, "application/xml")
    }

    func testValidateXMLRawPayloadResponse() async throws {
        struct Output: AWSDecodableShape, AWSShapeWithPayload {
            static let _payloadPath: String = "body"
            static let _options: AWSShapeOptions = .rawPayload
            let body: AWSPayload
        }
        let response = AWSHTTPResponse(
            status: .ok,
            headers: HTTPHeaders(),
            body: .init(ByteBuffer(string: "{\"name\":\"hello\"}"))
        )

        var output: Output?
        let awsResponse = try await AWSResponse(from: response, serviceProtocol: .restxml, raw: true)
        XCTAssertNoThrow(output = try awsResponse.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.body.asString(), "{\"name\":\"hello\"}")
    }

    // MARK: JSON tests

    func testValidateJSONResponse() async throws {
        struct Output: AWSDecodableShape {
            let name: String
        }
        let response = AWSHTTPResponse(
            status: .ok,
            headers: HTTPHeaders(),
            body: .init(ByteBuffer(string: "{\"name\":\"hello\"}"))
        )

        var output: Output?
        let awsResponse = try await AWSResponse(from: response, serviceProtocol: .json(version: "1.1"), raw: false)
        XCTAssertNoThrow(output = try awsResponse.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.name, "hello")
    }

    func testValidateJSONCodablePayloadResponse() async throws {
        struct Output2: AWSDecodableShape {
            let name: String
        }
        struct Output: AWSDecodableShape & AWSShapeWithPayload {
            static let _payloadPath: String = "output2"
            let output2: Output2
        }
        let response = AWSHTTPResponse(
            status: .ok,
            headers: HTTPHeaders(),
            body: .init(ByteBuffer(string: "{\"name\":\"hello\"}"))
        )

        var output: Output?
        let awsResponse = try await AWSResponse(from: response, serviceProtocol: .json(version: "1.1"), raw: false)
        XCTAssertNoThrow(output = try awsResponse.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.output2.name, "hello")
    }

    func testValidateJSONRawPayloadResponse() async throws {
        struct Output: AWSDecodableShape, AWSShapeWithPayload {
            static let _payloadPath: String = "body"
            static let _options: AWSShapeOptions = .rawPayload
            public static var _encoding = [
                AWSMemberEncoding(label: "contentType", location: .header("content-type")),
            ]
            let body: AWSPayload
        }
        let response = AWSHTTPResponse(
            status: .ok,
            headers: ["Content-Type": "application/json"],
            body: .init(ByteBuffer(string: "{\"name\":\"hello\"}"))
        )

        var output: Output?
        let awsResponse = try await AWSResponse(from: response, serviceProtocol: .json(version: "1.1"), raw: true)
        XCTAssertNoThrow(output = try awsResponse.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.body.asString(), "{\"name\":\"hello\"}")
    }

    // MARK: Error tests

    func testJSONError() async throws {
        let response = AWSHTTPResponse(
            status: .notFound,
            headers: HTTPHeaders(),
            body: .init(ByteBuffer(string: "{\"__type\":\"ResourceNotFoundException\", \"message\": \"Donald Where's Your Troosers?\"}"))
        )
        let service = createServiceConfig(serviceProtocol: .json(version: "1.1"), errorType: ServiceErrorType.self)

        let awsResponse = try await AWSResponse(from: response, serviceProtocol: .json(version: "1.1"), raw: false)
        let error = awsResponse.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? ServiceErrorType
        XCTAssertEqual(error, ServiceErrorType.resourceNotFoundException)
        XCTAssertEqual(error?.message, "Donald Where's Your Troosers?")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
    }

    func testJSONErrorV2() async throws {
        let response = AWSHTTPResponse(
            status: .notFound,
            headers: HTTPHeaders(),
            body: .init(ByteBuffer(string:
                #"{"__type":"ResourceNotFoundException", "Message": "Donald Where's Your Troosers?", "fault": "client","CancellationReasons":1}"#
            ))
        )
        let service = createServiceConfig(serviceProtocol: .json(version: "1.1"), errorType: ServiceErrorType.self)

        let awsResponse = try await AWSResponse(from: response, serviceProtocol: .json(version: "1.1"), raw: false)
        let error = awsResponse.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? ServiceErrorType
        XCTAssertEqual(error, ServiceErrorType.resourceNotFoundException)
        XCTAssertEqual(error?.message, "Donald Where's Your Troosers?")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
        XCTAssertEqual(error?.context?.additionalFields["fault"], "client")
    }

    func testRestJSONError() async throws {
        let response = AWSHTTPResponse(
            status: .notFound,
            headers: ["x-amzn-errortype": "ResourceNotFoundException"],
            body: .init(ByteBuffer(string: #"{"message": "Donald Where's Your Troosers?", "Fault": "Client"}"#))
        )
        let service = createServiceConfig(serviceProtocol: .restjson, errorType: ServiceErrorType.self)

        let awsResponse = try await AWSResponse(from: response, serviceProtocol: .restjson, raw: false)
        let error = awsResponse.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? ServiceErrorType
        XCTAssertEqual(error, ServiceErrorType.resourceNotFoundException)
        XCTAssertEqual(error?.message, "Donald Where's Your Troosers?")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
        XCTAssertEqual(error?.context?.additionalFields["Fault"], "Client")
    }

    func testRestJSONErrorV2() async throws {
        // Capitalized "Message"
        let response = AWSHTTPResponse(
            status: .notFound,
            headers: ["x-amzn-errortype": "ResourceNotFoundException"],
            body: .init(ByteBuffer(string: #"{"Message": "Donald Where's Your Troosers?"}"#))
        )
        let service = createServiceConfig(serviceProtocol: .restjson, errorType: ServiceErrorType.self)

        let awsResponse = try await AWSResponse(from: response, serviceProtocol: .restjson, raw: false)
        let error = awsResponse.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? ServiceErrorType
        XCTAssertEqual(error, ServiceErrorType.resourceNotFoundException)
        XCTAssertEqual(error?.message, "Donald Where's Your Troosers?")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
    }

    func testXMLError() async throws {
        let response = AWSHTTPResponse(
            status: .notFound,
            headers: HTTPHeaders(),
            body: .init(ByteBuffer(string: "<Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message><fault>client</fault></Error>"))
        )
        let service = createServiceConfig(serviceProtocol: .restxml, errorType: ServiceErrorType.self)

        let awsResponse = try await AWSResponse(from: response, serviceProtocol: .restxml, raw: false)
        let error = awsResponse.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? ServiceErrorType
        XCTAssertEqual(error, ServiceErrorType.noSuchKey)
        XCTAssertEqual(error?.message, "It doesn't exist")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
        XCTAssertEqual(error?.context?.additionalFields["fault"], "client")
    }

    func testQueryError() async throws {
        let response = AWSHTTPResponse(
            status: .notFound,
            headers: HTTPHeaders(),
            body: .init(ByteBuffer(string: "<ErrorResponse><Error><Code>MessageRejected</Code><Message>Don't like it</Message><fault>client</fault></Error></ErrorResponse>"))
        )
        let queryService = createServiceConfig(serviceProtocol: .query, errorType: ServiceErrorType.self)

        let awsResponse = try await AWSResponse(from: response, serviceProtocol: .query, raw: false)
        let error = awsResponse.generateError(serviceConfig: queryService, logger: TestEnvironment.logger) as? ServiceErrorType
        XCTAssertEqual(error, ServiceErrorType.messageRejected)
        XCTAssertEqual(error?.message, "Don't like it")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
        XCTAssertEqual(error?.context?.additionalFields["fault"], "client")
    }

    func testEC2Error() async throws {
        let response = AWSHTTPResponse(
            status: .notFound,
            headers: HTTPHeaders(),
            body: .init(ByteBuffer(string: "<Errors><Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message><fault>client</fault></Error></Errors>"))
        )
        let service = createServiceConfig(serviceProtocol: .ec2)

        let awsResponse = try await AWSResponse(from: response, serviceProtocol: .ec2, raw: false)
        let error = awsResponse.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? AWSResponseError
        XCTAssertEqual(error?.errorCode, "NoSuchKey")
        XCTAssertEqual(error?.message, "It doesn't exist")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
        XCTAssertEqual(error?.context?.additionalFields["fault"], "client")
    }

    func testAdditionalErrorFields() async throws {
        let response = AWSHTTPResponse(
            status: .notFound,
            headers: HTTPHeaders(),
            body: .init(ByteBuffer(string: "<Errors><Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message><fault>client</fault></Error></Errors>"))
        )
        let service = createServiceConfig(serviceProtocol: .restxml)

        let awsResponse = try await AWSResponse(from: response, serviceProtocol: .ec2, raw: false)
        let error = awsResponse.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? AWSResponseError
        XCTAssertEqual(error?.context?.additionalFields["fault"], "client")
    }

    func testHeaderPrefixFromDictionary() async throws {
        struct Output: AWSDecodableShape {
            static let _encoding: [AWSMemberEncoding] = [
                .init(label: "content", location: .headerPrefix("prefix-")),
            ]
            let content: [String: String]
            private enum CodingKeys: String, CodingKey {
                case content = "prefix-"
            }
        }
        let response = AWSHTTPResponse(
            status: .ok,
            headers: ["prefix-one": "first", "prefix-two": "second"]
        )
        var output: Output?
        let awsResponse = try await AWSResponse(from: response, serviceProtocol: .restxml)
        XCTAssertNoThrow(output = try awsResponse.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.content["one"], "first")
        XCTAssertEqual(output?.content["two"], "second")
    }

    func testHeaderPrefixFromXML() async throws {
        struct Output: AWSDecodableShape {
            static let _encoding: [AWSMemberEncoding] = [
                .init(label: "content", location: .headerPrefix("prefix-")),
            ]
            let content: [String: String]
            let body: String
            private enum CodingKeys: String, CodingKey {
                case body
                case content = "prefix-"
            }
        }
        let response = AWSHTTPResponse(
            status: .ok,
            headers: ["prefix-one": "first", "prefix-two": "second"],
            body: .init(ByteBuffer(string: "<Output><body>Hello</body></Output>"))
        )
        var output: Output?
        let awsResponse = try await AWSResponse(from: response, serviceProtocol: .restxml)
        XCTAssertNoThrow(output = try awsResponse.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.content["one"], "first")
        XCTAssertEqual(output?.content["two"], "second")
    }

    // MARK: Miscellaneous tests

    func testProcessHAL() async throws {
        struct Output: AWSDecodableShape {
            let s: String
            let i: Int
        }
        struct Output2: AWSDecodableShape {
            let a: [Output]
            let d: Double
            let b: Bool
        }
        let response = AWSHTTPResponse(
            status: .ok,
            headers: ["Content-Type": "application/hal+json"],
            body: .init(ByteBuffer(string: #"{"_embedded": {"a": [{"s":"Hello", "i":1234}, {"s":"Hello2", "i":12345}]}, "d":3.14, "b":true}"#))
        )

        var output: Output2?
        let awsResponse = try await AWSResponse(from: response, serviceProtocol: .json(version: "1.1"), raw: false)
        XCTAssertNoThrow(output = try awsResponse.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.a.count, 2)
        XCTAssertEqual(output?.d, 3.14)
        XCTAssertEqual(output?.a[1].s, "Hello2")
    }

    // MARK: Types used in tests

    struct ServiceErrorType: AWSErrorType, Equatable {
        enum Code: String {
            case resourceNotFoundException = "ResourceNotFoundException"
            case noSuchKey = "NoSuchKey"
            case messageRejected = "MessageRejected"
        }

        let error: Code
        let context: AWSErrorContext?

        init?(errorCode: String, context: AWSErrorContext) {
            guard let error = Code(rawValue: errorCode) else { return nil }
            self.error = error
            self.context = context
        }

        internal init(_ error: Code, context: AWSErrorContext? = nil) {
            self.error = error
            self.context = context
        }

        public var errorCode: String { self.error.rawValue }

        public static var resourceNotFoundException: ServiceErrorType { .init(.resourceNotFoundException) }
        public static var noSuchKey: ServiceErrorType { .init(.noSuchKey) }
        public static var messageRejected: ServiceErrorType { .init(.messageRejected) }

        public static func == (lhs: ServiceErrorType, rhs: ServiceErrorType) -> Bool {
            lhs.error == rhs.error
        }

        public var description: String {
            return "\(self.error.rawValue): \(message ?? "")"
        }
    }
}
