//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2023 the Soto project authors
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

class AWSResponseTests: XCTestCase {
    func testHeaderResponseDecoding() async throws {
        struct Output: AWSDecodableShape {
            let h: String
            public init(from decoder: Decoder) throws {
                let response = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
                self.h = try response.decode(String.self, forHeader: "header-member")
            }
        }
        let response = AWSHTTPResponse(
            status: .ok,
            headers: ["header-member": "test-header"]
        )

        // XML
        var xmlResult: Output?
        XCTAssertNoThrow(xmlResult = try response.generateOutputShape(operation: "Test", serviceProtocol: .query))
        XCTAssertEqual(xmlResult?.h, "test-header")

        // JSON
        var jsonResult: Output?
        XCTAssertNoThrow(jsonResult = try response.generateOutputShape(operation: "Test", serviceProtocol: .restjson))
        XCTAssertEqual(jsonResult?.h, "test-header")
    }

    func testHeaderResponseTypeDecoding() async throws {
        struct Output: AWSDecodableShape {
            let string: String
            let string2: String
            let double: Double
            let integer: Int
            let bool: Bool

            public init(from decoder: Decoder) throws {
                let response = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
                self.string = try response.decode(String.self, forHeader: "string")
                self.string2 = try response.decode(String.self, forHeader: "string2")
                self.double = try response.decode(Double.self, forHeader: "double")
                self.integer = try response.decode(Int.self, forHeader: "integer")
                self.bool = try response.decode(Bool.self, forHeader: "bool")
            }
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

        // JSON        var awsJSONResponse: response
        var jsonResult: Output?
        XCTAssertNoThrow(jsonResult = try response.generateOutputShape(operation: "Test", serviceProtocol: .restjson))
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
            public init(from decoder: Decoder) throws {
                let response = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
                self.status = response.decodeStatus()
            }
        }
        let response = AWSHTTPResponse(
            status: .ok,
            headers: HTTPHeaders()
        )

        // XML
        var xmlResult: Output?
        XCTAssertNoThrow(xmlResult = try response.generateOutputShape(operation: "Test", serviceProtocol: .query))
        XCTAssertEqual(xmlResult?.status, 200)

        // JSON
        var jsonResult: Output?
        XCTAssertNoThrow(jsonResult = try response.generateOutputShape(operation: "Test", serviceProtocol: .restjson))
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
            body: .init(string: responseBody)
        )

