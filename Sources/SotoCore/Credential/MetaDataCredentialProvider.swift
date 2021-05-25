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

import struct Foundation.Date
import class Foundation.DateFormatter
import class Foundation.JSONDecoder
import struct Foundation.Locale
import struct Foundation.TimeInterval
import struct Foundation.TimeZone
import struct Foundation.URL

import Baggage
import NIO
import NIOConcurrencyHelpers
import NIOHTTP1
import SotoSignerV4

/// protocol to get Credentials from the Client. With this the AWSClient requests the credentials for request signing from ecs and ec2.
protocol MetaDataClient: CredentialProvider {
    associatedtype MetaData: ExpiringCredential & Decodable

    func getMetaData(on eventLoop: EventLoop, context: LoggingContext) -> EventLoopFuture<MetaData>
}

extension MetaDataClient {
    func getCredential(on eventLoop: EventLoop, context: LoggingContext) -> EventLoopFuture<Credential> {
        self.getMetaData(on: eventLoop, context: context).map { metaData in
            metaData
        }
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
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        decoder.dateDecodingStrategy = .formatted(dateFormatter)

        return decoder
    }
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
            return self.expiration.timeIntervalSinceNow < interval
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
    let decoder = Self.createJSONDecoder()

    init?(httpClient: AWSHTTPClient, host: String = ECSMetaDataClient.Host) {
        guard let relativeURL = Environment[Self.RelativeURIEnvironmentName] else {
            return nil
        }

        self.httpClient = httpClient
        self.endpointURL = "\(host)\(relativeURL)"
    }

    func getMetaData(on eventLoop: EventLoop, context: LoggingContext) -> EventLoopFuture<ECSMetaData> {
        return request(url: endpointURL, timeout: 2, on: eventLoop, context: context)
            .flatMapThrowing { response in
                guard let body = response.body else {
                    throw MetaDataClientError.missingMetaData
                }
                return try self.decoder.decode(MetaData.self, from: body)
            }
    }

    private func request(url: String, timeout: TimeInterval, on eventLoop: EventLoop, context: LoggingContext) -> EventLoopFuture<AWSHTTPResponse> {
        let request = AWSHTTPRequest(url: URL(string: url)!, method: .GET, headers: [:], body: .empty)
        return httpClient.execute(request: request, timeout: TimeAmount.seconds(2), on: eventLoop, context: context)
    }
}

// MARK: InstanceMetaDataServiceProvider

/// Provide AWS credentials for instances
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
            return self.expiration.timeIntervalSinceNow < interval
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
        return URL(string: "\(self.host)\(Self.TokenUri)")!
    }

    private var credentialURL: URL {
        return URL(string: "\(self.host)\(Self.CredentialUri)")!
    }

    let httpClient: AWSHTTPClient
    let host: String
    let decoder = Self.createJSONDecoder()

    init(httpClient: AWSHTTPClient, host: String = InstanceMetaDataClient.Host) {
        self.httpClient = httpClient
        self.host = host
    }

    func getMetaData(on eventLoop: EventLoop, context: LoggingContext) -> EventLoopFuture<InstanceMetaData> {
        return getToken(on: eventLoop, context: context)
            .map { token in
                context.logger.trace("Found IMDSv2 token")
                return HTTPHeaders([(Self.TokenHeaderName, token)])
            }
            .flatMapErrorThrowing { _ in
                // If we didn't find a session key then assume we are running IMDSv1.
                // (we could be running from a Docker container and the hop count for the PUT
                // request is still set to 1)
                context.logger.trace("Did not find IMDSv2 token, use IMDSv1")
                return HTTPHeaders()
            }
            .flatMap { headers -> EventLoopFuture<(AWSHTTPResponse, HTTPHeaders)> in
                // next we need to request the rolename
                self.request(
                    url: self.credentialURL,
                    method: .GET,
                    headers: headers,
                    on: eventLoop,
                    context: context
                ).map { ($0, headers) }
            }
            .flatMapThrowing { response, headers -> (String, HTTPHeaders) in
                // the rolename is in the body
                guard response.status == .ok else {
                    throw MetaDataClientError.unexpectedTokenResponseStatus(status: response.status)
                }

                guard var body = response.body, let roleName = body.readString(length: body.readableBytes) else {
                    throw MetaDataClientError.couldNotGetInstanceRoleName
                }

                return (roleName, headers)
            }
            .flatMap { roleName, headers -> EventLoopFuture<AWSHTTPResponse> in
                // request credentials with the rolename
                let url = self.credentialURL.appendingPathComponent(roleName)
                return self.request(url: url, headers: headers, on: eventLoop, context: context)
            }
            .flatMapThrowing { response in
                // decode the repsonse payload into the metadata object
                guard let body = response.body else {
                    throw MetaDataClientError.missingMetaData
                }

                return try self.decoder.decode(InstanceMetaData.self, from: body)
            }
    }

    func getToken(on eventLoop: EventLoop, context: LoggingContext) -> EventLoopFuture<String> {
        return request(
            url: self.tokenURL,
            method: .PUT,
            headers: HTTPHeaders([Self.TokenTimeToLiveHeader]), timeout: .seconds(2),
            on: eventLoop,
            context: context
        ).flatMapThrowing { response in
            guard response.status == .ok else {
                throw MetaDataClientError.unexpectedTokenResponseStatus(status: response.status)
            }

            guard var body = response.body, let token = body.readString(length: body.readableBytes) else {
                throw MetaDataClientError.couldNotReadTokenFromResponse
            }
            return token
        }
    }

    private func request(
        url: URL,
        method: HTTPMethod = .GET,
        headers: HTTPHeaders = .init(),
        timeout: TimeAmount = .seconds(2),
        on eventLoop: EventLoop,
        context: LoggingContext
    ) -> EventLoopFuture<AWSHTTPResponse> {
        let request = AWSHTTPRequest(url: url, method: method, headers: headers, body: .empty)
        return httpClient.execute(request: request, timeout: timeout, on: eventLoop, context: context)
    }
}
