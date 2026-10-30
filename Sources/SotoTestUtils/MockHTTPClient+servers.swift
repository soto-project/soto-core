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

import HTTPTypes
import Logging
import NIOCore
import SotoCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension MockHTTPClient {
    // MARK: HTTPBin

    // httpBin function response
    package struct HTTPBinResponse: AWSDecodableShape & Encodable {
        package let method: String?
        package let data: String?
        package let headers: HTTPFields
        package let url: String
    }

    package static var httpBin: MockHTTPClient {
        .init { request in
            // httpBin function response
            let data = try await String(buffer: request.body.collect(upTo: .max))
            let httpBinResponse = HTTPBinResponse(
                method: request.method.rawValue,
                data: data,
                headers: request.request.headerFields,
                url: request.request.path ?? "Unknown"
            )
            let responseBody = try JSONEncoder().encode(httpBinResponse)
            return .init(response: .init(status: .ok, headerFields: [.contentType: "application/json"]), body: .init(bytes: responseBody))
        }
    }

    // MARK: EC2

    package enum IMDSVersion {
        case v1
        case v2
    }

    package struct EC2InstanceMetaData: Encodable, Sendable {
        package let accessKeyId: String
        package let secretAccessKey: String
        package let token: String
        package let expiration: Date
        package let code: String
        package let lastUpdated: Date
        package let type: String

        package static let `default` = EC2InstanceMetaData(
            accessKeyId: "EC2ACCESSKEYID",
            secretAccessKey: "EC2SECRETACCESSKEY",
            token: "EC2SESSIONTOKEN",
            expiration: Date(timeIntervalSinceNow: 3600),
            code: "ec2-test-role",
            lastUpdated: Date(timeIntervalSinceReferenceDate: 0),
            type: "type"
        )

        enum CodingKeys: String, CodingKey {
            case accessKeyId = "AccessKeyId"
            case secretAccessKey = "SecretAccessKey"
            case token = "Token"
            case expiration = "Expiration"
            case code = "Code"
            case lastUpdated = "LastUpdated"
            case type = "Type"
        }
    }

    /// fake ec2 metadata server
    package static func ec2MetadataServer(version: IMDSVersion, metaData: EC2InstanceMetaData? = nil) -> MockHTTPClient {
        enum InstanceMetaData {
            static let CredentialUri = "/latest/meta-data/iam/security-credentials/"
            static let TokenUri = "/latest/api/token"
            static let TokenHeaderName = HTTPField.Name("X-aws-ec2-metadata-token")!
        }
        let ec2Role = "ec2-testserver-role"
        let token = "345-34hj-345jk-4875"
        let metaData = metaData ?? EC2InstanceMetaData.default

        return .init { (request: AWSHTTPRequest) in
            switch (request.method, request.request.path) {
            case (.put, InstanceMetaData.TokenUri):
                // Token access
                switch version {
                case .v1:
                    return AWSError(status: .notImplemented).response(for: .restjson)
                case .v2:
                    let responseBody = ByteBuffer(string: token)
                    return .init(response: .init(status: .ok), body: .init(buffer: responseBody))
                }

            case (.get, InstanceMetaData.CredentialUri):
                // Role name
                guard version == .v1 || request.headers[InstanceMetaData.TokenHeaderName] == token else {
                    return AWSError(status: .badRequest).response(for: .restjson)
                }
                let responseBody = ByteBuffer(string: ec2Role)
                return .init(response: .init(status: .ok), body: .init(buffer: responseBody))

            case (.get, InstanceMetaData.CredentialUri + ec2Role):
                // credentials
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let responseBody = try encoder.encodeAsByteBuffer(metaData, allocator: ByteBufferAllocator())
                return .init(response: .init(status: .ok, headerFields: [.contentType: "application/json"]), body: .init(buffer: responseBody))

            default:
                return AWSError(status: .badRequest).response(for: .restjson)
            }
        }
    }

    // MARK: ECS

    package struct ECSMetaData: Encodable, Sendable {
        package let accessKeyId: String
        package let secretAccessKey: String
        package let token: String
        package let expiration: Date
        package let roleArn: String

        package static let `default` = ECSMetaData(
            accessKeyId: "ECSACCESSKEYID",
            secretAccessKey: "ECSSECRETACCESSKEY",
            token: "ECSSESSIONTOKEN",
            expiration: Date(timeIntervalSinceNow: 3600),
            roleArn: "arn:aws:iam:000000000000:role/ecs-test-role"
        )

        enum CodingKeys: String, CodingKey {
            case accessKeyId = "AccessKeyId"
            case secretAccessKey = "SecretAccessKey"
            case token = "Token"
            case expiration = "Expiration"
            case roleArn = "RoleArn"
        }
    }

    /// fake ecs metadata server
    package static func ecsMetadataServer(path: String, metaData: ECSMetaData? = nil) -> MockHTTPClient {
        let metaData = metaData ?? ECSMetaData.default

        return .init { (request: AWSHTTPRequest) in
            if request.method == .get, request.request.path == path {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let responseBody = try encoder.encodeAsByteBuffer(metaData, allocator: ByteBufferAllocator())
                return AWSHTTPResponse(
                    response: .init(status: .ok, headerFields: [.contentType: "application/json"]),
                    body: .init(buffer: responseBody)
                )
            }
            return AWSError(status: .badRequest).response(for: .restjson)
        }
    }
}
