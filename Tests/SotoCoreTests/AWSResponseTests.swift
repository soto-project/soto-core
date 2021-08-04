//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO
import NIOHTTP1
@testable import SotoCore
import SotoTestUtils
import SotoXML
import XCTest

class AWSResponseTests: XCTestCase {
    func testHeaderResponseDecoding() {
        struct Output: AWSDecodableShape {
            static let _encoding = [AWSMemberEncoding(label: "h", location: .header(locationName: "header-member"))]
            let h: String
            private enum CodingKeys: String, CodingKey {
                case h = "header-member"
            }
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: ["header-member": "test-header"],
            bodyData: nil
        )

        // XML
        var awsXMLResponse: AWSResponse?
        var xmlResult: Output?
        XCTAssertNoThrow(awsXMLResponse = try AWSResponse(from: response, serviceProtocol: .query, raw: false))
        XCTAssertNoThrow(xmlResult = try awsXMLResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(xmlResult?.h, "test-header")

        // JSON
        var awsJSONResponse: AWSResponse?
        var jsonResult: Output?
        XCTAssertNoThrow(awsJSONResponse = try AWSResponse(from: response, serviceProtocol: .restjson, raw: false))
        XCTAssertNoThrow(jsonResult = try awsJSONResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(jsonResult?.h, "test-header")
    }

    func testHeaderResponseTypeDecoding() {
        struct Output: AWSDecodableShape {
            static let _encoding = [
                AWSMemberEncoding(label: "string", location: .header(locationName: "string")),
                AWSMemberEncoding(label: "string2", location: .header(locationName: "string2")),
                AWSMemberEncoding(label: "double", location: .header(locationName: "double")),
                AWSMemberEncoding(label: "integer", location: .header(locationName: "integer")),
                AWSMemberEncoding(label: "bool", location: .header(locationName: "bool")),
            ]
            let string: String
            let string2: String
            let double: Double
            let integer: Int
            let bool: Bool
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: [
                "string": "test-header",
                "string2": "23",
                "double": "3.14",
                "integer": "901",
                "bool": "false",
            ]
        )

        // JSON
        var awsJSONResponse: AWSResponse?
        var jsonResult: Output?
        XCTAssertNoThrow(awsJSONResponse = try AWSResponse(from: response, serviceProtocol: .restjson, raw: false))
        XCTAssertNoThrow(jsonResult = try awsJSONResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(jsonResult?.string, "test-header")
        XCTAssertEqual(jsonResult?.string2, "23")
        XCTAssertEqual(jsonResult?.double, 3.14)
        XCTAssertEqual(jsonResult?.integer, 901)
        XCTAssertEqual(jsonResult?.bool, false)
    }

    func testStatusCodeResponseDecoding() {
        struct Output: AWSDecodableShape {
            static let _encoding = [AWSMemberEncoding(label: "status", location: .statusCode)]
            let status: Int
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: nil
        )

        // XML
        var awsXMLResponse: AWSResponse?
        var xmlResult: Output?
        XCTAssertNoThrow(awsXMLResponse = try AWSResponse(from: response, serviceProtocol: .query, raw: false))
        XCTAssertNoThrow(xmlResult = try awsXMLResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(xmlResult?.status, 200)

        // JSON
        var awsJSONResponse: AWSResponse?
        var jsonResult: Output?
        XCTAssertNoThrow(awsJSONResponse = try AWSResponse(from: response, serviceProtocol: .restjson, raw: false))
        XCTAssertNoThrow(jsonResult = try awsJSONResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(jsonResult?.status, 200)
    }

    // MARK: XML tests

    func testValidateXMLResponse() {
        class Output: AWSDecodableShape {
            let name: String
        }
        let responseBody = "<Output><name>hello</name></Output>"
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: Data(responseBody.utf8)
        )

        var awsResponse: AWSResponse?
        var output: Output?
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .restxml, raw: false))
        XCTAssertNoThrow(output = try awsResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.name, "hello")
    }

    func testValidateXMLCodablePayloadResponse() {
        class Output: AWSDecodableShape & AWSShapeWithPayload {
            static let _encoding = [AWSMemberEncoding(label: "contentType", location: .header(locationName: "content-type"))]
            static let _payloadPath: String = "name"
            let name: String
            let contentType: String

            private enum CodingKeys: String, CodingKey {
                case name
                case contentType = "content-type"
            }
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: ["Content-Type": "application/xml"],
            bodyData: "<name>hello</name>".data(using: .utf8)!
        )

        var awsResponse: AWSResponse?
        var output: Output?
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .restxml, raw: false))
        XCTAssertNoThrow(output = try awsResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.name, "hello")
        XCTAssertEqual(output?.contentType, "application/xml")
    }

