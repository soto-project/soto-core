//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import INIParser
import Logging
import NIO
#if os(Linux)
import Glibc
#else
import Foundation.NSString
#endif

/// Load settings from AWS credentials and profile configuration files
/// https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html
///
/// Credentials file settings have precedence over profile configuration settings
/// https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html#cli-configure-quickstart-precedence
struct ConfigFileLoader {

    static let `default` = "default"

    /// CLI credentials file – The credentials and config file are updated when you run the command aws configure. The credentials file is located
    /// at `~/.aws/credentials` on Linux or macOS, or at C:\Users\USERNAME\.aws\credentials on Windows. This file can contain the credential
    /// details for the default profile and any named profiles.
    struct ProfileCredentials: Equatable {
        let accessKey: String
        let secretAccessKey: String
        let sessionToken: String?
        let roleArn: String?
        let sourceProfile: String?
        let credentialSource: CredentialSource?
    }

    /// The credentials and config file are updated when you run the command aws configure. The config file is located at `~/.aws/config` on Linux
    /// or macOS, or at C:\Users\USERNAME\.aws\config on Windows. This file contains the configuration settings for the default profile and any named profiles.
    struct ProfileConfig: Equatable {
        let region: String?
        let roleArn: String?
        let roleSessionName: String?
        let sourceProfile: String?
        let credentialSource: CredentialSource?
    }

    /// Profile credential source `credential_source`
    ///
    /// Used within Amazon EC2 instances or EC2 containers to specify where the AWS CLI can find credentials to use to assume the role you
    /// specified with the `role_arn` parameter. You cannot specify both `source_profile` and `credential_source` in the same profile.
    enum CredentialSource: String, Equatable {
        case environment = "Environment"
        case ec2Instance = "Ec2InstanceMetadata"
        case ecsContainer = "EcsContainer"
    }

    /// Errors occurring when loading credentials and profile configuration
    ///
    /// - missingProfile: If the profile requested was not found
    /// - missingAccessKeyId: If the access key ID was not found
    /// - missingSecretAccessKey: If the secret access key was not found
    enum ConfigFileError: Error, Equatable {
        case invalidCredentialFileSyntax
        case missingProfile(String)
        case missingAccessKeyId
        case missingSecretAccessKey
    }

    /// Load profile configuraton from a file (passed in as byte-buffer), usually `~/.aws/config`
    ///
    /// - Parameters:
    ///   - byteBuffer: contents of the file to parse
    ///   - profile: AWS named profile to load (usually `default`)
    /// - Returns: Combined profile settings
    static func loadProfileConfig(from byteBuffer: ByteBuffer, for profile: String) throws -> ProfileConfig {
        guard let content = byteBuffer.getString(at: 0, length: byteBuffer.readableBytes) else {
            throw ConfigFileError.invalidCredentialFileSyntax
        }
        let parser: INIParser
        do {
            parser = try INIParser(content)
        } catch INIParser.Error.invalidSyntax {
            throw ConfigFileError.invalidCredentialFileSyntax
        }

        // The credentials file uses a different naming format than the CLI config file for named profiles. Include
        // the prefix word "profile" only when configuring a named profile in the config file. Do not use the word
        // profile when creating an entry in the credentials file.
        // https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html
        let loadedProfile = profile == Self.default ? profile : "profile \(profile)"

        guard let settings = parser.sections[loadedProfile] else {
            throw ConfigFileError.missingProfile(loadedProfile)
        }

        // All values are optional for profile configuration
        return ProfileConfig(
            region: settings["region"],
            roleArn: settings["role_arn"],
            roleSessionName: settings["role_session_name"],
            sourceProfile: settings["source_profile"],
            credentialSource: settings["credential_source"].flatMap(CredentialSource.init(rawValue:))
        )
    }

    /// Load profile credentials from a file (passed in as byte-buffer), usually `~/.aws/credentials`
    ///
    /// If `source_profile` is passed in, or found in the settings, credentials will be loaded from the source profile for use with STS Assume Role.
    ///
    /// - Parameters:
    ///   - byteBuffer: contents of the file to parse
    ///   - profile: AWS named profile to load (usually `default`)
    ///   - sourceProfile: specifies a named profile with long-term credentials that the AWS CLI can use to assume a role that you specified with the `role_arn` parameter.
    /// - Returns: Combined profile credentials
    static func loadCredentials(from byteBuffer: ByteBuffer, for profile: String, sourceProfile: String?) throws -> ProfileCredentials {
        guard let content = byteBuffer.getString(at: 0, length: byteBuffer.readableBytes) else {
            throw ConfigFileError.invalidCredentialFileSyntax
        }
        var parser: INIParser
        do {
            parser = try INIParser(content)
        } catch INIParser.Error.invalidSyntax {
            throw ConfigFileError.invalidCredentialFileSyntax
        }

        guard let settings = parser.sections[profile] else {
            throw ConfigFileError.missingProfile(profile)
        }

        var profileAccessKey = settings["aws_access_key_id"]
        var profileSecretAccessKey = settings["aws_secret_access_key"]
        var profileSessionToken = settings["aws_session_token"]

        if let sourceProfile = sourceProfile ?? settings["source_profile"] {
            guard let sourceSettings = parser.sections[sourceProfile] else {
                throw ConfigFileError.missingProfile(sourceProfile)
            }
            profileAccessKey = sourceSettings["aws_access_key_id"]
            profileSecretAccessKey = sourceSettings["aws_secret_access_key"]
            profileSessionToken = sourceSettings["aws_session_token"]
        }

        guard let accessKey = profileAccessKey else {
            throw ConfigFileError.missingAccessKeyId
        }
        guard let secretAccessKey = profileSecretAccessKey else {
            throw ConfigFileError.missingSecretAccessKey
        }

        return ProfileCredentials(
            accessKey: accessKey,
            secretAccessKey: secretAccessKey,
            sessionToken: profileSessionToken,
            roleArn: settings["role_arn"],
            sourceProfile: sourceProfile ?? settings["source_profile"],
            credentialSource: settings["credential_source"].flatMap(CredentialSource.init(rawValue:))
        )
    }

    static func expandTildeInFilePath(_ filePath: String) -> String {
        #if os(Linux)
        // We don't want to add more dependencies on Foundation than needed.
        // For this reason we get the expanded filePath on Linux from libc.
        // Since `wordexp` and `wordfree` are not available on iOS we stay
        // with NSString on Darwin.
        return filePath.withCString { (ptr) -> String in
            var wexp = wordexp_t()
            guard wordexp(ptr, &wexp, 0) == 0, let we_wordv = wexp.we_wordv else {
                return filePath
            }
            defer {
                wordfree(&wexp)
            }

            guard let resolved = we_wordv[0], let pth = String(cString: resolved, encoding: .utf8) else {
                return filePath
            }

            return pth
        }
        #elseif os(macOS)
        // can not use wordexp on macOS because for sandboxed application wexp.we_wordv == nil
        guard let home = getpwuid(getuid())?.pointee.pw_dir,
            let homePath = String(cString: home, encoding: .utf8)
        else {
            return filePath
        }
        return filePath.starts(with: "~") ? homePath + filePath.dropFirst() : filePath
        #else
        return NSString(string: filePath).expandingTildeInPath
        #endif
    }

}
