//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import INIParser
import struct Foundation.Date
import class  Foundation.ProcessInfo
import class  Foundation.NSString

extension Credential {
    func isEmpty() -> Bool {
        return self.accessKeyId.isEmpty || self.secretAccessKey.isEmpty
    }
}

/// Provide AWS credentials directly
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
        if let expiration = self.expiration {
            // are we within 5 minutes of expiration?
            return Date().addingTimeInterval(5.0 * 60.0) > expiration
        } else {
            return false
        }
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
public struct SharedCredential: Credential {

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
