//
//  MetaDataService.swift
//  SwiftAWSDynamodb
//
//  Created by Yuki Takei on 2017/07/12.
//
//

//#if os(Linux)

import Foundation
import NIO
import NIOHTTP1

/// errors returned by metadata service
enum MetaDataServiceError: Error {
    case missingRequiredParam(String)
    case couldNotGetInstanceSessionKey
    case couldNotGetInstanceRoleName
    case couldNotGetInstanceMetadata
}

/// Object managing accessing of AWS credentials from various sources
public struct MetaDataService {

    /// return future holding a credential provider
    public static func getCredential(eventLoopGroup: EventLoopGroup) throws -> Future<CredentialProvider> {
        if let ecsCredentialProvider = ECSMetaDataServiceProvider() {
            return ecsCredentialProvider.getCredential(eventLoopGroup: eventLoopGroup)
        } else {
            return InstanceMetaDataServiceProvider().getCredential(eventLoopGroup: eventLoopGroup)
        }
    }
}

/// protocol for decodable objects containing credential information
protocol MetaDataContainer: Decodable {
    var credential: Credential { get }
}

//MARK: MetadataServiceProvider

/// protocol for metadata service returning AWS credentials
protocol MetaDataServiceProvider {
    associatedtype MetaData: MetaDataContainer
    func getCredential(eventLoopGroup: EventLoopGroup) -> Future<CredentialProvider>
}

extension MetaDataServiceProvider {

    /// make HTTP request
    func request(uri: String, method: HTTPMethod = .GET, headers: [String:String] = [:], timeout: TimeInterval, eventLoopGroup: EventLoopGroup) -> Future<HTTPClient.Response> {
        let client = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        let httpHeaders = HTTPHeaders(headers.map { ($0, $1) })
        let head = HTTPRequestHead(
                     version: HTTPVersion(major: 1, minor: 1),
                     method: method,
                     uri: uri,
                     headers: httpHeaders
                   )
        let request = HTTPClient.Request(head: head, body: Data())
        let futureResponse = client.connect(request)

        futureResponse.whenComplete { _ in
            do {
                try client.syncShutdown()
            } catch {
                print("Error closing connection: \(error)")
            }
        }

        return futureResponse
    }

    /// decode response return by metadata service
    func decodeCredential(_ data: Data) -> CredentialProvider {
        do {
            let decoder = JSONDecoder()
            // set JSON decoding strategy for dates
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            decoder.dateDecodingStrategy = .formatted(dateFormatter)
            // decode to associated type
            let metaData = try decoder.decode(MetaData.self, from: data)
            return metaData.credential
        } catch {
            return Credential(accessKeyId: "", secretAccessKey: "")
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

        var credential: Credential {
            return Credential(
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
    var uri: String

    init?() {
        guard let uri = ECSMetaDataServiceProvider.containerCredentialsUri else {return nil}
        self.uri = "http://\(ECSMetaDataServiceProvider.host)\(uri)"
    }

    func getCredential(eventLoopGroup: EventLoopGroup) -> Future<CredentialProvider> {
        return request(uri: uri, timeout: 2, eventLoopGroup: eventLoopGroup)
            .map { response in
                return self.decodeCredential(response.body)
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

        var credential: Credential {
            return Credential(
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

    static let instanceMetadataApiTokenUri = "/latest/api/token/"
    static let instanceMetadataUri = "/latest/meta-data/iam/security-credentials/"
    static var host = "169.254.169.254"
    static var apiTokenURL: String {
        return "http://\(host)\(instanceMetadataUri)"
    }
    static var baseURLString: String {
        return "http://\(host)\(instanceMetadataUri)"
    }

    func getCredential(eventLoopGroup: EventLoopGroup) -> Future<CredentialProvider> {
        //  no point storing the session key as the credentials last as long
        var sessionToken: String = ""
        // instance service expects absoluteString as uri...
        return request(uri:InstanceMetaDataServiceProvider.apiTokenURL, method: .PUT, headers:["X-aws-ec2-metadata-token-ttl-seconds":"21600"], timeout: 2, eventLoopGroup: eventLoopGroup)
            .flatMapThrowing { response in
                // extract session key from response
                guard response.head.status == .ok,
                    let token = String(data: response.body, encoding: .utf8) else { throw MetaDataServiceError.couldNotGetInstanceSessionKey }
                sessionToken = token
                return token
            }
            .flatMap { token in
                // request rolename
                return self.request(uri:InstanceMetaDataServiceProvider.baseURLString, headers:["X-aws-ec2-metadata-token":token], timeout: 2, eventLoopGroup: eventLoopGroup)
            }
            .flatMapThrowing { response in
                // extract rolename
                guard response.head.status == .ok,
                    let roleName = String(data: response.body, encoding: .utf8) else { throw MetaDataServiceError.couldNotGetInstanceRoleName }
                return "\(InstanceMetaDataServiceProvider.baseURLString)/\(roleName)" }
            .flatMap { uri in
                // request credentials
                return self.request(uri: uri, headers:["X-aws-ec2-metadata-token":sessionToken], timeout: 2, eventLoopGroup: eventLoopGroup)
            }
            .flatMapThrowing { response in
                // decode credentials
                guard response.head.status == .ok else { throw MetaDataServiceError.couldNotGetInstanceMetadata }
                return self.decodeCredential(response.body)
        }
    }
}

//#endif // os(Linux)
