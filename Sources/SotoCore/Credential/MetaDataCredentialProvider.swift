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

import AsyncHTTPClient
import HTTPTypes
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOFoundationEssentialsCompat
import SotoSignerV4

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

protocol MetadataCredential {
    var accessKeyId: String { get }
    var secretAccessKey: String { get }
    var sessionToken: String? { get }
    var expiration: Date { get }
}

/// protocol to get Credentials from the Client. With this the AWSClient requests the credentials for request signing from ecs and ec2.
protocol MetadataClient: CredentialProvider {
    associatedtype MetaData: MetadataCredential & Decodable

    func getMetaData(logger: Logger) async throws -> MetaData
}

enum MetaDataClientError: Error {
    case failedToDecode(underlyingError: any Error)
    case unexpectedTokenResponseStatus(status: HTTPResponse.Status)
    case couldNotReadTokenFromResponse
    case couldNotGetInstanceRoleName
    case couldNotGetInstanceMetaData
    case missingMetaData
}

extension MetadataClient {
    static func createJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // set JSON decoding strategy for dates
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func getCredential(logger: Logger) async throws -> Credential {
        let metadata = try await getMetaData(logger: logger)
        return .init(
            accessKeyId: metadata.accessKeyId,
            secretAccessKey: metadata.secretAccessKey,
            sessionToken: metadata.sessionToken,
            expiration: metadata.expiration
        )
    }
}

struct MetadataHTTPResponse {
    var response: HTTPResponse
    var body: ByteBuffer

    @inlinable
    var status: HTTPResponse.Status { self.response.status }

    @inlinable
    var headers: HTTPFields { self.response.headerFields }
}

struct ECSMetaDataClient: MetadataClient {
    typealias MetaData = ECSMetaData

    static let Host = "http://169.254.170.2"
    static let RelativeURIEnvironmentName = "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"

    struct ECSMetaData: MetadataCredential & Decodable {
        let accessKeyId: String
        let secretAccessKey: String
        let token: String
        let expiration: Date
        let roleArn: String

        var sessionToken: String? {
            self.token
        }

        func isExpiring(within interval: TimeInterval) -> Bool {
            self.expiration.timeIntervalSinceNow < interval
        }

        enum CodingKeys: String, CodingKey {
            case accessKeyId = "AccessKeyId"
            case secretAccessKey = "SecretAccessKey"
            case token = "Token"
            case expiration = "Expiration"
            case roleArn = "RoleArn"
        }
    }

    let httpClient: any AWSHTTPClient
    let endpointURL: String

    init?(httpClient: any AWSHTTPClient, host: String = ECSMetaDataClient.Host) {
        guard let relativeURL = Environment[Self.RelativeURIEnvironmentName] else {
            return nil
        }

        self.httpClient = httpClient
        self.endpointURL = "\(host)\(relativeURL)"
    }

    func getMetaData(logger: Logger) async throws -> ECSMetaData {
        let response = try await request(url: endpointURL, timeout: .seconds(2), logger: logger)
        return try Self.createJSONDecoder().decode(MetaData.self, from: response.body)
    }

    private func request(url: String, timeout: TimeAmount, logger: Logger) async throws -> MetadataHTTPResponse {
        try Task.checkCancellation()
        let request = AWSHTTPRequest(
            request: HTTPRequest(method: .get, url: URL(string: url)!)
        )
        let response = try await httpClient.execute(request: request, timeout: timeout, logger: logger)
        return try await .init(response: response.response, body: response.body.collect(upTo: .max))
    }
}

// MARK: InstanceMetaDataServiceProvider

/// Provide AWS credentials for EC2 instances
struct InstanceMetaDataClient: MetadataClient {
    typealias MetaData = InstanceMetaData

    static let Host = "http://169.254.169.254"
    static let CredentialUri = "/latest/meta-data/iam/security-credentials/"
    static let TokenUri = "/latest/api/token"
    static let TokenTimeToLiveHeader = [HTTPField.Name("X-aws-ec2-metadata-token-ttl-seconds"): "21600"]
    static let TokenHeaderName = HTTPField.Name("X-aws-ec2-metadata-token")!

    struct InstanceMetaData: MetadataCredential & Decodable {
        let accessKeyId: String
        let secretAccessKey: String
        let token: String
        let expiration: Date
        let code: String
        let lastUpdated: Date
        let type: String

        var sessionToken: String? {
            self.token
        }

        func isExpiring(within interval: TimeInterval) -> Bool {
            self.expiration.timeIntervalSinceNow < interval
        }

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

    private var tokenURL: URL {
        URL(string: "\(self.host)\(Self.TokenUri)")!
    }

    private var credentialURL: URL {
        URL(string: "\(self.host)\(Self.CredentialUri)")!
    }

    let httpClient: any AWSHTTPClient
    let host: String

    init(httpClient: any AWSHTTPClient, host: String = InstanceMetaDataClient.Host) {
        self.httpClient = httpClient
        self.host = host
    }

    func getMetaData(logger: Logger) async throws -> InstanceMetaData {
        let headers: HTTPFields
        do {
            let token = try await getToken(logger: logger)
            logger.trace("Found IMDSv2 token")
            headers = [Self.TokenHeaderName: token]
        } catch {
            // If we didn't find a session key then assume we are running IMDSv1.
            // (we could be running from a Docker container and the hop count for the PUT
            // request is still set to 1)
            logger.trace("Did not find IMDSv2 token, use IMDSv1")
            headers = [:]
        }
        // next we need to request the rolename
        let response = try await self.request(
            HTTPRequest(method: .get, url: self.credentialURL, headerFields: headers),
            logger: logger
        )
        // the rolename is in the body
        guard response.status == .ok else {
            throw MetaDataClientError.unexpectedTokenResponseStatus(status: response.status)
        }
        let roleName = String(buffer: response.body)
        // request credentials with the rolename
        let url = self.credentialURL.appendingPathComponent(roleName)
        let credentialResponse = try await self.request(HTTPRequest(method: .get, url: url, headerFields: headers), logger: logger)

        return try Self.createJSONDecoder().decode(InstanceMetaData.self, from: credentialResponse.body)
    }

    func getToken(logger: Logger) async throws -> String {
        let response = try await request(
            HTTPRequest(method: .put, url: self.tokenURL, headerFields: [HTTPField.Name("X-aws-ec2-metadata-token-ttl-seconds")!: "21600"]),
            logger: logger
        )
        guard response.status == .ok else {
            throw MetaDataClientError.unexpectedTokenResponseStatus(status: response.status)
        }
        return String(buffer: response.body)
    }

    private func request(
        _ request: HTTPRequest,
        logger: Logger
    ) async throws -> MetadataHTTPResponse {
        try Task.checkCancellation()
        let request = AWSHTTPRequest(request: request, body: .init())
        let response = try await httpClient.execute(request: request, timeout: TimeAmount.seconds(2), logger: logger)
        return try await MetadataHTTPResponse(response: response.response, body: response.body.collect(upTo: 1_000_000))
    }
}
