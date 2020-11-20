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


/// Load settings from AWS credentials and profile configuration files
/// https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html
///
struct ConfigFileLoader {
    /// Profile Config loaded from file
    struct ProfileConfig: Equatable {
        let region: String?
        let roleArn: String?
        let roleSessionName: String?
        let sourceProfile: String?
        let credentialSource: CredentialSource?
    }

    /// Profile credential source `credential_source`
    /// - Used within Amazon EC2 instances or EC2 containers to specify where the AWS CLI can find credentials to use to assume the role you specified
    ///  with the `role_arn` parameter. You cannot specify both `source_profile` and `credential_source` in the same profile.
    enum CredentialSource: String, Equatable {
        case environment = "Environment"
        case ec2Instance = "Ec2InstanceMetadata"
        case ecsContainer = "EcsContainer"
    }

    /// Profile credentials loaded from file
    struct ProfileCredentials: Equatable {
        let accessKey: String
        let secretAccessKey: String
        let roleArn: String?
        let sourceProfile: String?
        let credentialSource: CredentialSource?
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

    /// If `role_arn` and `source_profile` are found in the settings, the settings from the source profile are also loaded and mixed in.
    /// In the scenario that a setting does exist in both profiles, the setting from `profile` will take precedence.
    ///
    /// >  `source_profile` specifies a named profile with long-term credentials that the AWS CLI can use to assume
    /// >  a role that you specified with the `role_arn` parameter. You cannot specify both `source_profile` and
    /// >  `credential_source` in the same profile.

    //********************


    /// Load profile configuraton from a file (passed in as byte-buffer), usually `~/.aws/config`.
    ///
    /// - Parameters:
    ///   - byteBuffer: contents of the file to parse
    ///   - profile: AWS named profile to load (usually `default`)
    /// - Returns: Combined profile settings
    static func loadProfileConfig(from byteBuffer: ByteBuffer, for profile: String = "default") throws -> ProfileConfig {
        guard let content = byteBuffer.getString(at: 0, length: byteBuffer.readableBytes) else {
            throw ConfigFileError.invalidCredentialFileSyntax
        }
        let parser: INIParser
        do {
            parser = try INIParser(content)
        } catch INIParser.Error.invalidSyntax {
            throw ConfigFileError.invalidCredentialFileSyntax
        }

        let loadedProfile = profile == "default" ? profile : "profile \(profile)"

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

    /// Load profile settings from a file (passed in as byte-buffer), usually `~/.aws/credentials` or `~/.aws/config`.
    ///
    /// If `role_arn` and `source_profile` are found in the settings, the settings from the source profile are also loaded and mixed in.
    /// In the scenario that a setting does exist in both profiles, the setting from `profile` will take precedence.
    ///
    /// >  `source_profile` specifies a named profile with long-term credentials that the AWS CLI can use to assume
    /// >  a role that you specified with the `role_arn` parameter. You cannot specify both `source_profile` and
    /// >  `credential_source` in the same profile.
    ///
    /// - Parameters:
    ///   - byteBuffer: contents of the file to parse
    ///   - profile: AWS named profile to load (usually `default`)
    ///   - sourceProfile: specifies a named profile with long-term credentials that the AWS CLI can use to assume a role that you specified with the `role_arn` parameter.
    /// - Returns: Combined profile settings
    static func loadCredentials(from byteBuffer: ByteBuffer, for profile: String, sourceProfile: String?) throws -> [String: String] {
        guard let content = byteBuffer.getString(at: 0, length: byteBuffer.readableBytes) else {
            throw ConfigFileError.invalidCredentialFileSyntax
        }
        var parser: INIParser
        do {
            parser = try INIParser(content)
        } catch INIParser.Error.invalidSyntax {
            throw ConfigFileError.invalidCredentialFileSyntax
        }

        guard var settings = parser.sections[profile] else {
            throw ConfigFileError.missingProfile(profile)
        }

        if let sourceProfile = sourceProfile ?? settings["source_profile"] {
            guard let sourceConfig = parser.sections[sourceProfile] else {
                throw ConfigFileError.missingProfile(sourceProfile)
            }
            settings.merge(sourceConfig) { (profile, _) in profile }
        }

        return settings
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
