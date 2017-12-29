//
//  Credential.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/04/05.
//
//

import Foundation

public protocol CredentialProvider {
    var accessKeyId: String { get }
    var secretAccessKey: String { get }
    var sessionToken: String? { get }
    var expiration: Date? { get }
}

extension CredentialProvider {      
    public func isEmpty() -> Bool {
        return self.accessKeyId.isEmpty || self.secretAccessKey.isEmpty
    }

    public func nearExpiration() -> Bool {
      if let expiration = self.expiration {
        // are we within 5 minutes of expiration?
        return Date().addingTimeInterval(5.0 * 60.0) > expiration
      } else {
        return false
      }
    }
}

public struct SharedCredential: CredentialProvider {
    
    static var `default`: Credential?
    
    public let accessKeyId: String
    public let secretAccessKey: String
    public let sessionToken: String?
    public let expiration: Date? = nil

    public init(filename: String = "~/.aws/credentials", profile: String = "default") throws {
        fatalError("Umimplemented")
        //let content = try String(contentsOfFile: filename)
    }
}

public struct Credential: CredentialProvider {
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
}

struct EnvironementCredential: CredentialProvider {
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String?
    let expiration: Date? = nil
    
    init?() {
        guard let accessKeyId = ProcessInfo.processInfo.environment["AWS_ACCESS_KEY_ID"] else {
            return nil
        }
        guard let secretAccessKey = ProcessInfo.processInfo.environment["AWS_SECRET_ACCESS_KEY"] else {
            return nil
        }
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = ProcessInfo.processInfo.environment["AWS_SESSION_TOKEN"]
    }
}

