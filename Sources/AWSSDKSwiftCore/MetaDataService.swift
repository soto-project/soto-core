//
//  MetaDataService.swift
//  SwiftAWSDynamodb
//
//  Created by Yuki Takei on 2017/07/12.
//
//

import Foundation
import Prorsum

enum MetaDataServiceError: Error {
    case missingRequiredParam(String)
    case couldNotGetInstanceRoleName
    case connectionTimeout
}

struct MetaDataService {
  
    static var container_credentials_uri = ProcessInfo.processInfo.environment["AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"]
    static let instance_metadata_uri = "/latest/meta-data/iam/security-credentials/"
    
    static var serviceHost: MetaDataServiceHost { 
      get {
        if container_credentials_uri != nil {
          return .ECSCredentials(container_credentials_uri!)
        } else { 
          return .InstanceProfileCredentials(instance_metadata_uri)
        }
      }      
    }
  
    enum MetaDataServiceHost {
        case ECSCredentials(String)
        case InstanceProfileCredentials(String)
        
        var baseURLString: String {
            switch self {
              case .ECSCredentials(let container_credentials_uri):
                return "http://169.254.170.2\(container_credentials_uri)"
              case .InstanceProfileCredentials(let instance_metadata_uri):
                return "http://169.254.169.254\(instance_metadata_uri)"
            }
        }
        
        func url() throws -> URL {
          switch self {
          case .ECSCredentials:
            return URL(string: baseURLString)!
          case .InstanceProfileCredentials:
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

    struct MetaData {
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

        init(dictionary: [String: Any]) throws {
            switch MetaDataService.serviceHost {
            case .ECSCredentials:
              self.code = nil
              self.lastUpdated = nil
              self.type = nil

              guard let roleArn = dictionary["RoleArn"] as? String else {
                  throw MetaDataServiceError.missingRequiredParam("RoleArn")
              }
              self.roleArn = roleArn

            case .InstanceProfileCredentials:
              self.roleArn = nil

              guard let code = dictionary["Code"] as? String else {
                  throw MetaDataServiceError.missingRequiredParam("Code")
              }

              guard let lastUpdated = dictionary["LastUpdated"] as? String else {
                  throw MetaDataServiceError.missingRequiredParam("LastUpdated")
              }

              guard let type = dictionary["Type"] as? String  else {
                  throw MetaDataServiceError.missingRequiredParam("Type")
              }

              self.code = code
              self.lastUpdated = lastUpdated
              self.type = type
            }

            guard let accessKeyId = dictionary["AccessKeyId"] as? String  else {
                throw MetaDataServiceError.missingRequiredParam("AccessKeyId")
            }

            guard let secretAccessKey = dictionary["SecretAccessKey"] as? String  else {
                throw MetaDataServiceError.missingRequiredParam("SecretAccessKey")
            }

            guard let token = dictionary["Token"] as? String  else {
                throw MetaDataServiceError.missingRequiredParam("Token")
            }

            guard let expiration = dictionary["Expiration"] as? String  else {
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

    func getCredential() throws -> Credential {
        let response = try MetaDataService.request(url: MetaDataService.serviceHost.url(), timeout: 2)
        let body: [String: Any] = try JSONSerialization.jsonObject(with: response.body.asData(), options: []) as? [String: Any] ?? [:]
        let metadata = try MetaData(dictionary: body)

        return metadata.credential
    }
}
