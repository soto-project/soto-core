//
//  MetaDataService.swift
//  SwiftAWSDynamodb
//
//  Created by Yuki Takei on 2017/07/12.
//
//

import AsyncHTTPClient
import AWSSigner
import Foundation
import NIO
import NIOFoundationCompat
import NIOHTTP1

/// errors returned by metadata service
enum MetaDataServiceError: Error {
    case failedToDecode
    case couldNotGetInstanceRoleName
}

/// Object managing accessing of AWS credentials from various sources
struct MetaDataService {

    /// return future holding a credential provider
    static func getCredential(httpClient: AWSHTTPClient) -> Future<CredentialProvider> {
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
    func getCredential(httpClient: AWSHTTPClient) -> Future<CredentialProvider>
}

extension MetaDataServiceProvider {

    /// make HTTP request
    func request(url: String, timeout: TimeInterval, httpClient: AWSHTTPClient) -> Future<AWSHTTPResponse> {
        let request = AWSHTTPRequest(url: URL(string: url)!, method: .GET, headers: [:], body: nil)
        let futureResponse = httpClient.execute(request: request, timeout: TimeAmount.seconds(2))
        return futureResponse
    }

    /// decode response return by metadata service
    func decodeCredential(_ data: Data) -> CredentialProvider? {
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

    func getCredential(httpClient: AWSHTTPClient) -> Future<CredentialProvider> {
        return request(url: url, timeout: 2, httpClient: httpClient)
            .flatMapThrowing { response in
                if let body = response.body,
                    let data = body.getData(at: body.readerIndex, length: body.readableBytes, byteTransferStrategy: .noCopy),
                    let credential = self.decodeCredential(data) {
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

    static let instanceMetadataUri = "/latest/meta-data/iam/security-credentials/"
    static var host = "169.254.169.254"
    static var baseURLString: String {
        return "http://\(host)\(instanceMetadataUri)"
    }

    func uri(httpClient: AWSHTTPClient) -> Future<String> {
        // instance service expects absoluteString as uri...
        return request(url:InstanceMetaDataServiceProvider.baseURLString, timeout: 2, httpClient: httpClient)
            .flatMapThrowing{ response in
                switch response.status {
                case .ok:
                    if let body = response.body, let roleName = body.getString(at: body.readerIndex, length: body.readableBytes, encoding: .utf8) {
                        return "\(InstanceMetaDataServiceProvider.baseURLString)/\(roleName)"
                    }
                    return InstanceMetaDataServiceProvider.baseURLString
                default:
                    throw MetaDataServiceError.couldNotGetInstanceRoleName
                }
        }
    }

    func getCredential(httpClient: AWSHTTPClient) -> Future<CredentialProvider> {
        return uri(httpClient: httpClient)
            .flatMap { url in
                return self.request(url: url, timeout: 2, httpClient: httpClient)
            }
            .flatMapThrowing { response in
                if let body = response.body,
                    let data = body.getData(at: body.readerIndex, length: body.readableBytes, byteTransferStrategy: .noCopy),
                    let credential = self.decodeCredential(data) {
                    return credential
                } else {
                    throw MetaDataServiceError.failedToDecode
                }
        }
    }
}