        var output: Output?
        XCTAssertNoThrow(output = try response.generateOutputShape(operation: "Test", serviceProtocol: .restxml))
        XCTAssertEqual(output?.name, "hello")
    }

    func testValidateXMLCodablePayloadResponse() async throws {
        struct Output: AWSDecodableShape {
            let name: String
            let contentType: String

            init(from decoder: Decoder) throws {
                let response = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
                self.contentType = try response.decode(String.self, forHeader: "content-type")
                self.name = try .init(from: decoder)
            }
        }
        let response = AWSHTTPResponse(
            status: .ok,
            headers: ["Content-Type": "application/xml"],
            body: .init(string: "<name>hello</name>")
        )

        var output: Output?
        XCTAssertNoThrow(output = try response.generateOutputShape(operation: "Test", serviceProtocol: .restxml))
        XCTAssertEqual(output?.name, "hello")
        XCTAssertEqual(output?.contentType, "application/xml")
    }

    func testValidateXMLRawPayloadResponse() async throws {
        struct Output: AWSDecodableShape {
            static let _options: AWSShapeOptions = .rawPayload
            let body: AWSHTTPBody

            init(from decoder: Decoder) throws {
                let response = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
                self.body = response.decodePayload()
            }
        }
        let byteBuffer = ByteBuffer(string: "{\"name\":\"hello\"}")
        let response = AWSHTTPResponse(
            status: .ok,
            headers: HTTPHeaders(),
            body: .init(asyncSequence: byteBuffer.asyncSequence(chunkSize: 32), length: nil)
        )

        var _output: Output?
        XCTAssertNoThrow(_output = try response.generateOutputShape(operation: "Test", serviceProtocol: .restxml))
        let output = try XCTUnwrap(_output)
        let responsePayload = try await String(buffer: output.body.collect(upTo: .max))
        XCTAssertEqual(responsePayload, "{\"name\":\"hello\"}")
    }

    // MARK: JSON tests

    func testValidateJSONResponse() async throws {
        struct Output: AWSDecodableShape {
            let name: String
        }
        let response = AWSHTTPResponse(
            status: .ok,
            headers: HTTPHeaders(),
            body: .init(string: "{\"name\":\"hello\"}")
        )

        var output: Output?
        XCTAssertNoThrow(output = try response.generateOutputShape(operation: "Test", serviceProtocol: .json(version: "1.1")))
        XCTAssertEqual(output?.name, "hello")
    }

    func testValidateJSONCodablePayloadResponse() async throws {
        struct Output2: AWSDecodableShape {
            let name: String
        }
        struct Output: AWSDecodableShape {
            let output2: Output2

            init(from decoder: Decoder) throws {
                self.output2 = try .init(from: decoder)
            }
        }
        let response = AWSHTTPResponse(
            status: .ok,
            headers: HTTPHeaders(),
            body: .init(string: "{\"name\":\"hello\"}")
        )

        var output: Output?
        XCTAssertNoThrow(output = try response.generateOutputShape(operation: "Test", serviceProtocol: .json(version: "1.1")))
        XCTAssertEqual(output?.output2.name, "hello")
    }

    func testValidateJSONRawPayloadResponse() async throws {
        struct Output: AWSDecodableShape {
            static let _options: AWSShapeOptions = .rawPayload
            let body: AWSHTTPBody
            init(from decoder: Decoder) throws {
                let response = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
                self.body = response.decodePayload()
            }
        }
        let byteBuffer = ByteBuffer(string: "{\"name\":\"hello\"}")
        let response = AWSHTTPResponse(
            status: .ok,
            headers: ["Content-Type": "application/json"],
            body: .init(asyncSequence: byteBuffer.asyncSequence(chunkSize: 32), length: nil)
        )

        var _output: Output?
        XCTAssertNoThrow(_output = try response.generateOutputShape(operation: "Test", serviceProtocol: .json(version: "1.1")))
        let output = try XCTUnwrap(_output)
        let responsePayload = try await String(buffer: output.body.collect(upTo: .max))
        XCTAssertEqual(responsePayload, "{\"name\":\"hello\"}")
    }

    // MARK: Error tests

    func testJSONError() async throws {
        let response = AWSHTTPResponse(
            status: .notFound,
            headers: HTTPHeaders(),
            body: .init(string: "{\"__type\":\"ResourceNotFoundException\", \"message\": \"Donald Where's Your Troosers?\"}")
        )
        let service = createServiceConfig(serviceProtocol: .json(version: "1.1"), errorType: ServiceErrorType.self)

        let error = response.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? ServiceErrorType
        XCTAssertEqual(error, ServiceErrorType.resourceNotFoundException)
        XCTAssertEqual(error?.message, "Donald Where's Your Troosers?")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
    }

    func testJSONErrorV2() async throws {
        let response = AWSHTTPResponse(
            status: .notFound,
            headers: HTTPHeaders(),
            body: .init(buffer: ByteBuffer(string:
                #"{"__type":"ResourceNotFoundException", "Message": "Donald Where's Your Troosers?", "fault": "client","CancellationReasons":1}"#
            ))
        )
        let service = createServiceConfig(serviceProtocol: .json(version: "1.1"), errorType: ServiceErrorType.self)

        let error = response.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? ServiceErrorType
        XCTAssertEqual(error, ServiceErrorType.resourceNotFoundException)
        XCTAssertEqual(error?.message, "Donald Where's Your Troosers?")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
        XCTAssertEqual(error?.context?.additionalFields["fault"], "client")
    }

    func testRestJSONError() async throws {
        let response = AWSHTTPResponse(
            status: .notFound,
            headers: ["x-amzn-errortype": "ResourceNotFoundException"],
            body: .init(string: #"{"message": "Donald Where's Your Troosers?", "Fault": "Client"}"#)
        )
        let service = createServiceConfig(serviceProtocol: .restjson, errorType: ServiceErrorType.self)

        let error = response.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? ServiceErrorType
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
            body: .init(string: #"{"Message": "Donald Where's Your Troosers?"}"#)
        )
        let service = createServiceConfig(serviceProtocol: .restjson, errorType: ServiceErrorType.self)

        let error = response.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? ServiceErrorType
        XCTAssertEqual(error, ServiceErrorType.resourceNotFoundException)
        XCTAssertEqual(error?.message, "Donald Where's Your Troosers?")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
    }

    func testXMLError() async throws {
        let response = AWSHTTPResponse(
            status: .notFound,
            headers: HTTPHeaders(),
            body: .init(string: "<Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message><fault>client</fault></Error>")
        )
        let service = createServiceConfig(serviceProtocol: .restxml, errorType: ServiceErrorType.self)

        let error = response.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? ServiceErrorType
        XCTAssertEqual(error, ServiceErrorType.noSuchKey)
        XCTAssertEqual(error?.message, "It doesn't exist")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
        XCTAssertEqual(error?.context?.additionalFields["fault"], "client")
    }

    func testQueryError() async throws {
        let response = AWSHTTPResponse(
            status: .notFound,
            headers: HTTPHeaders(),
            body: .init(string: "<ErrorResponse><Error><Code>MessageRejected</Code><Message>Don't like it</Message><fault>client</fault></Error></ErrorResponse>")
        )
        let queryService = createServiceConfig(serviceProtocol: .query, errorType: ServiceErrorType.self)

        let error = response.generateError(serviceConfig: queryService, logger: TestEnvironment.logger) as? ServiceErrorType
        XCTAssertEqual(error, ServiceErrorType.messageRejected)
        XCTAssertEqual(error?.message, "Don't like it")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
        XCTAssertEqual(error?.context?.additionalFields["fault"], "client")
    }

    func testEC2Error() async throws {
        let response = AWSHTTPResponse(
            status: .notFound,
            headers: HTTPHeaders(),
            body: .init(string: "<Errors><Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message><fault>client</fault></Error></Errors>")
        )
        let service = createServiceConfig(serviceProtocol: .ec2)

        let error = response.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? AWSResponseError
        XCTAssertEqual(error?.errorCode, "NoSuchKey")
        XCTAssertEqual(error?.message, "It doesn't exist")
        XCTAssertEqual(error?.context?.responseCode, .notFound)
        XCTAssertEqual(error?.context?.additionalFields["fault"], "client")
    }

    func testAdditionalErrorFields() async throws {
        let response = AWSHTTPResponse(
            status: .notFound,
            headers: HTTPHeaders(),
            body: .init(string: "<Errors><Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message><fault>client</fault></Error></Errors>")
        )
        let service = createServiceConfig(serviceProtocol: .restxml)

        let error = response.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? AWSResponseError
        XCTAssertEqual(error?.context?.additionalFields["fault"], "client")
    }

    func testHeaderPrefixFromDictionary() async throws {
        struct Output: AWSDecodableShape {
            static let _encoding: [AWSMemberEncoding] = [
                .init(label: "content", location: .headerPrefix("prefix-")),
            ]
            let content: [String: String]?

            public init(from decoder: Decoder) throws {
                let response = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
                self.content = try response.decodeIfPresent([String: String].self, forHeader: "prefix-")
            }
        }
        let response = AWSHTTPResponse(
            status: .ok,
            headers: ["prefix-one": "first", "prefix-two": "second"]
        )
        var output: Output?
        XCTAssertNoThrow(output = try response.generateOutputShape(operation: "Test", serviceProtocol: .restxml))
        XCTAssertEqual(output?.content?["one"], "first")
        XCTAssertEqual(output?.content?["two"], "second")
    }

    func testHeaderPrefixFromXML() async throws {
        struct Output: AWSDecodableShape {
            let content: [String: String]?
            let body: String

            public init(from decoder: Decoder) throws {
                let response = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.content = try response.decodeIfPresent([String: String].self, forHeader: "prefix-")
                self.body = try container.decode(String.self, forKey: .body)
            }

            private enum CodingKeys: String, CodingKey {
                case body
            }
        }
        let response = AWSHTTPResponse(
            status: .ok,
            headers: ["prefix-one": "first", "prefix-two": "second"],
            body: .init(string: "<Output><body>Hello</body></Output>")
        )
        var output: Output?
        XCTAssertNoThrow(output = try response.generateOutputShape(operation: "Test", serviceProtocol: .restxml))
        XCTAssertEqual(output?.content?["one"], "first")
        XCTAssertEqual(output?.content?["two"], "second")
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
            body: .init(string: #"{"_embedded": {"a": [{"s":"Hello", "i":1234}, {"s":"Hello2", "i":12345}]}, "d":3.14, "b":true}"#)
        )

        var output: Output2?
        XCTAssertNoThrow(output = try response.generateOutputShape(operation: "Test", serviceProtocol: .json(version: "1.1")))
        XCTAssertEqual(output?.a.count, 2)
        XCTAssertEqual(output?.d, 3.14)
        XCTAssertEqual(output?.a[1].s, "Hello2")
    }

    /// Write event stream event
    func writeEvent(headers: [String: String], payload: ByteBuffer, to: inout ByteBuffer) {
        var payload = payload
        let messageStartIndex = to.writerIndex
        // skip prelude
        to.writeRepeatingByte(0, count: 12)
        // get writer index
        let headerStartIndex = to.writerIndex
        for header in headers {
            to.writeInteger(UInt8(header.key.utf8.count))
            to.writeString(header.key)
            to.writeInteger(UInt8(7)) // header type (always 7)
            to.writeInteger(UInt16(header.value.utf8.count))
            to.writeString(header.value)
        }
        let headerLength = to.writerIndex - headerStartIndex
        to.writeBuffer(&payload)

        let totalLength = to.writerIndex - messageStartIndex

        // write prelude
        to.setInteger(UInt32(totalLength + 4), at: messageStartIndex)
        to.setInteger(UInt32(headerLength), at: messageStartIndex + 4)
        let preludeCRC = soto_crc32(0, bytes: ByteBufferView(to.getSlice(at: messageStartIndex, length: 8)!))
        to.setInteger(UInt32(preludeCRC), at: messageStartIndex + 8)

        let messageCRC = soto_crc32(0, bytes: ByteBufferView(to.getSlice(at: messageStartIndex, length: totalLength)!))
        to.writeInteger(UInt32(messageCRC))
    }

    enum TestEventStream: AWSDecodableShape {
        struct EmptyEvent: AWSDecodableShape {}
        struct PayloadEvent: AWSDecodableShape {
            let payload: AWSEventPayload

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                self.payload = try container.decode(AWSEventPayload.self)
            }
        }

        struct ShapeEvent: AWSDecodableShape, Encodable, Equatable {
            let string: String
            let integer: Int
        }

        /// Empty Event.
        case empty(EmptyEvent)
        /// Event with raw payload.
        case payload(PayloadEvent)
        /// Event with codable payload.
        case shape(ShapeEvent)

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.allKeys.count == 1, let key = container.allKeys.first else {
                let context = DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Expected exactly one key, but got \(container.allKeys.count)"
                )
                throw DecodingError.dataCorrupted(context)
            }
            switch key {
            case .empty:
                let value = try container.decode(EmptyEvent.self, forKey: .empty)
                self = .empty(value)
            case .payload:
                let value = try container.decode(PayloadEvent.self, forKey: .payload)
                self = .payload(value)
            case .shape:
                let value = try container.decode(ShapeEvent.self, forKey: .shape)
                self = .shape(value)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case empty = "Empty"
            case payload = "Payload"
            case shape = "Shape"
        }
    }

    func testEventStreamDecoder() throws {
        // test empty buffer
        var eventByteBuffer = ByteBuffer()
        let emptyHeaders = [":event-type": "Empty"]
        self.writeEvent(headers: emptyHeaders, payload: ByteBuffer(), to: &eventByteBuffer)
        let emptyResult = try EventStreamDecoder().decode(TestEventStream.self, from: &eventByteBuffer)
        if case .empty = emptyResult {
        } else {
            XCTFail()
        }
        // test payload buffer
        let payloadHeaders = [":event-type": "Payload", ":content-type": "application/octet-stream"]
        let payloadBuffer = ByteBuffer(staticString: "Testing payloads")
        self.writeEvent(headers: payloadHeaders, payload: payloadBuffer, to: &eventByteBuffer)
        let payloadResult = try EventStreamDecoder().decode(TestEventStream.self, from: &eventByteBuffer)
        if case .payload(let payload) = payloadResult {
            XCTAssertEqual(payload.payload.buffer, payloadBuffer)
        } else {
            XCTFail()
        }
        // test JSON buffer
        let jsonHeaders = [":event-type": "Shape", ":content-type": "application/json"]
        let shape = TestEventStream.ShapeEvent(string: "Testing", integer: 590)
        let jsonPayload = try JSONEncoder().encodeAsByteBuffer(shape, allocator: ByteBufferAllocator())
        self.writeEvent(headers: jsonHeaders, payload: jsonPayload, to: &eventByteBuffer)
        let jsonResult = try EventStreamDecoder().decode(TestEventStream.self, from: &eventByteBuffer)
        if case .shape(let shapeResult) = jsonResult {
            XCTAssertEqual(shapeResult, shape)
        } else {
            XCTFail()
        }
        // test XML buffer
        let xmlHeaders = [":event-type": "Shape", ":content-type": "text/xml"]
        let xml = try XMLEncoder().encode(shape)
        let xmlPayload = xml.map { ByteBuffer(string: $0.xmlString) } ?? .init()
        self.writeEvent(headers: xmlHeaders, payload: xmlPayload, to: &eventByteBuffer)
        let xmlResult = try EventStreamDecoder().decode(TestEventStream.self, from: &eventByteBuffer)
        if case .shape(let shapeResult) = xmlResult {
            XCTAssertEqual(shapeResult, shape)
        } else {
            XCTFail()
        }
    }

    func testEventStreamStreamer() async throws {
        var eventByteBuffer = ByteBuffer()
        let emptyHeaders = [":event-type": "Empty"]
        self.writeEvent(headers: emptyHeaders, payload: ByteBuffer(), to: &eventByteBuffer)
        let payloadHeaders = [":event-type": "Payload", ":content-type": "application/octet-stream"]
        let payloadBuffer = ByteBuffer(staticString: "Testing payloads")
        self.writeEvent(headers: payloadHeaders, payload: payloadBuffer, to: &eventByteBuffer)
        let jsonHeaders = [":event-type": "Shape", ":content-type": "application/json"]
        let shape = TestEventStream.ShapeEvent(string: "Testing", integer: 590)
        let jsonPayload = try JSONEncoder().encodeAsByteBuffer(shape, allocator: ByteBufferAllocator())
        self.writeEvent(headers: jsonHeaders, payload: jsonPayload, to: &eventByteBuffer)

        let eventStream = AWSEventStream<TestEventStream>(eventByteBuffer.asyncSequence(chunkSize: 65))
        var eventIterator = eventStream.makeAsyncIterator()
        let emptyResult = try await eventIterator.next()
        if case .empty = emptyResult {
        } else {
            XCTFail()
        }
        let payloadResult = try await eventIterator.next()
        if case .payload(let payload) = payloadResult {
            XCTAssertEqual(payload.payload.buffer, payloadBuffer)
        } else {
            XCTFail()
        }
        let jsonResult = try await eventIterator.next()
        if case .shape(let shapeResult) = jsonResult {
            XCTAssertEqual(shapeResult, shape)
        } else {
            XCTFail()
        }
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
