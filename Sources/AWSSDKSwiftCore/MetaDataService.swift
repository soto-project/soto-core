//
//  MetaDataService.swift
//  SwiftAWSDynamodb
//
//  Created by Yuki Takei on 2017/07/12.
//
//

import Foundation
// import Prorsum

enum MetaDataServiceError: Error {
    case missingRequiredParam(String)
    case couldNotGetInstanceRoleName
    case connectionTimeout
}

struct MetaDataService {

    static var containerCredentialsUri = ProcessInfo.processInfo.environment["AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"]
    static let instanceMetadataUri = "/latest/meta-data/iam/security-credentials/"

    static var serviceHost: MetaDataServiceHost {
      get {
        if containerCredentialsUri != nil {
          return .ecsCredentials(containerCredentialsUri!)
        } else {
          return .instanceProfileCredentials(instanceMetadataUri)
        }
      }
    }

    enum MetaDataServiceHost {
        case ecsCredentials(String)
        case instanceProfileCredentials(String)

        var baseURLString: String {
            switch self {
              case .ecsCredentials(let containerCredentialsUri):
                return "http://169.254.170.2\(containerCredentialsUri)"
              case .instanceProfileCredentials(let instanceMetadataUri):
                return "http://169.254.169.254\(instanceMetadataUri)"
            }
        }

        func url() throws -> URL {
          switch self {
          case .ecsCredentials:
            return URL(string: baseURLString)!
          case .instanceProfileCredentials:
            let roleName = try getRoleName()
            return URL(string: "\(baseURLString)/\(roleName)")!
          }
        }

        func getRoleName() throws -> String {
            let response = try MetaDataService.request(url: URL(string: baseURLString)!, timeout: 2)
            switch response.statusCode {
            case 200:
                return String(data: response.body.asData(), encoding: .utf8) ?? ""
            default:
                throw MetaDataServiceError.couldNotGetInstanceRoleName
            }
        }
    }

    private static func request(url: URL, timeout: TimeInterval) throws -> Response {

        let chan = Channel<(Response?, Error?)>.make(capacity: 1)
        go {
            do {
                let client = try HTTPClient(url: url)
                try client.open()
                let response = try client.request()
                try chan.send((response, nil))
            } catch {
                do { try chan.send((nil, error)) } catch {}
            }
        }

        var response: Response?
        var error: Error?
        let endAt = Date().addingTimeInterval(timeout)

        forSelect { done in
            when(chan) { res, err in
                response = res
                error = err
                chan.close()
                done()
            }

            otherwise {
                if Date() > endAt {
                    error = MetaDataServiceError.connectionTimeout
                    chan.close()
                    done()
                }
            }
        }

        if let e = error {
            throw e
        }

        return response!
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

    func getCredential() throws -> Credential {
        let response = try MetaDataService.request(url: MetaDataService.serviceHost.url(), timeout: 2)
        let metaData = try JSONDecoder().decode(MetaDataService.MetaData.self, from: response.body.asData())
        return metaData.credential
    }
}

extension MetaDataService.MetaData {
  init(from decoder: Decoder) throws {

    let values = try decoder.container(keyedBy: CodingKeys.self)

    switch MetaDataService.serviceHost {

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

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
    dateFormatter.timeZone = TimeZone(identifier: "UTC")
    guard let date = dateFormatter.date(from: expiration) else {
       fatalError("ERROR: Date conversion failed due to mismatched format.")
    }
    self.expiration = date
  }
}
