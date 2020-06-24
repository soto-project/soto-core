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

import struct Foundation.Date
import struct Foundation.TimeZone
import struct Foundation.Locale
import struct Foundation.TimeInterval
import struct Foundation.URL
import class Foundation.DateFormatter
import class Foundation.JSONDecoder

import NIO
import NIOHTTP1
import NIOConcurrencyHelpers
import AWSSignerV4

/// protocol for decodable objects containing credential information
public protocol CredentialContainer: Decodable {
    var credential: ExpiringCredential { get }
}

/// protocol to get Credentials from the Client. With this the AWSClient requests the credentials for request signing from ecs and ec2.
public protocol MetaDataClient: CredentialProvider {
    associatedtype MetaData: CredentialContainer & Decodable
    
    func getMetaData(on eventLoop: EventLoop) -> EventLoopFuture<MetaData>
}

extension MetaDataClient {
    public func getCredential(on eventLoop: EventLoop) -> EventLoopFuture<Credential> {
        self.getMetaData(on: eventLoop).map { (metaData) in
            metaData.credential
        }
    }
}

enum MetaDataClientError: Error {
    case failedToDecode(underlyingError: Error)
    case unexpectedTokenResponseStatus(status: HTTPResponseStatus)
    case noECSMetaDataService
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


public struct ECSMetaDataClient: MetaDataClient {
    public typealias MetaData = ECSMetaData
    
    static let Host = "169.254.170.2"
    static let RelativeURIEnvironmentName = "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"
    
    public struct ECSMetaData: CredentialContainer {
        let accessKeyId: String
        let secretAccessKey: String
        let token: String
        let expiration: Date
        let roleArn: String

        public var credential: ExpiringCredential {
            return RotatingCredential(
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
    
    let httpClient : AWSHTTPClient
    let host: String
    let decoder = Self.createJSONDecoder()
    
    init(httpClient: AWSHTTPClient, host: String = ECSMetaDataClient.Host) {
        self.host = host
        self.httpClient = httpClient
    }
    
    public func getMetaData(on eventLoop: EventLoop) -> EventLoopFuture<ECSMetaData> {
        guard let relativeURL = Environment[Self.RelativeURIEnvironmentName] else {
            return eventLoop.makeFailedFuture(MetaDataClientError.noECSMetaDataService)
        }
        let endpointURL    = "http://\(host)\(relativeURL)"
        return request(url: endpointURL, timeout: 2, on: eventLoop)
            .flatMapThrowing { response in
                guard let body = response.body else {
                    throw MetaDataClientError.missingMetaData
                }
                return try self.decoder.decode(MetaData.self, from: body)
            }
    }
    
    private func request(url: String, timeout: TimeInterval, on eventLoop: EventLoop) -> EventLoopFuture<AWSHTTPResponse> {
        let request = AWSHTTPRequest(url: URL(string: url)!, method: .GET, headers: [:], body: .empty)
        return httpClient.execute(request: request, timeout: TimeAmount.seconds(2), on: eventLoop)
    }
}

//MARK: InstanceMetaDataServiceProvider
/// Provide AWS credentials for instances
public struct InstanceMetaDataClient: MetaDataClient {
    public typealias MetaData = InstanceMetaData
    
    static let Host = "169.254.169.254"
    static let CredentialUri = "/latest/meta-data/iam/security-credentials/"
    static let TokenUri = "/latest/api/token"
    static let TokenTimeToLiveHeader = (name: "X-aws-ec2-metadata-token-ttl-seconds", value: "21600")
    static let TokenHeaderName = "X-aws-ec2-metadata-token"
    
    public struct InstanceMetaData: CredentialContainer {
        let accessKeyId: String
        let secretAccessKey: String
        let token: String
        let expiration: Date
        let code: String
        let lastUpdated: Date
        let type: String

        public var credential: ExpiringCredential {
            return RotatingCredential(
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
  
    private var tokenURL: URL {
        return URL(string: "http://\(self.host)\(Self.TokenUri)")!
    }
    private var credentialURL: URL {
        return URL(string: "http://\(self.host)\(Self.CredentialUri)")!
    }
    
    let httpClient: AWSHTTPClient
    let host      : String
    let decoder   = Self.createJSONDecoder()
  
    init(httpClient: AWSHTTPClient, host: String = InstanceMetaDataClient.Host) {
        self.httpClient = httpClient
        self.host       = host
    }
    
    public func getMetaData(on eventLoop: EventLoop) -> EventLoopFuture<InstanceMetaData> {
        return getToken(on: eventLoop)
            .map() { token in
                HTTPHeaders([(Self.TokenHeaderName, token)])
            }
            .flatMapErrorThrowing() { error in
                // If we didn't find a session key then assume we are running IMDSv1.
                // (we could be running from a Docker container and the hop count for the PUT
                // request is still set to 1)
                HTTPHeaders()
            }
            .flatMap { (headers) -> EventLoopFuture<(AWSHTTPResponse, HTTPHeaders)> in
                // next we need to request the rolename
                self.request(url: self.credentialURL,
                             method: .GET,
                             headers: headers,
                             on: eventLoop).map() { ($0, headers) }
            }
            .flatMapThrowing { (response, headers) -> (String, HTTPHeaders) in
                // the rolename is in the body
                guard response.status == .ok else {
                    throw MetaDataClientError.unexpectedTokenResponseStatus(status: response.status)
                }

                guard var body = response.body, let roleName = body.readString(length: body.readableBytes) else {
                    throw MetaDataClientError.couldNotGetInstanceRoleName
                }

                return (roleName, headers)
            }
            .flatMap { (roleName, headers) -> EventLoopFuture<AWSHTTPResponse> in
                // request credentials with the rolename
                let url = self.credentialURL.appendingPathComponent(roleName)
                return self.request(url: url, headers: headers, on: eventLoop)
            }
            .flatMapThrowing { (response) in
                // decode the repsonse payload into the metadata object
                guard let body = response.body else {
                    throw MetaDataClientError.missingMetaData
                }
                
                return try self.decoder.decode(InstanceMetaData.self, from: body)
            }
    }
        
    func getToken(on eventLoop: EventLoop) -> EventLoopFuture<String> {
        return request(url: self.tokenURL, method: .PUT, headers: HTTPHeaders([Self.TokenTimeToLiveHeader]), timeout: .seconds(2), on: eventLoop)
            .flatMapThrowing { response in
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
        on eventLoop: EventLoop) -> EventLoopFuture<AWSHTTPResponse>
    {
        let request = AWSHTTPRequest(url: url, method: method, headers: headers, body: .empty)
        return httpClient.execute(request: request, timeout: timeout, on: eventLoop)
    }
}

