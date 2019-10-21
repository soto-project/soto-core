//
//  Credential.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/04/05.
//
//

import Foundation
import INIParser

/// Protocol defining requirements for object providing AWS credentials
public protocol CredentialProvider {
    var accessKeyId: String { get }
    var secretAccessKey: String { get }
    var sessionToken: String? { get }
    var expiration: Date? { get }
}

extension CredentialProvider {
    func isEmpty() -> Bool {
        return self.accessKeyId.isEmpty || self.secretAccessKey.isEmpty
    }

    func nearExpiration() -> Bool {
        if let expiration = self.expiration {
            // are we within 5 minutes of expiration?
            return Date().addingTimeInterval(5.0 * 60.0) > expiration
        } else {
            return false
        }
    }
}

/// Provide AWS credentials directly
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

/// Protocol for parsing AWS credential configs
protocol SharedCredentialsConfigParser {
    /// Parse a specified file
    ///
    /// - Parameter filename: The path to the file
    /// - Returns: A dictionary of dictionaries where the key is each profile
    /// and the value is the fields and values within that profile
    /// - Throws: If the file cannot be parsed
    func parse(filename: String) throws -> [String: [String:String]]
}

/// An implementation of SharedCredentialsConfigParser that uses INIParser
class IniConfigParser: SharedCredentialsConfigParser {
    func parse(filename: String) throws -> [String : [String : String]] {
        return try INIParser(filename).sections
    }
}

/// Provide AWS credentials via the ~/.aws/credential file
public struct SharedCredential: CredentialProvider {

    /// Errors occurring when initializing a SharedCredential
    ///
    /// - missingProfile: If the profile requested was not found
    /// - missingAccessKeyId: If the access key ID was not found
    /// - missingSecretAccessKey: If the secret access key was not found
    public enum SharedCredentialError: Error, Equatable {
        case missingProfile(String)
        case missingAccessKeyId
        case missingSecretAccessKey
    }

    public let accessKeyId: String
    public let secretAccessKey: String
    public let sessionToken: String?
    public let expiration: Date? = nil

    public init(filename: String = "~/.aws/credentials",
                profile: String = "default") throws {
        try self.init(
            filename: filename,
            profile: profile,
            parser: IniConfigParser()
        )
    }

    init(filename: String, profile: String, parser: SharedCredentialsConfigParser) throws {
        // Expand tilde before parsing the file
        let filename = NSString(string: filename).expandingTildeInPath
        let contents = try parser.parse(filename: filename)
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

/// Provide AWS credentials via environment variables
public struct EnvironmentCredential: CredentialProvider {
    public let accessKeyId: String
    public let secretAccessKey: String
    public let sessionToken: String?
    public let expiration: Date? = nil

    public init?() {
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
