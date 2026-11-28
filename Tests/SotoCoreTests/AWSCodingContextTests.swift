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

@Suite("AWSCodingContext")
struct AWSCodingContextTests {
    /// Member shape that writes a header and a host label, as a generated shape does
    struct Nested: AWSEncodableShape, Decodable {
        let id: String
        let headerValue: String

        private enum CodingKeys: String, CodingKey {
            case id
            case headerValue
        }

        func encode(to encoder: any Encoder) throws {
            let request = try encoder.requireAWSRequestContainer()
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.id, forKey: .id)
            try container.encode(self.headerValue, forKey: .headerValue)
            request.encodeHeader(self.headerValue, key: "x-nested")
            request.encodeHostPrefix(self.id, key: "id")
        }
    }

    struct Root: AWSEncodableShape, Decodable {
        let name: String
        let nested: Nested
    }

    struct Summary: Equatable {
        let url: String
        let nestedHeader: String?
        let contentType: String?
        let body: String
    }

    static func isCBOR(_ serviceProtocol: ServiceProtocol) -> Bool {
        if case .rpcv2Cbor = serviceProtocol { return true }
        return false
    }

    static func isJSON1(_ serviceProtocol: ServiceProtocol) -> Bool {
        if case .json = serviceProtocol { return true }
        return false
    }

    static func summary(_ serviceProtocol: ServiceProtocol) throws -> Summary {
        let config = createServiceConfig(region: .useast1, amzTarget: "Target", service: "test", serviceProtocol: serviceProtocol)
        let request = try AWSHTTPRequest(
            operation: "Op",
            path: "/thing",
            method: .post,
            input: Root(name: "a", nested: .init(id: "42", headerValue: "h")),
            hostPrefix: "{id}.",
            configuration: config
        )
        let body: String
        if case .byteBuffer(let buffer) = request.body.storage {
            body =
                Self.isCBOR(serviceProtocol) ? buffer.readableBytesView.map { String($0, radix: 16) }.joined(separator: " ") : String(buffer: buffer)
        } else {
            body = "<stream>"
        }
        return .init(
            url: request.request.url?.absoluteString ?? "",
            nestedHeader: request.headers[.init("x-nested")!],
            contentType: request.headers[.contentType],
            body: body
        )
    }

    static let cbor = ServiceProtocol.rpcv2Cbor(serviceName: "TestService")

    // MARK: Nested shapes

    /// A header member and a host label member on a nested shape reach the request for every protocol
    /// that has HTTP bindings, and are ignored by RPC v2 except for the host label.
    @Test(arguments: [ServiceProtocol.json(version: "1.1"), .restjson, .restxml, .query, .ec2])
    func nestedMembersReachTheRequest(_ serviceProtocol: ServiceProtocol) throws {
        let summary = try Self.summary(serviceProtocol)
        #expect(summary.nestedHeader == "h")
        #expect(summary.url == "https://42.test.us-east-1.amazonaws.com/thing")
    }

    @Test func nestedMembersWithRPCv2() throws {
        let summary = try Self.summary(Self.cbor)
        #expect(summary.nestedHeader == nil)
        #expect(summary.url == "https://42.test.us-east-1.amazonaws.com/service/TestService/operation/Op")
        // {"name": "a", "nested": {"id": "42", "headerValue": "h"}}
        #expect(summary.body == "a2 64 6e 61 6d 65 61 61 66 6e 65 73 74 65 64 a2 62 69 64 62 34 32 6b 68 65 61 64 65 72 56 61 6c 75 65 61 68")
    }

    // MARK: Output of the existing protocols

    @Test func xmlOutputIsUnchanged() throws {
        let summary = try Self.summary(.restxml)
        #expect(summary.contentType == "application/octet-stream")
        #expect(
            summary.body
                == #"<?xml version="1.0" encoding="UTF-8"?><Root><name>a</name><nested><id>42</id><headerValue>h</headerValue></nested></Root>"#
        )
    }

    @Test func queryOutputIsUnchanged() throws {
        let summary = try Self.summary(.query)
        #expect(summary.contentType == "application/x-www-form-urlencoded; charset=utf-8")
        #expect(summary.body == "Action=Op&Version=01-01-2001&name=a&nested.headerValue=h&nested.id=42")
    }

    @Test func ec2OutputIsUnchanged() throws {
        let summary = try Self.summary(.ec2)
        #expect(summary.contentType == "application/x-www-form-urlencoded; charset=utf-8")
        #expect(summary.body == "Action=Op&Name=a&Nested.HeaderValue=h&Nested.Id=42&Version=01-01-2001")
    }

    @Test(arguments: [ServiceProtocol.json(version: "1.1"), .restjson])
    func jsonOutputIsUnchanged(_ serviceProtocol: ServiceProtocol) throws {
        let summary = try Self.summary(serviceProtocol)
        // JSONEncoder does not order keys, so compare the decoded body
        let root = try JSONDecoder().decode(Root.self, from: Data(summary.body.utf8))
        #expect(root.name == "a")
        #expect(root.nested.id == "42")
        #expect(root.nested.headerValue == "h")
        #expect(summary.contentType == (Self.isJSON1(serviceProtocol) ? "application/x-amz-json-1.1" : "application/json"))
    }

    // MARK: Scope

    @Test func encodingOutsideAScopeThrows() {
        #expect(throws: AWSClient.ClientError.missingCodingContext) {
            try CBOREncoder().encode(Nested(id: "1", headerValue: "h"))
        }
        #expect(throws: AWSClient.ClientError.missingCodingContext) {
            _ = try JSONEncoder().encode(Nested(id: "1", headerValue: "h"))
        }
    }

    @Test func decodingOutsideAScopeThrows() throws {
        struct NeedsResponse: Decodable {
            init(from decoder: any Decoder) throws {
                _ = try decoder.requireAWSResponseContainer()
            }
        }
        #expect(throws: AWSClient.ClientError.missingCodingContext) {
            try JSONDecoder().decode(NeedsResponse.self, from: Data("{}".utf8))
        }
        #expect(throws: AWSClient.ClientError.missingCodingContext) {
            try CBORDecoder().decode(NeedsResponse.self, from: [0xA0])
        }
    }

    @Test func scopeEndsWhenTheCallReturns() throws {
        _ = try Self.summary(.restjson)
        #expect(AWSCodingContext.request == nil)
        #expect(AWSCodingContext.response == nil)
        #expect(AWSCodingContext.serviceProtocol == nil)
        #expect(AWSCodingContext.errorMap == nil)
        #expect(AWSCodingContext.event == nil)
    }

    @Test func userInfoIsUsedWhenThereIsNoScope() throws {
        let container = RequestEncodingContainer(path: "/", hostPrefix: nil)
        let encoder = JSONEncoder()
        encoder.userInfo[.awsRequest] = container
        _ = try encoder.encode(Nested(id: "1", headerValue: "from-user-info"))
        #expect(container.headers[.init("x-nested")!] == "from-user-info")
    }

    @Test func scopeWinsOverUserInfo() throws {
        let scoped = RequestEncodingContainer(path: "/", hostPrefix: nil)
        let other = RequestEncodingContainer(path: "/", hostPrefix: nil)
        let encoder = JSONEncoder()
        encoder.userInfo[.awsRequest] = other
        _ = try AWSCodingContext.$request.withValue(scoped) {
            try encoder.encode(Nested(id: "1", headerValue: "scoped"))
        }
        #expect(scoped.headers[.init("x-nested")!] == "scoped")
        #expect(other.headers[.init("x-nested")!] == nil)
    }

    // MARK: Concurrency

    @Test func concurrentEncodesKeepTheirContainersApart() async throws {
        let count = 64
        let results = try await withThrowingTaskGroup(of: (Int, String?, String?).self) { group in
            for index in 0..<count {
                group.addTask {
                    // alternate between a JSON and a CBOR request
                    let serviceProtocol: ServiceProtocol = index % 2 == 0 ? .restjson : Self.cbor
                    let config = createServiceConfig(region: .useast1, service: "test", serviceProtocol: serviceProtocol)
                    let request = try AWSHTTPRequest(
                        operation: "Op",
                        path: "/thing",
                        method: .post,
                        input: Root(name: "n\(index)", nested: .init(id: "id\(index)", headerValue: "h\(index)")),
                        hostPrefix: "{id}.",
                        configuration: config
                    )
                    await Task.yield()
                    return (index, request.headers[.init("x-nested")!], request.request.url?.host)
                }
            }
            var results: [(Int, String?, String?)] = []
            for try await result in group { results.append(result) }
            return results
        }
        #expect(results.count == count)
        for (index, header, host) in results {
            #expect(host == "id\(index).test.us-east-1.amazonaws.com")
            #expect(header == (index % 2 == 0 ? "h\(index)" : nil))
        }
    }
}
