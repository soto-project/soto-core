//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
import NIO
import NIOFoundationCompat
import NIOHTTP1

import struct Foundation.Data
import struct Foundation.URL
import class  Foundation.DateFormatter
import struct Foundation.Date
import struct Foundation.TimeInterval
import struct Foundation.TimeZone
import struct Foundation.Locale
import class  Foundation.JSONDecoder
import class  Foundation.ProcessInfo

/// errors returned by metadata service
enum MetaDataServiceError: Error {
    case failedToDecode
    case couldNotGetInstanceRoleName
    case couldNotGetInstanceMetadata
}

/// Object managing accessing of AWS credentials from various sources
struct MetaDataService {

    /// return future holding a credential provider
    static func getCredential(httpClient: AWSHTTPClient) -> EventLoopFuture<Credential> {
        if let ecsCredentialProvider = ECSMetaDataServiceProvider() {
            return ecsCredentialProvider.getCredential(httpClient: httpClient)
        } else {
            return InstanceMetaDataServiceProvider().getCredential(httpClient: httpClient)
        }
    }
}

/// protocol for decodable objects containing credential information
protocol MetaDataContainer: Decodable {
    var credential: ExpiringCredential { get }
}

//MARK: MetadataServiceProvider

/// protocol for metadata service returning AWS credentials
protocol MetaDataServiceProvider {
    associatedtype MetaData: MetaDataContainer
    func getCredential(httpClient: AWSHTTPClient) -> EventLoopFuture<Credential>
}

extension MetaDataServiceProvider {

    /// make HTTP request
    func request(url: String, method: HTTPMethod = .GET, headers: [String:String] = [:], timeout: TimeInterval, httpClient: AWSHTTPClient) -> EventLoopFuture<AWSHTTPResponse> {
        let request = AWSHTTPRequest(url: URL(string: url)!, method: method, headers: HTTPHeaders(headers.map {($0.key, $0.value) }), body: nil)
        let futureResponse = httpClient.execute(request: request, timeout: TimeAmount.seconds(2))
        return futureResponse
    }

    /// decode response return by metadata service
    func decodeCredential(_ byteBuffer: ByteBuffer) -> Credential? {
        do {
            let decoder = JSONDecoder()
            // set JSON decoding strategy for dates
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            decoder.dateDecodingStrategy = .formatted(dateFormatter)
            // decode to associated type
            let metaData = try decoder.decode(MetaData.self, from: byteBuffer)
            return metaData.credential
        } catch {
            return nil
        }
    }
}

//MARK: ECSMetaDataServiceProvider

/// Provide AWS credentials for ECS instances
struct ECSMetaDataServiceProvider: MetaDataServiceProvider {

    struct ECSMetaData: MetaDataContainer {
        let accessKeyId: String
        let secretAccessKey: String
        let token: String
        let expiration: Date
        let roleArn: String

        var credential: ExpiringCredential {
            return ExpiringCredential(
                accessKeyId: accessKeyId,
                secretAccessKey: secretAccessKey,
                sessionToken: token,
                expiration: expiration
            )
        }

        enum CodingKeys: String, CodingKey {
            case accessKeyId = "AccessKeyId"
            case secretAccessKey = "SecretAccessKey"
            case token = "Token"
            case expiration = "Expiration"
            case roleArn = "RoleArn"
        }
    }

    typealias MetaData = ECSMetaData

    static var containerCredentialsUri = ProcessInfo.processInfo.environment["AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"]
    static var host = "169.254.170.2"
    var url: String

    init?() {
        guard let uri = ECSMetaDataServiceProvider.containerCredentialsUri else {return nil}
        self.url = "http://\(ECSMetaDataServiceProvider.host)\(uri)"
    }

    func getCredential(httpClient: AWSHTTPClient) -> EventLoopFuture<Credential> {
        return request(url: url, timeout: 2, httpClient: httpClient)
            .flatMapThrowing { response in
                guard response.status == .ok else { throw MetaDataServiceError.couldNotGetInstanceMetadata }
                if let body = response.body,
                    let credential = self.decodeCredential(body) {
                    return credential
                } else {
                    throw MetaDataServiceError.failedToDecode
                }
        }
    }
}

//MARK: InstanceMetaDataServiceProvider

/// Provide AWS credentials for instances
struct InstanceMetaDataServiceProvider: MetaDataServiceProvider {

    struct InstanceMetaData: MetaDataContainer {
        let accessKeyId: String
        let secretAccessKey: String
        let token: String
        let expiration: Date
        let code: String
        let lastUpdated: Date
        let type: String

        var credential: ExpiringCredential {
            return ExpiringCredential(
                accessKeyId: accessKeyId,
                secretAccessKey: secretAccessKey,
                sessionToken: token,
                expiration: expiration
            )
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

    typealias MetaData = InstanceMetaData

    static let instanceMetadataApiTokenUri = "/latest/api/token"
    static let instanceMetadataUri = "/latest/meta-data/iam/security-credentials/"
    static var host = "169.254.169.254"
    static var apiTokenURL: String {
        return "http://\(host)\(instanceMetadataApiTokenUri)"
    }
    static var baseURLString: String {
        return "http://\(host)\(instanceMetadataUri)"
    }

    func getCredential(httpClient: AWSHTTPClient) -> EventLoopFuture<Credential> {
        //  no point storing the session key as the credentials last as long
        var sessionTokenHeader: [String: String] = [:]
        // instance service expects absoluteString as uri...
        return request(
            url:InstanceMetaDataServiceProvider.apiTokenURL,
            method: .PUT,
            headers:["X-aws-ec2-metadata-token-ttl-seconds":"21600"],
            timeout: 2,
            httpClient: httpClient
        ).flatMapThrowing { response in
            // extract session key from response.
            if response.status == .ok,
                let body = response.body,
                let token = body.getString(at: body.readerIndex, length: body.readableBytes, encoding: .utf8) {
                sessionTokenHeader = ["X-aws-ec2-metadata-token":token]
            }
        }.flatMapError { error in
            // If we didn't find a session key then assume we are running IMDSv1 (we could be running from a Docker container
            // and the hop count for the PUT request is still set to 1)
            return httpClient.eventLoopGroup.next().makeSucceededFuture(())
        }.flatMap { _ in
            // request rolename
            return self.request(
                url:InstanceMetaDataServiceProvider.baseURLString,
                headers:sessionTokenHeader,
                timeout: 2,
                httpClient: httpClient
            )
        }.flatMapThrowing { response in
            // extract rolename
            guard response.status == .ok,
                let body = response.body,
                let roleName = body.getString(at: body.readerIndex, length: body.readableBytes, encoding: .utf8) else {
                    throw MetaDataServiceError.couldNotGetInstanceRoleName
            }
            return "\(InstanceMetaDataServiceProvider.baseURLString)/\(roleName)"
        }.flatMap { url in
            // request credentials
            return self.request(url: url, headers:sessionTokenHeader, timeout: 2, httpClient: httpClient)
        }.flatMapThrowing { response in
            // decode credentials
            guard response.status == .ok else { throw MetaDataServiceError.couldNotGetInstanceMetadata }
            if let body = response.body,
                let credential = self.decodeCredential(body) {
                return credential
            } else {
                throw MetaDataServiceError.failedToDecode
            }
        }
    }
}
