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

import Foundation
import HTTPTypes
import NIOCore
import NIOFoundationEssentialsCompat
import SotoTestUtils
import SotoXML
import Testing

@testable @_spi(SotoInternal) import SotoCore

class AWSResponseTests {
    @Test func testHeaderResponseDecoding() async throws {
        struct Output: AWSDecodableShape {
            let h: String
            public init(from decoder: any Decoder) throws {
                let response = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
                self.h = try response.decodeHeader(String.self, key: "header-member")
            }
        }
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .ok, headerFields: [HTTPField.Name("header-member")!: "test-header"])
        )

        // XML
        var xmlResult: Output?
        #expect(throws: Never.self) { xmlResult = try response.generateOutputShape(operation: "Test", serviceProtocol: .query) }
        #expect(xmlResult?.h == "test-header")

        // JSON
        var jsonResult: Output?
        #expect(throws: Never.self) { jsonResult = try response.generateOutputShape(operation: "Test", serviceProtocol: .restjson) }
        #expect(jsonResult?.h == "test-header")
    }

    @Test func testHeaderResponseTypeDecoding() async throws {
        struct Output: AWSDecodableShape {
            let string: String
            let string2: String
            let double: Double
            let integer: Int
            let bool: Bool

            public init(from decoder: any Decoder) throws {
                let response = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
                self.string = try response.decodeHeader(String.self, key: "string")
                self.string2 = try response.decodeHeader(String.self, key: "string2")
                self.double = try response.decodeHeader(Double.self, key: "double")
                self.integer = try response.decodeHeader(Int.self, key: "integer")
                self.bool = try response.decodeHeader(Bool.self, key: "bool")
            }
        }
        let response = AWSHTTPResponse(
            response: HTTPResponse(
                status: .ok,
                headerFields: [
                    HTTPField.Name("string")!: "test-header",
                    HTTPField.Name("string2")!: "23",
                    HTTPField.Name("double")!: "3.14",
                    HTTPField.Name("integer")!: "901",
                    HTTPField.Name("bool")!: "false",
                ]
            )
        )

        // JSON        var awsJSONResponse: response
        var jsonResult: Output?
        #expect(throws: Never.self) { jsonResult = try response.generateOutputShape(operation: "Test", serviceProtocol: .restjson) }
        #expect(jsonResult?.string == "test-header")
        #expect(jsonResult?.string2 == "23")
        #expect(jsonResult?.double == 3.14)
        #expect(jsonResult?.integer == 901)
        #expect(jsonResult?.bool == false)
    }

    @Test func testHeaderResponseEnumDecoding() async throws {
        enum TestEnum: String, Decodable {
            case hello
            case goodbye
        }
        struct Output: AWSDecodableShape {
            let test: TestEnum

            public init(from decoder: any Decoder) throws {
                let response = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
                self.test = try response.decodeHeader(TestEnum.self, key: "testEnum")
            }
        }
        let response = AWSHTTPResponse(
            response: HTTPResponse(
                status: .ok,
                headerFields: [
                    HTTPField.Name("testEnum")!: "hello"
                ]
            )
        )

        var jsonResult: Output?
        #expect(throws: Never.self) { jsonResult = try response.generateOutputShape(operation: "Test", serviceProtocol: .restjson) }
        #expect(jsonResult?.test == .hello)
    }

    @Test func testStatusCodeResponseDecoding() async throws {
        struct Output: AWSDecodableShape {
            let status: Int
            public init(from decoder: any Decoder) throws {
                let response = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
                self.status = response.decodeStatus()
            }
        }
        let response = AWSHTTPResponse(response: HTTPResponse(status: .ok))

        // XML
        var xmlResult: Output?
        #expect(throws: Never.self) { xmlResult = try response.generateOutputShape(operation: "Test", serviceProtocol: .query) }
        #expect(xmlResult?.status == 200)

        // JSON
        var jsonResult: Output?
        #expect(throws: Never.self) { jsonResult = try response.generateOutputShape(operation: "Test", serviceProtocol: .restjson) }
        #expect(jsonResult?.status == 200)
    }

    // MARK: XML tests

    @Test func testValidateXMLResponse() async throws {
        struct Output: AWSDecodableShape {
            let name: String
        }
        let responseBody = "<Output><name>hello</name></Output>"
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .ok),
            body: .init(string: responseBody)
        )

        var output: Output?
        #expect(throws: Never.self) { output = try response.generateOutputShape(operation: "Test", serviceProtocol: .restxml) }
        #expect(output?.name == "hello")
    }

    @Test func testValidateXMLCodablePayloadResponse() async throws {
        struct Output: AWSDecodableShape {
            let name: String
            let contentType: String

            init(from decoder: any Decoder) throws {
                let response = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
                self.contentType = try response.decodeHeader(String.self, key: "content-type")
                self.name = try .init(from: decoder)
            }
        }
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .ok, headerFields: [.contentType: "application/xml"]),
            body: .init(string: "<name>hello</name>")
        )

        var output: Output?
        #expect(throws: Never.self) { output = try response.generateOutputShape(operation: "Test", serviceProtocol: .restxml) }
        #expect(output?.name == "hello")
        #expect(output?.contentType == "application/xml")
    }

    @Test func testValidateXMLRawPayloadResponse() async throws {
        struct Output: AWSDecodableShape {
            static let _options: AWSShapeOptions = .rawPayload
            let body: AWSHTTPBody

            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                self.body = try container.decode(AWSHTTPBody.self)
            }
        }
        let byteBuffer = ByteBuffer(string: "{\"name\":\"hello\"}")
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .ok),
            body: .init(asyncSequence: byteBuffer.asyncSequence(chunkSize: 32), length: nil)
        )

        var _output: Output?
        #expect(throws: Never.self) { _output = try response.generateOutputShape(operation: "Test", serviceProtocol: .restxml) }
        let output = try #require(_output)
        let responsePayload = try await String(buffer: output.body.collect(upTo: .max))
        #expect(responsePayload == "{\"name\":\"hello\"}")
    }

    // MARK: JSON tests

    @Test func testValidateJSONResponse() async throws {
        struct Output: AWSDecodableShape {
            let name: String
        }
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .ok),
            body: .init(string: "{\"name\":\"hello\"}")
        )

        var output: Output?
        #expect(throws: Never.self) { output = try response.generateOutputShape(operation: "Test", serviceProtocol: .json(version: "1.1")) }
        #expect(output?.name == "hello")
    }

    @Test func testValidateJSONCodablePayloadResponse() async throws {
        struct Output2: AWSDecodableShape {
            let name: String
        }
        struct Output: AWSDecodableShape {
            let output2: Output2

            init(from decoder: any Decoder) throws {
                self.output2 = try .init(from: decoder)
            }
        }
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .ok),
            body: .init(string: "{\"name\":\"hello\"}")
        )

        var output: Output?
        #expect(throws: Never.self) { output = try response.generateOutputShape(operation: "Test", serviceProtocol: .json(version: "1.1")) }
        #expect(output?.output2.name == "hello")
    }

    @Test func testValidateJSONRawPayloadResponse() async throws {
        struct Output: AWSDecodableShape {
            static let _options: AWSShapeOptions = .rawPayload
            let body: AWSHTTPBody
            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                self.body = try container.decode(AWSHTTPBody.self)
            }
        }
        let byteBuffer = ByteBuffer(string: "{\"name\":\"hello\"}")
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
            body: .init(asyncSequence: byteBuffer.asyncSequence(chunkSize: 32), length: nil)
        )

        var _output: Output?
        #expect(throws: Never.self) { _output = try response.generateOutputShape(operation: "Test", serviceProtocol: .json(version: "1.1")) }
        let output = try #require(_output)
        let responsePayload = try await String(buffer: output.body.collect(upTo: .max))
        #expect(responsePayload == "{\"name\":\"hello\"}")
    }

    // MARK: Error tests

    @Test func testJSONError() async throws {
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .notFound),
            body: .init(string: "{\"__type\":\"ResourceNotFoundException\", \"message\": \"Donald Where's Your Troosers?\"}")
        )
        let service = createServiceConfig(serviceProtocol: .json(version: "1.1"), errorType: ServiceErrorType.self)

        let error = response.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? ServiceErrorType
        switch error?.error {
        case .resourceNotFoundException:
            break
        default:
            Issue.record()
        }
        #expect(error?.message == "Donald Where's Your Troosers?")
    }

    @Test func testJSONErrorWithoutMessage() async throws {
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .notFound),
            body: .init(string: "{\"__type\":\"ResourceNotFoundException\"}")
        )
        let service = createServiceConfig(serviceProtocol: .json(version: "1.1"), errorType: ServiceErrorType.self)

        let error = response.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? ServiceErrorType
        switch error?.error {
        case .resourceNotFoundException:
            break
        default:
            Issue.record()
        }
    }

    @Test func testJSONErrorV2() async throws {
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .notFound),
            body: .init(
                buffer: ByteBuffer(
                    string:
                        #"{"__type":"ResourceNotFoundException", "Message": "Donald Where's Your Troosers?", "fault": "client","CancellationReasons":1}"#
                )
            )
        )
        let service = createServiceConfig(serviceProtocol: .json(version: "1.1"), errorType: ServiceErrorType.self)

        let error = response.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? ServiceErrorType
        switch error?.error {
        case .resourceNotFoundException:
            break
        default:
            Issue.record()
        }
        #expect(error?.message == "Donald Where's Your Troosers?")
    }

    @Test func testRestJSONError() async throws {
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .notFound, headerFields: [.xAmznErrorType: "ResourceNotFoundException"]),
            body: .init(string: #"{"message": "Donald Where's Your Troosers?", "Fault": "Client"}"#)
        )
        let service = createServiceConfig(serviceProtocol: .restjson, errorType: ServiceErrorType.self)

        let error = response.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? ServiceErrorType
        switch error?.error {
        case .resourceNotFoundException:
            break
        default:
            Issue.record()
        }
        #expect(error?.message == "Donald Where's Your Troosers?")
    }

    @Test func testRestJSONErrorV2() async throws {
        // Capitalized "Message"
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .notFound, headerFields: [.xAmznErrorType: "ResourceNotFoundException"]),
            body: .init(string: #"{"Message": "Donald Where's Your Troosers?"}"#)
        )
        let service = createServiceConfig(serviceProtocol: .restjson, errorType: ServiceErrorType.self)

        let error = response.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? ServiceErrorType
        switch error?.error {
        case .resourceNotFoundException:
            break
        default:
            Issue.record()
        }
        #expect(error?.message == "Donald Where's Your Troosers?")
    }

    @Test func testXMLError() async throws {
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .notFound),
            body: .init(string: "<Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message><fault>client</fault></Error>")
        )
        let service = createServiceConfig(serviceProtocol: .restxml, errorType: ServiceErrorType.self)

        let error = response.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? ServiceErrorType
        switch error?.error {
        case .noSuchKey:
            break
        default:
            Issue.record()
        }
        #expect(error?.message == "It doesn't exist")
    }

    @Test func testQueryError() async throws {
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .notFound),
            body: .init(
                string:
                    "<ErrorResponse><Error><Code>MessageRejected</Code><Message>Don't like it</Message><fault>client</fault></Error></ErrorResponse>"
            )
        )
        let queryService = createServiceConfig(serviceProtocol: .query, errorType: ServiceErrorType.self)

        let error = response.generateError(serviceConfig: queryService, logger: TestEnvironment.logger) as? ServiceErrorType
        switch error?.error {
        case .messageRejected(let context):
            #expect(context.fault == "client")
        default:
            Issue.record()
        }
    }

    @Test func testEC2Error() async throws {
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .notFound),
            body: .init(string: "<Errors><Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message><fault>client</fault></Error></Errors>")
        )
        let service = createServiceConfig(serviceProtocol: .ec2)

        let error = response.generateError(serviceConfig: service, logger: TestEnvironment.logger) as? AWSResponseError
        #expect(error?.errorCode == "NoSuchKey")
        #expect(error?.message == "It doesn't exist")
    }

    @Test func testHeaderPrefixFromDictionary() async throws {
        struct Output: AWSDecodableShape {
            let content: [String: String]?

            public init(from decoder: any Decoder) throws {
                let response = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
                self.content = try response.decodeHeaderIfPresent([String: String].self, key: "prefix-")
            }
        }
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .ok, headerFields: [HTTPField.Name("prefix-one")!: "first", HTTPField.Name("prefix-two")!: "second"]),
        )
        var output: Output?
        #expect(throws: Never.self) { output = try response.generateOutputShape(operation: "Test", serviceProtocol: .restxml) }
        #expect(output?.content?["one"] == "first")
        #expect(output?.content?["two"] == "second")
    }

    @Test func testHeaderPrefixFromXML() async throws {
        struct Output: AWSDecodableShape {
            let content: [String: String]?
            let body: String

            public init(from decoder: any Decoder) throws {
                let response = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.content = try response.decodeHeaderIfPresent([String: String].self, key: "prefix-")
                self.body = try container.decode(String.self, forKey: .body)
            }

            private enum CodingKeys: String, CodingKey {
                case body
            }
        }
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .ok, headerFields: [HTTPField.Name("prefix-one")!: "first", HTTPField.Name("prefix-two")!: "second"]),
            body: .init(string: "<Output><body>Hello</body></Output>")
        )
        var output: Output?
        #expect(throws: Never.self) { output = try response.generateOutputShape(operation: "Test", serviceProtocol: .restxml) }
        #expect(output?.content?["one"] == "first")
        #expect(output?.content?["two"] == "second")
    }

    // MARK: Miscellaneous tests

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
            to.writeInteger(UInt8(7))  // header type (always 7)
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

            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                self.payload = try container.decode(AWSEventPayload.self)
            }
        }

        struct HeaderEvent: AWSDecodableShape {
            let test: String
            let test2: String?

            init(from decoder: any Decoder) throws {
                let response = decoder.userInfo[.awsEvent]! as! EventDecodingContainer
                self.test = try response.decodeHeader(key: "test")
                self.test2 = try response.decodeHeaderIfPresent(key: "test2")
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
        /// Exception event with codable payload.
        case exception(ShapeEvent)
        /// Exception event with codable payload.
        case header(HeaderEvent)

        public init(from decoder: any Decoder) throws {
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
            case .exception:
                let value = try container.decode(ShapeEvent.self, forKey: .exception)
                self = .exception(value)
            case .header:
                let value = try container.decode(HeaderEvent.self, forKey: .header)
                self = .header(value)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case empty = "Empty"
            case payload = "Payload"
            case shape = "Shape"
            case exception = "ShapeException"
            case header = "Header"
        }
    }

    @Test func testEventStreamDecoder() throws {
        // test empty buffer
        var eventByteBuffer = ByteBuffer()
        let emptyHeaders = [":message-type": "event", ":event-type": "Empty"]
        self.writeEvent(headers: emptyHeaders, payload: ByteBuffer(), to: &eventByteBuffer)
        let emptyResult = try EventStreamDecoder().decode(TestEventStream.self, from: &eventByteBuffer)
        if case .empty = emptyResult {
        } else {
            Issue.record()
        }
        // test payload buffer
        let payloadHeaders = [":message-type": "event", ":event-type": "Payload", ":content-type": "application/octet-stream"]
        let payloadBuffer = ByteBuffer(staticString: "Testing payloads")
        self.writeEvent(headers: payloadHeaders, payload: payloadBuffer, to: &eventByteBuffer)
        let payloadResult = try EventStreamDecoder().decode(TestEventStream.self, from: &eventByteBuffer)
        if case .payload(let payload) = payloadResult {
            #expect(payload.payload.buffer == payloadBuffer)
        } else {
            Issue.record()
        }
        // test event header
        let headerHeaders = [":message-type": "event", ":event-type": "Header", ":content-type": "application/octet-stream", "test": "Hello"]
        self.writeEvent(headers: headerHeaders, payload: ByteBuffer(), to: &eventByteBuffer)
        let headerResult = try EventStreamDecoder().decode(TestEventStream.self, from: &eventByteBuffer)
        if case .header(let header) = headerResult {
            #expect(header.test == "Hello")
            #expect(header.test2 == nil)
        } else {
            Issue.record()
        }
        // test JSON buffer
        let jsonHeaders = [":message-type": "event", ":event-type": "Shape", ":content-type": "application/json"]
        let shape = TestEventStream.ShapeEvent(string: "Testing", integer: 590)
        let jsonPayload = try JSONEncoder().encodeAsByteBuffer(shape, allocator: ByteBufferAllocator())
        self.writeEvent(headers: jsonHeaders, payload: jsonPayload, to: &eventByteBuffer)
        let jsonResult = try EventStreamDecoder().decode(TestEventStream.self, from: &eventByteBuffer)
        if case .shape(let shapeResult) = jsonResult {
            #expect(shapeResult == shape)
        } else {
            Issue.record()
        }
        // test XML buffer
        let xmlHeaders = [":message-type": "event", ":event-type": "Shape", ":content-type": "text/xml"]
        let xml = try XMLEncoder().encode(shape)
        let xmlPayload = xml.map { ByteBuffer(string: $0.xmlString) } ?? .init()
        self.writeEvent(headers: xmlHeaders, payload: xmlPayload, to: &eventByteBuffer)
        let xmlResult = try EventStreamDecoder().decode(TestEventStream.self, from: &eventByteBuffer)
        if case .shape(let shapeResult) = xmlResult {
            #expect(shapeResult == shape)
        } else {
            Issue.record()
        }
    }

    @Test func testEventStreamStreamer() async throws {
        var eventByteBuffer = ByteBuffer()
        let emptyHeaders = [":message-type": "event", ":event-type": "Empty"]
        self.writeEvent(headers: emptyHeaders, payload: ByteBuffer(), to: &eventByteBuffer)
        let payloadHeaders = [":message-type": "event", ":event-type": "Payload", ":content-type": "application/octet-stream"]
        let payloadBuffer = ByteBuffer(staticString: "Testing payloads")
        self.writeEvent(headers: payloadHeaders, payload: payloadBuffer, to: &eventByteBuffer)
        let jsonHeaders = [":message-type": "event", ":event-type": "Shape", ":content-type": "application/json"]
        let shape = TestEventStream.ShapeEvent(string: "Testing", integer: 590)
        let jsonPayload = try JSONEncoder().encodeAsByteBuffer(shape, allocator: ByteBufferAllocator())
        self.writeEvent(headers: jsonHeaders, payload: jsonPayload, to: &eventByteBuffer)

        let eventStream = AWSEventStream<TestEventStream>(eventByteBuffer.asyncSequence(chunkSize: 65))
        var eventIterator = eventStream.makeAsyncIterator()
        let emptyResult = try await eventIterator.next()
        if case .empty = emptyResult {
        } else {
            Issue.record()
        }
        let payloadResult = try await eventIterator.next()
        if case .payload(let payload) = payloadResult {
            #expect(payload.payload.buffer == payloadBuffer)
        } else {
            Issue.record()
        }
        let jsonResult = try await eventIterator.next()
        if case .shape(let shapeResult) = jsonResult {
            #expect(shapeResult == shape)
        } else {
            Issue.record()
        }
    }

    @Test func testEventStreamException() async throws {
        let exceptionHeaders = [":message-type": "exception", ":exception-type": "ShapeException", ":content-type": "application/json"]
        let shape = TestEventStream.ShapeEvent(string: "Testing", integer: 590)
        let jsonPayload = try JSONEncoder().encodeAsByteBuffer(shape, allocator: ByteBufferAllocator())
        var eventByteBuffer = ByteBuffer()
        self.writeEvent(headers: exceptionHeaders, payload: jsonPayload, to: &eventByteBuffer)

        let jsonResult = try EventStreamDecoder().decode(TestEventStream.self, from: &eventByteBuffer)
        if case .exception(let shapeResult) = jsonResult {
            #expect(shapeResult == shape)
        } else {
            Issue.record()
        }
    }

    @Test func testEventStreamError() async throws {
        let errorHeaders = [":message-type": "error", ":error-code": "FooError", ":error-message": "Foo encountered an error"]
        var eventByteBuffer = ByteBuffer()
        self.writeEvent(headers: errorHeaders, payload: .init(), to: &eventByteBuffer)

        #expect(throws: AWSEventStreamError.self) {
            try EventStreamDecoder().decode(TestEventStream.self, from: &eventByteBuffer)
        }
    }

    @Test func testDocument() throws {
        struct Output: AWSDecodableShape {
            let doc: AWSDocument
        }
        var output: Output = try AWSHTTPResponse(response: HTTPResponse(status: .ok), body: .init(string: #"{"doc":"hello"}"#))
            .generateOutputShape(operation: "Test", serviceProtocol: .json(version: "1.1"))
        #expect(output.doc == "hello")
        output = try AWSHTTPResponse(response: HTTPResponse(status: .ok), body: .init(string: #"{"doc":867}"#))
            .generateOutputShape(operation: "Test", serviceProtocol: .json(version: "1.1"))
        #expect(output.doc == 867)
        output = try AWSHTTPResponse(response: HTTPResponse(status: .ok), body: .init(string: #"{"doc":867.5}"#))
            .generateOutputShape(operation: "Test", serviceProtocol: .json(version: "1.1"))
        #expect(output.doc == 867.5)
        output = try AWSHTTPResponse(response: HTTPResponse(status: .ok), body: .init(string: #"{"doc":true}"#))
            .generateOutputShape(operation: "Test", serviceProtocol: .json(version: "1.1"))
        #expect(output.doc == true)
        output = try AWSHTTPResponse(response: HTTPResponse(status: .ok), body: .init(string: #"{"doc":["hello", "world"]}"#))
            .generateOutputShape(operation: "Test", serviceProtocol: .json(version: "1.1"))
        #expect(output.doc == ["hello", "world"])
        output = try AWSHTTPResponse(response: HTTPResponse(status: .ok), body: .init(string: #"{"doc":{"hello":"world"}}"#))
            .generateOutputShape(operation: "Test", serviceProtocol: .json(version: "1.1"))
        #expect(output.doc == ["hello": "world"])
    }

    // MARK: Types used in tests

    struct ServiceErrorType: AWSErrorType, Decodable {
        enum ErrorContents {
            case resourceNotFoundException
            case noSuchKey
            case messageRejected(MessageRejected)
        }
        struct MessageRejected: Decodable {
            let fault: String?
        }

        let error: ErrorContents
        let message: String?
        let response: HTTPResponse?

        init(from decoder: any Decoder) throws {
            let singleValueContainer = try decoder.singleValueContainer()
            let error = try singleValueContainer.decode(AWSResponseError.self)
            switch error.errorCode {
            case "ResourceNotFoundException":
                self.error = .resourceNotFoundException
            case "NoSuchKey":
                self.error = .noSuchKey
            case "MessageRejected":
                let context = try singleValueContainer.decode(MessageRejected.self)
                self.error = .messageRejected(context)
            default:
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unrecognised error code"))
            }
            self.message = error.message
            self.response = error.response
        }

        var errorCode: String {
            switch self.error {
            case .resourceNotFoundException: "ResourceNotFoundException"
            case .noSuchKey: "NoSuchKey"
            case .messageRejected: "MessageRejected"
            }
        }
    }
}