    func testValidateXMLRawPayloadResponse() {
        class Output: AWSDecodableShape, AWSShapeWithPayload {
            static let _payloadPath: String = "body"
            static let _payloadOptions: AWSShapePayloadOptions = .raw
            let body: AWSPayload
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: Data("{\"name\":\"hello\"}".utf8)
        )

        var awsResponse: AWSResponse?
        var output: Output?
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .restxml, raw: true))
        XCTAssertNoThrow(output = try awsResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.body.asData(), Data("{\"name\":\"hello\"}".utf8))
    }

    // MARK: JSON tests

    func testValidateJSONResponse() {
        class Output: AWSDecodableShape {
            let name: String
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: Data("{\"name\":\"hello\"}".utf8)
        )

        var awsResponse: AWSResponse?
        var output: Output?
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .json(version: "1.1"), raw: false))
        XCTAssertNoThrow(output = try awsResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.name, "hello")
    }

    func testValidateJSONCodablePayloadResponse() {
        class Output2: AWSDecodableShape {
            let name: String
        }
        struct Output: AWSDecodableShape & AWSShapeWithPayload {
            static let _payloadPath: String = "output2"
            let output2: Output2
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: Data("{\"name\":\"hello\"}".utf8)
        )

        var awsResponse: AWSResponse?
        var output: Output?
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .json(version: "1.1"), raw: false))
        XCTAssertNoThrow(output = try awsResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.output2.name, "hello")
    }

    func testValidateJSONRawPayloadResponse() {
        struct Output: AWSDecodableShape, AWSShapeWithPayload {
            static let _payloadPath: String = "body"
            static let _payloadOptions: AWSShapePayloadOptions = .raw
            public static var _encoding = [
                AWSMemberEncoding(label: "contentType", location: .header(locationName: "content-type")),
            ]
            let body: AWSPayload
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: ["Content-Type": "application/json"],
            bodyData: Data("{\"name\":\"hello\"}".utf8)
        )

        var awsResponse: AWSResponse?
        var output: Output?
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .json(version: "1.1"), raw: true))
        XCTAssertNoThrow(output = try awsResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.body.asString(), "{\"name\":\"hello\"}")
    }

    // MARK: Error tests

    func testJSONError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "{\"__type\":\"ResourceNotFoundException\", \"message\": \"Donald Where's Your Troosers?\"}".data(using: .utf8)!
        )
        let service = createServiceConfig(serviceProtocol: .json(version: "1.1"), errorType: ServiceErrorType.self)

        var awsResponse: AWSResponse?
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .json(version: "1.1"), raw: false))
        let error = awsResponse?.generateError(serviceConfig: service, context: TestEnvironment.loggingContext) as? ServiceErrorType
        XCTAssertEqual(error, ServiceErrorType.resourceNotFoundException)
        XCTAssertEqual(error?.message, "Donald Where's Your Troosers?")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
    }

    func testJSONErrorV2() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: #"{"__type":"ResourceNotFoundException", "Message": "Donald Where's Your Troosers?", "fault": "client"}"#.data(using: .utf8)!
        )
        let service = createServiceConfig(serviceProtocol: .json(version: "1.1"), errorType: ServiceErrorType.self)

        var awsResponse: AWSResponse?
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .json(version: "1.1"), raw: false))
        let error = awsResponse?.generateError(serviceConfig: service, context: TestEnvironment.loggingContext) as? ServiceErrorType
        XCTAssertEqual(error, ServiceErrorType.resourceNotFoundException)
        XCTAssertEqual(error?.message, "Donald Where's Your Troosers?")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
        XCTAssertEqual(error?.context?.additionalFields["fault"], "client")
    }

    func testRestJSONError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: ["x-amzn-errortype": "ResourceNotFoundException"],
            bodyData: Data(#"{"message": "Donald Where's Your Troosers?", "Fault": "Client"}"#.utf8)
        )
        let service = createServiceConfig(serviceProtocol: .restjson, errorType: ServiceErrorType.self)

        var awsResponse: AWSResponse?
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .restjson, raw: false))
        let error = awsResponse?.generateError(serviceConfig: service, context: TestEnvironment.loggingContext) as? ServiceErrorType
        XCTAssertEqual(error, ServiceErrorType.resourceNotFoundException)
        XCTAssertEqual(error?.message, "Donald Where's Your Troosers?")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
        XCTAssertEqual(error?.context?.additionalFields["Fault"], "Client")
    }

    func testRestJSONErrorV2() {
        // Capitalized "Message"
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: ["x-amzn-errortype": "ResourceNotFoundException"],
            bodyData: Data(#"{"Message": "Donald Where's Your Troosers?"}"#.utf8)
        )
        let service = createServiceConfig(serviceProtocol: .restjson, errorType: ServiceErrorType.self)

        var awsResponse: AWSResponse?
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .restjson, raw: false))
        let error = awsResponse?.generateError(serviceConfig: service, context: TestEnvironment.loggingContext) as? ServiceErrorType
        XCTAssertEqual(error, ServiceErrorType.resourceNotFoundException)
        XCTAssertEqual(error?.message, "Donald Where's Your Troosers?")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
    }

    func testXMLError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "<Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message><fault>client</fault></Error>".data(using: .utf8)!
        )
        let service = createServiceConfig(serviceProtocol: .restxml, errorType: ServiceErrorType.self)

        var awsResponse: AWSResponse?
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .restxml, raw: false))
        let error = awsResponse?.generateError(serviceConfig: service, context: TestEnvironment.loggingContext) as? ServiceErrorType
        XCTAssertEqual(error, ServiceErrorType.noSuchKey)
        XCTAssertEqual(error?.message, "It doesn't exist")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
        XCTAssertEqual(error?.context?.additionalFields["fault"], "client")
    }

    func testQueryError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "<ErrorResponse><Error><Code>MessageRejected</Code><Message>Don't like it</Message><fault>client</fault></Error></ErrorResponse>".data(using: .utf8)!
        )
        let queryService = createServiceConfig(serviceProtocol: .query, errorType: ServiceErrorType.self)

        var awsResponse: AWSResponse?
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .query, raw: false))
        let error = awsResponse?.generateError(serviceConfig: queryService, context: TestEnvironment.loggingContext) as? ServiceErrorType
        XCTAssertEqual(error, ServiceErrorType.messageRejected)
        XCTAssertEqual(error?.message, "Don't like it")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
        XCTAssertEqual(error?.context?.additionalFields["fault"], "client")
    }

    func testEC2Error() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "<Errors><Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message><fault>client</fault></Error></Errors>".data(using: .utf8)!
        )
        let service = createServiceConfig(serviceProtocol: .ec2)

        var awsResponse: AWSResponse?
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .ec2, raw: false))
        let error = awsResponse?.generateError(serviceConfig: service, context: TestEnvironment.loggingContext) as? AWSResponseError
        XCTAssertEqual(error?.errorCode, "NoSuchKey")
        XCTAssertEqual(error?.message, "It doesn't exist")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
        XCTAssertEqual(error?.context?.additionalFields["fault"], "client")
    }

    func testAdditionalErrorFields() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "<Errors><Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message><fault>client</fault></Error></Errors>".data(using: .utf8)!
        )
        let service = createServiceConfig(serviceProtocol: .restxml)

        var awsResponse: AWSResponse?
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .ec2, raw: false))
        let error = awsResponse?.generateError(serviceConfig: service, context: TestEnvironment.loggingContext) as? AWSResponseError
        XCTAssertEqual(error?.context?.additionalFields["fault"], "client")
    }

    // MARK: Miscellaneous tests

    func testProcessHAL() {
        struct Output: AWSDecodableShape {
            let s: String
            let i: Int
        }
        struct Output2: AWSDecodableShape {
            let a: [Output]
            let d: Double
            let b: Bool
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: ["Content-Type": "application/hal+json"],
            bodyData: Data(#"{"_embedded": {"a": [{"s":"Hello", "i":1234}, {"s":"Hello2", "i":12345}]}, "d":3.14, "b":true}"#.utf8)
        )

        var awsResponse: AWSResponse?
        var output: Output2?
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .json(version: "1.1"), raw: false))
        XCTAssertNoThrow(output = try awsResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.a.count, 2)
        XCTAssertEqual(output?.d, 3.14)
        XCTAssertEqual(output?.a[1].s, "Hello2")
    }

    // MARK: Types used in tests

    struct AWSHTTPResponseImpl: AWSHTTPResponse {
        let status: HTTPResponseStatus
        let headers: HTTPHeaders
        let body: ByteBuffer?

        init(status: HTTPResponseStatus, headers: HTTPHeaders, body: ByteBuffer? = nil) {
            self.status = status
            self.headers = headers
            self.body = body
        }

        init(status: HTTPResponseStatus, headers: HTTPHeaders, bodyData: Data?) {
            var body: ByteBuffer?
            if let bodyData = bodyData {
                body = ByteBufferAllocator().buffer(capacity: bodyData.count)
                body?.writeBytes(bodyData)
            }
            self.init(status: status, headers: headers, body: body)
        }
    }

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
