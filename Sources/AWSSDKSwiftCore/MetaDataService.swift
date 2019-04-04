//
//  MetaDataService.swift
//  SwiftAWSDynamodb
//
//  Created by Yuki Takei on 2017/07/12.
//
//

import Foundation
import NIO
import NIOHTTP1

enum MetaDataServiceError: Error {
    case missingRequiredParam(String)
    case couldNotGetInstanceRoleName
    case connectionTimeout
}

struct MetaDataService {

    static var containerCredentialsUri = ProcessInfo.processInfo.environment["AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"]
    static let instanceMetadataUri = "/latest/meta-data/iam/security-credentials/"

    static var serviceProvider: MetaDataServiceProvider {
        get {
          if containerCredentialsUri != nil {
              return .ecsCredentials(containerCredentialsUri!)
          } else {
              return .instanceProfileCredentials(instanceMetadataUri)
          }
        }
    }

    enum MetaDataServiceProvider {
        case ecsCredentials(String)
        case instanceProfileCredentials(String)

        var host: String {
            switch self {
              case .ecsCredentials:
                  return "169.254.170.2"
              case .instanceProfileCredentials:
                  return "169.254.169.254"
            }
        }

        var baseURLString: String {
            switch self {
              case .ecsCredentials(let containerCredentialsUri):
                  return "http://\(host)\(containerCredentialsUri)"
              case .instanceProfileCredentials(let instanceMetadataUri):
                  return "http://\(host)\(instanceMetadataUri)"
            }
        }

        func uri() throws -> Future<String> {
            switch self {
            case .ecsCredentials(let containerCredentialsUri):
                return AWSClient.eventGroup.next().makeSucceededFuture(containerCredentialsUri)
            case .instanceProfileCredentials:
                // instance service expects absoluteString as uri...
                return MetaDataService.request(host: host, uri: baseURLString, timeout: 2).flatMapThrowing{ response in
                    switch response.head.status {
                    case .ok:
                        let roleName = String(data: response.body, encoding: .utf8) ?? ""
                        return "\(self.baseURLString)/\(roleName)"
                    default:
                        throw MetaDataServiceError.couldNotGetInstanceRoleName
                    }

                }
            }
        }
    }

    public static func getCredential() throws -> Future<CredentialProvider> {
        let futurUri = try serviceProvider.uri()

        return futurUri.flatMap { uri -> Future<Response> in
            return request(host: serviceProvider.host, uri: uri, timeout: 2)
        }.map{ credentialResponse -> CredentialProvider in
            do {
                let metaData = try JSONDecoder().decode(MetaData.self, from: credentialResponse.body)
                return metaData.credential
            } catch {
                return Credential(accessKeyId: "", secretAccessKey: "")
            }
        }
    }

    static func request(host: String, uri: String, timeout: TimeInterval) -> Future<Response> {
        let client = HTTPClient(hostname: host, port: 80)
        let head = HTTPRequestHead(
                     version: HTTPVersion(major: 1, minor: 1),
                     method: .GET,
                     uri: uri
                   )
        let request = Request(head: head, body: Data())
        let futureResponse = client.connect(request)

        futureResponse.whenComplete { _ in
            client.close { error in
                if let error = error {
                    print("Error closing connection: \(error)")
                }
            }
        }

        return futureResponse
    }

    struct MetaData: Codable {
        let accessKeyId: String
        let secretAccessKey: String
        let token: String
        let expiration: Date

        let code: String?
        let lastUpdated: String?
        let type: String?
        let roleArn: String?

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
            case roleArn = "RoleArn"
        }
    }

}

extension MetaDataService.MetaData {
    init(from decoder: Decoder) throws {

      let values = try decoder.container(keyedBy: CodingKeys.self)

      switch MetaDataService.serviceProvider {

      case .ecsCredentials:
          self.code = nil
          self.lastUpdated = nil
          self.type = nil

          guard let roleArn = try? values.decode(String.self, forKey: .roleArn) else {
              throw MetaDataServiceError.missingRequiredParam("RoleArn")
          }
          self.roleArn = roleArn

      case .instanceProfileCredentials:
          self.roleArn = nil

          guard let code = try? values.decode(String.self, forKey: .code) else {
              throw MetaDataServiceError.missingRequiredParam("Code")
          }

          guard let lastUpdated = try? values.decode(String.self, forKey: .lastUpdated) else {
              throw MetaDataServiceError.missingRequiredParam("LastUpdated")
          }

          guard let type = try? values.decode(String.self, forKey: .type) else {
              throw MetaDataServiceError.missingRequiredParam("Type")
          }

          self.code = code
          self.lastUpdated = lastUpdated
          self.type = type
      }

      guard let accessKeyId = try? values.decode(String.self, forKey: .accessKeyId) else {
          throw MetaDataServiceError.missingRequiredParam("AccessKeyId")
      }

      guard let secretAccessKey = try? values.decode(String.self, forKey: .secretAccessKey) else {
          throw MetaDataServiceError.missingRequiredParam("SecretAccessKey")
      }

      guard let token = try? values.decode(String.self, forKey: .token) else {
          throw MetaDataServiceError.missingRequiredParam("Token")
      }

      guard let expiration = try? values.decode(String.self, forKey: .expiration) else {
          throw MetaDataServiceError.missingRequiredParam("Expiration")
      }

      self.accessKeyId = accessKeyId
      self.secretAccessKey = secretAccessKey
      self.token = token

      // ISO8601DateFormatter and DateFormatter inherit from Formatter, which does not have the methods we need.
      if #available(OSX 10.12, *) {
          let dateFormatter = ISO8601DateFormatter()
          guard let date = dateFormatter.date(from: expiration) else {
              fatalError("ERROR: Date conversion failed due to mismatched format.")
          }
          self.expiration = date
      } else {
          let dateFormatter = DateFormatter()
          dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
          dateFormatter.timeZone = TimeZone(identifier: "UTC")
          guard let date = dateFormatter.date(from: expiration) else {
              fatalError("ERROR: Date conversion failed due to mismatched format.")
          }
          self.expiration = date
      }

    }
}
