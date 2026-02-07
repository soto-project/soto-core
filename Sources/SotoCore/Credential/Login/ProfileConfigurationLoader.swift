//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// Profile Configuration Loader

import Foundation
import INIParser

struct ProfileConfigurationLoader {
    /// Load configuration from profile
    /// - Parameters:
    ///   - profileName: Name of the profile (defaults to "default")
    ///   - cacheDirectoryOverride: Optional override for cache directory
    ///   - configPath: Optional path to config file (defaults to ~/.aws/config)
    /// - Returns: LoginConfiguration
    func loadConfiguration(
        profileName: String? = nil,
        cacheDirectoryOverride: String? = nil,
        configPath: String? = nil
    ) throws -> LoginConfiguration {
        let profile = profileName ?? "default"

        // Load profile from config file
        let profileData = try loadProfile(name: profile, configPath: configPath)

        // login_session is mandatory
        guard let loginSession = profileData["login_session"] else {
            throw AWSLoginCredentialError.loginSessionMissing
        }

        // region is optional - check profile, then AWS_REGION env var, then default to us-east-1
        let region: Region
        if let regionString = profileData["region"] {
            region = Region(rawValue: regionString)
        } else if let envRegion = ProcessInfo.processInfo.environment["AWS_REGION"] {
            region = Region(rawValue: envRegion)
        } else {
            region = .useast1
        }

        // Check environment for cache directory override
        let cacheDir = cacheDirectoryOverride ?? ProcessInfo.processInfo.environment[LoginConfiguration.cacheEnvVar]

        let endpoint = constructEndpoint(region: region)

        return LoginConfiguration(
            endpoint: endpoint,
            loginSession: loginSession,
            region: region,
            cacheDirectory: cacheDir
        )
    }

    private func loadProfile(name: String, configPath: String?) throws -> [String: String] {
        // Use provided path or construct default path to ~/.aws/config
        let path: String
        if let configPath = configPath {
            path = configPath
        } else {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            path = homeDir.appendingPathComponent(".aws").appendingPathComponent("config").path
        }

        // Read config file
        guard let configContent = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw AWSLoginCredentialError.configFileNotFound(path)
        }

        // Parse INI file
        let parser = try INIParser(configContent)

        // Look for profile - try both "profile name" and "name" formats
        // AWS config uses [default] for default profile and [profile name] for others
        let profileKey = name == "default" ? name : "profile \(name)"

        guard let profileSection = parser.sections[profileKey] else {
            throw AWSLoginCredentialError.profileNotFound(name)
        }

        return profileSection
    }

    private func constructEndpoint(region: Region) -> String {
        "\(region.rawValue).\(LoginConfiguration.loginServiceHostPrefix).aws.amazon.com"
    }
}
