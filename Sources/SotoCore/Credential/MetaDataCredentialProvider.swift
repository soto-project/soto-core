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

import AsyncHTTPClient
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOFoundationCompat
import NIOHTTP1
import SotoSignerV4

import struct Foundation.Date
import class Foundation.ISO8601DateFormatter
import class Foundation.JSONDecoder
import struct Foundation.TimeInterval
import struct Foundation.URL

/// protocol to get Credentials from the Client. With this the AWSClient requests the credentials for request signing from ecs and ec2.
protocol MetaDataClient: CredentialProvider {
    associatedtype MetaData: ExpiringCredential & Decodable

    func getMetaData(logger: Logger) async throws -> MetaData
}

extension MetaDataClient {
    func getCredential(logger: Logger) async throws -> Credential {
        try await self.getMetaData(logger: logger)
    }
}

enum MetaDataClientError: Error {
    case failedToDecode(underlyingError: Error)
    case unexpectedTokenResponseStatus(status: HTTPResponseStatus)
    case couldNotReadTokenFromResponse
    case couldNotGetInstanceRoleName
    case couldNotGetInstanceMetaData
    case missingMetaData
}

extension MetaDataClient {
    static func createJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // set JSON decoding strategy for dates
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct MetadataHTTPResponse {
    public var status: HTTPResponseStatus
    public var headers: HTTPHeaders
    public var body: ByteBuffer?
}

struct ECSMetaDataClient: MetaDataClient {
    typealias MetaData = ECSMetaData

    static let Host = "http://169.254.170.2"
    static let RelativeURIEnvironmentName = "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"

    struct ECSMetaData: ExpiringCredential, Decodable {
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

    let httpClient: AWSHTTPClient
    let endpointURL: String

    init?(httpClient: AWSHTTPClient, host: String = ECSMetaDataClient.Host) {
        guard let relativeURL = Environment[Self.RelativeURIEnvironmentName] else {
            return nil
        }

        self.httpClient = httpClient
        self.endpointURL = "\(host)\(relativeURL)"
    }

    func getMetaData(logger: Logger) async throws -> ECSMetaData {
        let response = try await request(url: endpointURL, timeout: .seconds(2), logger: logger)
        guard let body = response.body else {
            throw MetaDataClientError.missingMetaData
        }
        return try Self.createJSONDecoder().decode(MetaData.self, from: body)
    }

    private func request(url: String, timeout: TimeAmount, logger: Logger) async throws -> MetadataHTTPResponse {
        try Task.checkCancellation()
        let request = AWSHTTPRequest(url: URL(string: url)!, method: .GET, headers: [:], body: .init())
        let response = try await httpClient.execute(request: request, timeout: timeout, logger: logger)
        return try await .init(status: response.status, headers: response.headers, body: response.body.collect(upTo: .max))
    }
}

// MARK: InstanceMetaDataServiceProvider

/// Provide AWS credentials for EC2 instances
struct InstanceMetaDataClient: MetaDataClient {
    typealias MetaData = InstanceMetaData

    static let Host = "http://169.254.169.254"
    static let CredentialUri = "/latest/meta-data/iam/security-credentials/"
    static let TokenUri = "/latest/api/token"
    static let TokenTimeToLiveHeader = (name: "X-aws-ec2-metadata-token-ttl-seconds", value: "21600")
    static let TokenHeaderName = "X-aws-ec2-metadata-token"

    struct InstanceMetaData: ExpiringCredential, Decodable {
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

    let httpClient: AWSHTTPClient
    let host: String

    init(httpClient: AWSHTTPClient, host: String = InstanceMetaDataClient.Host) {
        self.httpClient = httpClient
        self.host = host
    }

    func getMetaData(logger: Logger) async throws -> InstanceMetaData {
        let headers: HTTPHeaders
        do {
            let token = try await getToken(logger: logger)
            logger.trace("Found IMDSv2 token")
            headers = HTTPHeaders([(Self.TokenHeaderName, token)])
        } catch {
            // If we didn't find a session key then assume we are running IMDSv1.
            // (we could be running from a Docker container and the hop count for the PUT
            // request is still set to 1)
            logger.trace("Did not find IMDSv2 token, use IMDSv1")
            headers = HTTPHeaders()
        }
        // next we need to request the rolename
        let response = try await self.request(
            url: self.credentialURL,
            method: .GET,
            headers: headers,
            logger: logger
        )
        // the rolename is in the body
        guard response.status == .ok else {
            throw MetaDataClientError.unexpectedTokenResponseStatus(status: response.status)
        }
        guard var body = response.body, let roleName = body.readString(length: body.readableBytes) else {
            throw MetaDataClientError.couldNotGetInstanceRoleName
        }
        // request credentials with the rolename
        let url = self.credentialURL.appendingPathComponent(roleName)
        let credentialResponse = try await self.request(url: url, headers: headers, logger: logger)

        // decode the repsonse payload into the metadata object
        guard let body = credentialResponse.body else {
            throw MetaDataClientError.missingMetaData
        }

        return try Self.createJSONDecoder().decode(InstanceMetaData.self, from: body)
    }

    func getToken(logger: Logger) async throws -> String {
        let response = try await request(
            url: self.tokenURL,
            method: .PUT,
            headers: HTTPHeaders([Self.TokenTimeToLiveHeader]),
            logger: logger
        )
        guard response.status == .ok else {
            throw MetaDataClientError.unexpectedTokenResponseStatus(status: response.status)
        }

        guard var body = response.body, let token = body.readString(length: body.readableBytes) else {
            throw MetaDataClientError.couldNotReadTokenFromResponse
        }
        return token
    }

    private func request(
        url: URL,
        method: HTTPMethod = .GET,
        headers: HTTPHeaders = .init(),
        logger: Logger
    ) async throws -> MetadataHTTPResponse {
        try Task.checkCancellation()
        let request = AWSHTTPRequest(url: url, method: method, headers: headers, body: .init())
        let response = try await httpClient.execute(request: request, timeout: TimeAmount.seconds(2), logger: logger)
        return try await .init(status: response.status, headers: response.headers, body: response.body.collect(upTo: .max))
    }
}
