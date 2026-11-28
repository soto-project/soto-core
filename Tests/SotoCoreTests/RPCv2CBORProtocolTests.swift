//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import CBOR
import HTTPTypes
import NIOCore
import SotoTestUtils
import Testing

@testable @_spi(SotoInternal) import SotoCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite("RPC v2 CBOR protocol")
struct RPCv2CBORProtocolTests {
    struct Input: AWSEncodableShape, Decodable {
        let name: String
        let count: Int
    }

    /// Shape that would normally pull members out of the body into headers, query and path
    struct BoundInput: AWSEncodableShape, Decodable {
        let name: String
        let headerMember: String
        let queryMember: String

        private enum CodingKeys: String, CodingKey {
            case name
            case headerMember
            case queryMember
        }

        func encode(to encoder: any Encoder) throws {
            let request = try encoder.requireAWSRequestContainer()
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.name, forKey: .name)
            try container.encode(self.headerMember, forKey: .headerMember)
            try container.encode(self.queryMember, forKey: .queryMember)
            request.encodeHeader(self.headerMember, key: "x-bound-header")
            request.encodeQuery(self.queryMember, key: "boundQuery")
        }
    }

    /// Shape with a host label member, which fills in the endpoint prefix and is also sent in the body
    struct HostLabelInput: AWSEncodableShape {
        let accountId: String

        private enum CodingKeys: String, CodingKey {
            case accountId
        }

        func encode(to encoder: any Encoder) throws {
            let request = try encoder.requireAWSRequestContainer()
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.accountId, forKey: .accountId)
            request.encodeHostPrefix(self.accountId, key: "accountId")
        }
    }

    /// Shape whose payload is a raw body, which the CBOR protocol cannot carry
    struct RawPayloadInput: AWSEncodableShape {
        let payload: AWSHTTPBody

        func encode(to encoder: any Encoder) throws {
            try self.payload.encode(to: encoder)
        }
    }

    /// Shape with a raw body nested as a member, as opposed to the shape's own payload
    struct NestedRawPayloadInput: AWSEncodableShape {
        let payload: AWSHTTPBody

        private enum CodingKeys: String, CodingKey {
            case payload
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.payload, forKey: .payload)
        }
    }

    struct Output: AWSDecodableShape, Encodable {
        let name: String?
        let count: Int?
    }

    struct ErrorBody: Encodable {
        let __type: String
        let message: String?
    }

    struct CapitalMessageErrorBody: Encodable {
        let __type: String
        let Message: String
    }

    struct ServiceError: AWSErrorType, Decodable {
        enum Kind {
            case resourceNotFound
        }
        let kind: Kind
        let message: String?
        let response: HTTPResponse?

        init(from decoder: any Decoder) throws {
            let error = try decoder.singleValueContainer().decode(AWSResponseError.self)
            switch error.errorCode {
            case "ResourceNotFound":
                self.kind = .resourceNotFound
            default:
                throw error
            }
            self.message = error.message
            self.response = error.response
        }

        var errorCode: String { "ResourceNotFound" }
    }

    static let serviceProtocol = ServiceProtocol.rpcv2Cbor(serviceName: "TestService")

    static func cborBody<T: Encodable>(_ value: T) throws -> AWSHTTPBody {
        .init(buffer: ByteBuffer(bytes: try CBOREncoder().encode(value)))
    }

    // MARK: Protocol

    @Test func contentType() {
        #expect(Self.serviceProtocol.contentType == "application/cbor")
    }

    // MARK: Request

    @Test func requestHeadersPathAndBody() throws {
        let config = createServiceConfig(region: .useast1, service: "test", serviceProtocol: Self.serviceProtocol)
        let request = try AWSHTTPRequest(
            operation: "GetThing",
            path: "/",
            method: .post,
            input: Input(name: "hello", count: 3),
            configuration: config
        )
        #expect(request.method == .post)
        #expect(request.request.url?.absoluteString == "https://test.us-east-1.amazonaws.com/service/TestService/operation/GetThing")
        #expect(request.headers[.init("Smithy-Protocol")!] == "rpc-v2-cbor")
        #expect(request.headers[.accept] == "application/cbor")
        #expect(request.headers[.contentType] == "application/cbor")

        guard case .byteBuffer(let buffer) = request.body.storage else {
            Issue.record("Expected a byte buffer body")
            return
        }
        let decoded = try CBORDecoder().decode(Input.self, from: Array(buffer.readableBytesView))
        #expect(decoded.name == "hello")
        #expect(decoded.count == 3)
    }

    @Test func requestKeepsEndpointPrefix() throws {
        let config = createServiceConfig(
            region: .useast1,
            service: "test",
            serviceProtocol: Self.serviceProtocol,
            endpoint: "https://localhost:4566"
        )
        let request = try AWSHTTPRequest(
            operation: "GetThing",
            path: "/ignored",
            method: .post,
            input: Input(name: "a", count: 1),
            configuration: config
        )
        #expect(request.request.url?.absoluteString == "https://localhost:4566/service/TestService/operation/GetThing")
    }

    @Test func requestHasNoAmzTarget() throws {
        let config = createServiceConfig(
            region: .useast1,
            amzTarget: "Target_20200101",
            service: "test",
            serviceProtocol: Self.serviceProtocol
        )
        let withInput = try AWSHTTPRequest(
            operation: "GetThing",
            path: "/",
            method: .post,
            input: Input(name: "a", count: 1),
            configuration: config
        )
        #expect(withInput.headers[.xAmzTarget] == nil)
        let noInput = try AWSHTTPRequest(operation: "GetThing", path: "/", method: .post, configuration: config)
        #expect(noInput.headers[.xAmzTarget] == nil)
    }

    @Test func requestWithoutInputHasNoBodyOrContentType() throws {
        let config = createServiceConfig(region: .useast1, service: "test", serviceProtocol: Self.serviceProtocol)
        let request = try AWSHTTPRequest(operation: "GetThing", path: "/", method: .post, configuration: config)
        #expect(request.request.url?.path == "/service/TestService/operation/GetThing")
        #expect(request.headers[.init("Smithy-Protocol")!] == "rpc-v2-cbor")
        #expect(request.headers[.accept] == "application/cbor")
        #expect(request.headers[.contentType] == nil)
        guard case .byteBuffer(let buffer) = request.body.storage else {
            Issue.record("Expected a byte buffer body")
            return
        }
        #expect(buffer.readableBytes == 0)
    }

    @Test func requestIgnoresHTTPBindings() throws {
        let config = createServiceConfig(region: .useast1, service: "test", serviceProtocol: Self.serviceProtocol)
        let request = try AWSHTTPRequest(
            operation: "GetThing",
            path: "/{pathMember}",
            method: .post,
            input: BoundInput(name: "n", headerMember: "h", queryMember: "q"),
            configuration: config
        )
        #expect(request.headers[.init("x-bound-header")!] == nil)
        #expect(request.request.url?.query == nil)
        #expect(request.request.url?.path == "/service/TestService/operation/GetThing")

        guard case .byteBuffer(let buffer) = request.body.storage else {
            Issue.record("Expected a byte buffer body")
            return
        }
        let decoded = try CBORDecoder().decode(BoundInput.self, from: Array(buffer.readableBytesView))
        #expect(decoded.name == "n")
        #expect(decoded.headerMember == "h")
        #expect(decoded.queryMember == "q")
    }

    @Test func hostLabelFillsInTheEndpointPrefix() throws {
        let config = createServiceConfig(region: .useast1, service: "test", serviceProtocol: Self.serviceProtocol)
        let request = try AWSHTTPRequest(
            operation: "GetThing",
            path: "/",
            method: .post,
            input: HostLabelInput(accountId: "123456789012"),
            hostPrefix: "{accountId}.",
            configuration: config
        )
        #expect(request.request.url?.host == "123456789012.test.us-east-1.amazonaws.com")
        guard case .byteBuffer(let buffer) = request.body.storage else {
            Issue.record("Expected a byte buffer body")
            return
        }
        #expect(try CBORDecoder().decode([String: String].self, from: Array(buffer.readableBytesView)) == ["accountId": "123456789012"])
    }

    /// Dates are tag 1 epoch seconds and blobs are byte strings, whatever the shape
    @Test func datesAndBlobsUseTheirCBORTypes() throws {
        struct Timed: Encodable {
            let at: Date
            let blob: Data
        }
        let buffer = try RPCv2CBOR.encode(
            Timed(at: Date(timeIntervalSince1970: 1_363_896_240), blob: Data([1, 2, 3])),
            request: .init(path: "/", hostPrefix: nil),
            allocator: .init()
        )
        let expected: [UInt8] =
            [0xA2] + [0x62, 0x61, 0x74] + [0xC1, 0x1A, 0x51, 0x4B, 0x67, 0xB0]
            + [0x64, 0x62, 0x6C, 0x6F, 0x62] + [0x43, 0x01, 0x02, 0x03]
        #expect(Array(buffer.readableBytesView) == expected)
    }

    @Test func rawPayloadIsRefused() {
        let config = createServiceConfig(region: .useast1, service: "test", serviceProtocol: Self.serviceProtocol)
        #expect(throws: AWSClient.ClientError.unsupportedPayload) {
            try AWSHTTPRequest(
                operation: "PutThing",
                path: "/",
                method: .post,
                input: RawPayloadInput(payload: .init(string: "raw")),
                configuration: config
            )
        }
    }

    @Test func nestedRawPayloadIsRefused() {
        let config = createServiceConfig(region: .useast1, service: "test", serviceProtocol: Self.serviceProtocol)
        #expect(throws: AWSClient.ClientError.unsupportedPayload) {
            try AWSHTTPRequest(
                operation: "PutThing",
                path: "/",
                method: .post,
                input: NestedRawPayloadInput(payload: .init(string: "raw")),
                configuration: config
            )
        }
    }

    // MARK: Response

    @Test func successResponseDecodes() throws {
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .ok),
            body: try Self.cborBody(Output(name: "hello", count: 7))
        )
        let output: Output = try response.generateOutputShape(operation: "GetThing", serviceProtocol: Self.serviceProtocol)
        #expect(output.name == "hello")
        #expect(output.count == 7)
    }

    @Test func emptySuccessResponseDecodes() throws {
        let response = AWSHTTPResponse(response: HTTPResponse(status: .ok))
        let output: Output = try response.generateOutputShape(operation: "GetThing", serviceProtocol: Self.serviceProtocol)
        #expect(output.name == nil)
        #expect(output.count == nil)
    }

    @Test func errorWithNamespaceAndSuffix() throws {
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .notFound),
            body: try Self.cborBody(ErrorBody(__type: "com.test#ResourceNotFound:http://internal.amazon.com/", message: "not here"))
        )
        let config = createServiceConfig(serviceProtocol: Self.serviceProtocol, errorType: ServiceError.self)
        let error = response.generateError(serviceConfig: config, logger: TestEnvironment.logger) as? ServiceError
        #expect(error?.kind == .resourceNotFound)
        #expect(error?.message == "not here")
    }

    @Test func errorWithoutNamespace() throws {
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .notFound),
            body: try Self.cborBody(ErrorBody(__type: "ResourceNotFound", message: nil))
        )
        let config = createServiceConfig(serviceProtocol: Self.serviceProtocol, errorType: ServiceError.self)
        let error = response.generateError(serviceConfig: config, logger: TestEnvironment.logger) as? ServiceError
        #expect(error?.kind == .resourceNotFound)
        #expect(error?.message == nil)
    }

    @Test func errorWithCapitalisedMessage() throws {
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .notFound),
            body: try Self.cborBody(CapitalMessageErrorBody(__type: "ns#ResourceNotFound", Message: "capital"))
        )
        let config = createServiceConfig(serviceProtocol: Self.serviceProtocol, errorType: ServiceError.self)
        let error = response.generateError(serviceConfig: config, logger: TestEnvironment.logger) as? ServiceError
        #expect(error?.message == "capital")
    }

    @Test func unrecognisedErrorFallsBackToResponseError() throws {
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .badRequest),
            body: try Self.cborBody(ErrorBody(__type: "ns#SomethingElseException", message: "oops"))
        )
        let config = createServiceConfig(serviceProtocol: Self.serviceProtocol, errorType: ServiceError.self)
        let error = response.generateError(serviceConfig: config, logger: TestEnvironment.logger) as? AWSResponseError
        #expect(error?.errorCode == "SomethingElse")
        #expect(error?.message == "oops")
    }

    @Test func errorIgnoresAmznErrorTypeHeader() throws {
        let response = AWSHTTPResponse(
            response: HTTPResponse(status: .notFound, headerFields: [.xAmznErrorType: "WrongHeaderError"]),
            body: try Self.cborBody(ErrorBody(__type: "ns#ResourceNotFound", message: nil))
        )
        let config = createServiceConfig(serviceProtocol: Self.serviceProtocol)
        let error = response.generateError(serviceConfig: config, logger: TestEnvironment.logger) as? AWSResponseError
        #expect(error?.errorCode == "ResourceNotFound")
    }

    // MARK: Existing protocols are unchanged

    @Test func existingProtocolsUnchanged() throws {
        let input = Input(name: "a", count: 1)

        let json = createServiceConfig(region: .useast1, amzTarget: "Target", service: "test", serviceProtocol: .json(version: "1.1"))
        let jsonRequest = try AWSHTTPRequest(operation: "Op", path: "/", method: .post, input: input, configuration: json)
        #expect(jsonRequest.headers[.xAmzTarget] == "Target.Op")
        #expect(jsonRequest.headers[.contentType] == "application/x-amz-json-1.1")
        #expect(jsonRequest.request.url?.path == "/")
        #expect(jsonRequest.headers[.init("Smithy-Protocol")!] == nil)
        #expect(jsonRequest.headers[.accept] == nil)

        let restJSON = createServiceConfig(region: .useast1, service: "test", serviceProtocol: .restjson)
        let restRequest = try AWSHTTPRequest(operation: "Op", path: "/thing", method: .post, input: input, configuration: restJSON)
        #expect(restRequest.headers[.contentType] == "application/json")
        #expect(restRequest.request.url?.path == "/thing")
        #expect(restRequest.headers[.init("Smithy-Protocol")!] == nil)

        let query = createServiceConfig(region: .useast1, service: "test", serviceProtocol: .query)
        let queryRequest = try AWSHTTPRequest(operation: "Op", path: "/", method: .post, input: input, configuration: query)
        #expect(queryRequest.headers[.contentType] == "application/x-www-form-urlencoded; charset=utf-8")
        #expect(queryRequest.headers[.init("Smithy-Protocol")!] == nil)
    }
}
