//
//  Credential.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/04/05.
//
//

import Foundation
import INIParser

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

    /// Errors occurring when initializing a SharedCredential
    ///
    /// - missingProfile: If the profile requested was not found
    /// - missingAccessKeyId: If the access key ID was not found
    /// - missingSecretAccessKey: If the secret access key was not found
    public enum SharedCredentialError: Error {
        case missingProfile(String)
        case missingAccessKeyId
        case missingSecretAccessKey
    }

    public let accessKeyId: String
    public let secretAccessKey: String
    public let sessionToken: String?
    public let expiration: Date? = nil

    public init(filename: String = "~/.aws/credentials", profile: String = "default") throws {
        // Expand tilde before parsing the file
        let filename = NSString(string: filename).expandingTildeInPath
        let contents = try INIParser(filename).sections
        guard let config = contents[profile] else {
            throw SharedCredentialError.missingProfile(profile)
        }
        guard let accessKeyId = config["aws_access_key_id"] else {
            throw SharedCredentialError.missingAccessKeyId
        }
        self.accessKeyId = accessKeyId
        guard let secretAccessKey = config["aws_secret_access_key"] else {
            throw SharedCredentialError.missingSecretAccessKey
        }
        self.secretAccessKey = secretAccessKey
        self.sessionToken = config["aws_session_token"]
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
