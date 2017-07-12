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
    struct MetaData {
        let code: String
        let lastUpdated: String
        let type: String
        let accessKeyId: String
        let secretAccessKey: String
        let token: String
        let expiration: String
        
        var credential: Credential {
            return Credential(
                accessKeyId: accessKeyId,
                secretAccessKey: secretAccessKey,
                sessionToken: token
            )
        }
        
        init(dictionary: [String: Any]) throws {
            guard let code = dictionary["Code"] as? String else {
                throw MetaDataServiceError.missingRequiredParam("Code")
            }
            
            guard let lastUpdated = dictionary["LastUpdated"] as? String else {
                throw MetaDataServiceError.missingRequiredParam("LastUpdated")
            }
            
            guard let type = dictionary["Type"] as? String  else {
                throw MetaDataServiceError.missingRequiredParam("Type")
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
            
            self.code = code
            self.lastUpdated = lastUpdated
            self.type = type
            self.accessKeyId = accessKeyId
            self.secretAccessKey = secretAccessKey
            self.token = token
            self.expiration = expiration
        }
    }
    
    let host = "169.254.169.254"
    
    var urlString: String {
        return "http://\(host)/latest/meta-data/iam/security-credentials/"
    }
    
    private func request(url: URL, timeout: TimeInterval) throws -> Response {
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
    
    func getRoleName() throws -> String {
        let response = try request(url: URL(string: self.urlString)!, timeout: 2)
        switch response.statusCode {
        case 200:
            return String(data: response.body.asData(), encoding: .utf8) ?? ""
        default:
            throw MetaDataServiceError.couldNotGetInstanceRoleName
        }
    }
    
    func getCredential() throws -> Credential {
        let roleName = try getRoleName()
        let url = URL(string: "\(urlString)/\(roleName)")!
        let response = try request(url: url, timeout: 2)
        let body: [String: Any] = try JSONSerialization.jsonObject(with: response.body.asData(), options: []) as? [String: Any] ?? [:]
        let metadata = try MetaData(dictionary: body)
        
        return metadata.credential
    }
}
