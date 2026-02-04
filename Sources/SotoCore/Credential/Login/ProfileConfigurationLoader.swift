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
    /// - Returns: LoginConfiguration
    func loadConfiguration(
        profileName: String? = nil,
        cacheDirectoryOverride: String? = nil
    ) throws -> LoginConfiguration {
        let profile = profileName ?? "default"

        // Load profile from ~/.aws/config
        let profileData = try loadProfile(name: profile)

        // login_session is mandatory
        guard let loginSession = profileData["login_session"] else {
            throw LoginError.loginSessionMissing
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

    private func loadProfile(name: String) throws -> [String: String] {
        // Construct path to ~/.aws/config
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let configPath = homeDir.appendingPathComponent(".aws").appendingPathComponent("config")

        // Read config file
        guard let configContent = try? String(contentsOf: configPath, encoding: .utf8) else {
            throw LoginError.configFileNotFound(configPath.path)
        }

        // Parse INI file
        let parser = try INIParser(configContent)

        // Look for profile - try both "profile name" and "name" formats
        // AWS config uses [default] for default profile and [profile name] for others
        let profileKey = name == "default" ? name : "profile \(name)"

        guard let profileSection = parser.sections[profileKey] else {
            throw LoginError.profileNotFound(name)
        }

        return profileSection
    }

    private func constructEndpoint(region: Region) -> String {
        "\(region.rawValue).\(LoginConfiguration.loginServiceHostPrefix).aws.amazon.com"
    }
}
