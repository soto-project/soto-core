//
//  MetaDataCredentialProvider.swift
//  AWSSDKSwiftCore
//
//  Created by Fabian Fett on 05.12.19.
//

#if os(Linux)

import Foundation
import NIO
import NIOConcurrencyHelpers
import AWSSigner

public struct ExpiringCredential: Credential {
  
    public let accessKeyId: String
    public let secretAccessKey: String
    public let sessionToken: String?
    public let expiration: Date?
    
    public init(accessKeyId: String, secretAccessKey: String, sessionToken: String? = nil, expiration: Date? = nil) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken ?? ProcessInfo.processInfo.environment["AWS_SESSION_TOKEN"]
        self.expiration = expiration
    }
    
    func nearExpiration() -> Bool {
        guard let expiration = self.expiration else {
            return false
        }
      
        // are we within 5 minutes of expiration?
        return Date().addingTimeInterval(5.0 * 60.0) > expiration
    }
}

/// protocol for decodable objects containing credential information
public protocol CredentialContainer: Decodable {
    var credential: ExpiringCredential { get }
}

public protocol MetaDataClient {
    associatedtype MetaData: CredentialContainer & Decodable
    
    func getMetaData() -> EventLoopFuture<MetaData>
}

enum MetaDataClientError: Error {
    case failedToDecode
    case couldNotGetInstanceRoleName
}

extension MetaDataClient {
    
    /// decode response return by metadata service
    func decodeResponse(_ bytes: ByteBuffer) throws -> MetaData {
        let decoder = JSONDecoder()
        // set JSON decoding strategy for dates
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        // decode to associated type
        let metaData = try decoder.decode(MetaData.self, from: bytes)
        return metaData
    }
}

class MetaDataCredentialProvider<Client: MetaDataClient> {
    typealias MetaData  = Client.MetaData
    
    let eventLoopGroup  : EventLoopGroup
    let metaDataClient  : Client
    
    let lock            = NIOConcurrencyHelpers.Lock()
    var credential      : ExpiringCredential? = nil
    var credentialFuture: EventLoopFuture<Credential>? = nil

    init(eventLoopGroup: EventLoopGroup, client: Client) {
        self.eventLoopGroup = eventLoopGroup
        self.metaDataClient = client

        _ = self.refreshCredentials()
    }
    
    func getCredential() -> EventLoopFuture<Credential> {
        self.lock.lock()
        let cred = credential
        self.lock.unlock()
        
        if let cred = cred, cred.nearExpiration() == false {
            // we have credentials and those are still valid
            
            if self.eventLoopGroup is MultiThreadedEventLoopGroup {
              // if we are in a MultiThreadedEventLoopGroup we try to minimize hops.
              return MultiThreadedEventLoopGroup.currentEventLoop!.makeSucceededFuture(cred)
            }
            return self.eventLoopGroup.next().makeSucceededFuture(cred)
        }
        
        // we need to refresh the credentials
        return self.refreshCredentials()
    }
    
    private func refreshCredentials() -> EventLoopFuture<Credential> {
        self.lock.lock()
        defer { self.lock.unlock() }
        
        if let future = credentialFuture {
            // a refresh is already running
            return future
        }
        
        credentialFuture = self.metaDataClient.getMetaData()
            .map { (metadata) -> (Credential) in
                let credential = metadata.credential
                
                self.lock.lock()
                defer { self.lock.unlock() }
                
                self.credentialFuture = nil
                self.credential = credential
                
                return credential
            }

        return credentialFuture!
    }
  
}

struct ECSMetaDataClient: MetaDataClient {
    public typealias MetaData = ECSMetaData
    
    struct ECSMetaData: CredentialContainer {
        let accessKeyId: String
        let secretAccessKey: String
        let token: String
        let expiration: Date
        let roleArn: String

        public var credential: ExpiringCredential {
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
    
    static let Host = "169.254.170.2"
    
    let httpClient    : AWSHTTPClient
    let endpointURL   : String
    
    init?(httpClient: AWSHTTPClient, host: String = ECSMetaDataClient.Host) {
        guard let relativeURL  = ProcessInfo.processInfo.environment["AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"] else {
            return nil
        }
        
        self.httpClient     = httpClient
        self.endpointURL    = "http://\(host)\(relativeURL)"
    }
    
    func getMetaData() -> EventLoopFuture<ECSMetaData> {
        return request(url: endpointURL, timeout: 2)
            .flatMapThrowing { response in
                if let body = response.body {
                    return try self.decodeResponse(body)
                }
                throw MetaDataClientError.failedToDecode
            }
    }
    
    private func request(url: String, timeout: TimeInterval) -> Future<AWSHTTPResponse> {
        let request = AWSHTTPRequest(url: URL(string: url)!, method: .GET, headers: [:], body: nil)
        return httpClient.execute(request: request, timeout: TimeAmount.seconds(2))
    }

  
}

//MARK: InstanceMetaDataServiceProvider

/// Provide AWS credentials for instances
struct InstanceMetaDataClient: MetaDataClient {
    typealias MetaData = InstanceMetaData

    struct InstanceMetaData: CredentialContainer {
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
  
    static let Host = "169.254.169.254"
    static let MetadataUri = "/latest/meta-data/iam/security-credentials/"

    let httpClient    : AWSHTTPClient
    let endpointURL   : String
  
    init(httpClient: AWSHTTPClient, host: String = InstanceMetaDataClient.Host, uri: String = InstanceMetaDataClient.MetadataUri) {
        self.httpClient = httpClient
        self.endpointURL = "http://\(host)\(uri)"
    }
    
    func getMetaData() -> EventLoopFuture<InstanceMetaData> {
        return getUri()
            .flatMap { url in
                return self.request(url: url, timeout: 2)
            }
            .flatMapThrowing { response in
                if let body = response.body {
                    return try self.decodeResponse(body)
                }
                throw MetaDataClientError.failedToDecode
            }
    }
    
    func getUri() -> EventLoopFuture<String> {
        return request(url: self.endpointURL, timeout: 2)
            .flatMapThrowing{ response in
                switch response.status {
                case .ok:
                    if let body = response.body, let roleName = body.getString(at: body.readerIndex, length: body.readableBytes, encoding: .utf8) {
                        return "\(self.endpointURL)/\(roleName)"
                    }
                    return self.endpointURL
                default:
                    throw MetaDataClientError.couldNotGetInstanceRoleName
                }
        }
    }
    
    private func request(url: String, timeout: TimeInterval) -> Future<AWSHTTPResponse> {
        let request = AWSHTTPRequest(url: URL(string: url)!, method: .GET, headers: [:], body: nil)
        return httpClient.execute(request: request, timeout: TimeAmount.seconds(2))
    }
}

#endif
