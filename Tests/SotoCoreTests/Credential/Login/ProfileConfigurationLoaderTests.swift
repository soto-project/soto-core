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

// Profile Configuration Loader Tests

import Foundation
import SotoCore
import Testing

@testable import SotoCore

@Suite("Profile Configuration Loader", .serialized)
struct ProfileConfigurationLoaderTests {

    // Helper to create a temp config file
    func createTempConfigFile(content: String) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let configPath = tempDir.appendingPathComponent("config")
        try content.write(to: configPath, atomically: true, encoding: .utf8)
        return configPath.path
    }

    func removeTempFile(_ path: String) {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("Load configuration with missing profile throws error")
    func loadConfigurationMissingProfile() throws {
        let configContent = """
            [default]
            login_session = test-session
            """

        let configPath = try createTempConfigFile(content: configContent)
        defer { removeTempFile(configPath) }

        let loader = ProfileConfigurationLoader()

        // Trying to load a non-existent profile should throw profileNotFound error
        do {
            _ = try loader.loadConfiguration(
                profileName: "nonexistent",
                cacheDirectoryOverride: nil,
                configPath: configPath
            )
            Issue.record("Expected profileNotFound error")
        } catch let error as AWSLoginCredentialError {
            #expect(error.code == "profileNotFound")
            #expect(error.message.contains("nonexistent"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Load configuration with valid default profile")
    func loadConfigurationDefaultProfile() throws {
        let configContent = """
            [default]
            login_session = test-session-123
            region = us-west-2
            """

        let configPath = try createTempConfigFile(content: configContent)
        defer { removeTempFile(configPath) }

        let loader = ProfileConfigurationLoader()
        let config = try loader.loadConfiguration(
            profileName: nil,
            cacheDirectoryOverride: nil,
            configPath: configPath
        )

        #expect(config.loginSession == "test-session-123")
        #expect(config.region == .uswest2)
        #expect(config.endpoint == "us-west-2.signin.aws.amazon.com")
    }

    @Test("Load configuration with named profile")
    func loadConfigurationNamedProfile() throws {
        let configContent = """
            [default]
            login_session = default-session

            [profile dev]
            login_session = dev-session-456
            region = eu-west-1
            """

        let configPath = try createTempConfigFile(content: configContent)
        defer { removeTempFile(configPath) }

        let loader = ProfileConfigurationLoader()
        let config = try loader.loadConfiguration(
            profileName: "dev",
            cacheDirectoryOverride: nil,
            configPath: configPath
        )

        #expect(config.loginSession == "dev-session-456")
        #expect(config.region == .euwest1)
        #expect(config.endpoint == "eu-west-1.signin.aws.amazon.com")
    }

    @Test("Load configuration with missing login_session throws error")
    func loadConfigurationMissingLoginSession() throws {
        let configContent = """
            [default]
            region = us-east-1
            """

        let configPath = try createTempConfigFile(content: configContent)
        defer { removeTempFile(configPath) }

        let loader = ProfileConfigurationLoader()

        // Should throw loginSessionMissing error
        do {
            _ = try loader.loadConfiguration(
                profileName: nil,
                cacheDirectoryOverride: nil,
                configPath: configPath
            )
            Issue.record("Expected loginSessionMissing error")
        } catch let error as AWSLoginCredentialError {
            #expect(error.code == "loginSessionMissing")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Load configuration uses AWS_REGION env var when profile has no region")
    func loadConfigurationUsesEnvRegion() throws {
        let configContent = """
            [default]
            login_session = test-session
            """

        let configPath = try createTempConfigFile(content: configContent)
        defer { removeTempFile(configPath) }

        let originalRegion = ProcessInfo.processInfo.environment["AWS_REGION"]
        setenv("AWS_REGION", "ap-southeast-1", 1)
        defer {
            if let region = originalRegion {
                setenv("AWS_REGION", region, 1)
            } else {
                unsetenv("AWS_REGION")
            }
        }

        let loader = ProfileConfigurationLoader()
        let config = try loader.loadConfiguration(
            profileName: nil,
            cacheDirectoryOverride: nil,
            configPath: configPath
        )

        #expect(config.region == .apsoutheast1)
    }

    @Test("Load configuration defaults to us-east-1 when no region specified")
    func loadConfigurationDefaultsToUsEast1() throws {
        let configContent = """
            [default]
            login_session = test-session
            """

        let configPath = try createTempConfigFile(content: configContent)
        defer { removeTempFile(configPath) }

        let originalRegion = ProcessInfo.processInfo.environment["AWS_REGION"]
        unsetenv("AWS_REGION")
        defer {
            if let region = originalRegion {
                setenv("AWS_REGION", region, 1)
            }
        }

        let loader = ProfileConfigurationLoader()
        let config = try loader.loadConfiguration(
            profileName: nil,
            cacheDirectoryOverride: nil,
            configPath: configPath
        )

        #expect(config.region == .useast1)
    }

    @Test("Load configuration with cache directory override")
    func loadConfigurationWithCacheOverride() throws {
        let configContent = """
            [default]
            login_session = test-session
            region = us-east-1
            """

        let configPath = try createTempConfigFile(content: configContent)
        defer { removeTempFile(configPath) }

        let loader = ProfileConfigurationLoader()
        let config = try loader.loadConfiguration(
            profileName: nil,
            cacheDirectoryOverride: "/custom/cache/dir",
            configPath: configPath
        )

        #expect(config.cacheDirectory == "/custom/cache/dir")
    }

    @Test("Load configuration with cache directory from environment")
    func loadConfigurationWithCacheFromEnv() throws {
        let configContent = """
            [default]
            login_session = test-session
            region = us-east-1
            """

        let configPath = try createTempConfigFile(content: configContent)
        defer { removeTempFile(configPath) }

        let originalCache = ProcessInfo.processInfo.environment[LoginConfiguration.cacheEnvVar]
        setenv(LoginConfiguration.cacheEnvVar, "/env/cache/dir", 1)
        defer {
            if let cache = originalCache {
                setenv(LoginConfiguration.cacheEnvVar, cache, 1)
            } else {
                unsetenv(LoginConfiguration.cacheEnvVar)
            }
        }

        let loader = ProfileConfigurationLoader()
        let config = try loader.loadConfiguration(
            profileName: nil,
            cacheDirectoryOverride: nil,
            configPath: configPath
        )

        #expect(config.cacheDirectory == "/env/cache/dir")
    }

    @Test("Load configuration with config file not found throws error")
    func loadConfigurationFileNotFound() {
        let loader = ProfileConfigurationLoader()

        // Should throw configFileNotFound error
        do {
            _ = try loader.loadConfiguration(
                profileName: nil,
                cacheDirectoryOverride: nil,
                configPath: "/nonexistent/config"
            )
            Issue.record("Expected configFileNotFound error")
        } catch let error as AWSLoginCredentialError {
            #expect(error.code == "configFileNotFound")
            #expect(error.message.contains("/nonexistent/config"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Load configuration with multiple profiles")
    func loadConfigurationMultipleProfiles() throws {
        let configContent = """
            [default]
            login_session = default-session
            region = us-east-1

            [profile staging]
            login_session = staging-session
            region = us-west-1

            [profile production]
            login_session = prod-session
            region = eu-central-1
            """

        let configPath = try createTempConfigFile(content: configContent)
        defer { removeTempFile(configPath) }

        let loader = ProfileConfigurationLoader()

        // Test default profile
        let defaultConfig = try loader.loadConfiguration(
            profileName: nil,
            cacheDirectoryOverride: nil,
            configPath: configPath
        )
        #expect(defaultConfig.loginSession == "default-session")
        #expect(defaultConfig.region == .useast1)

        // Test staging profile
        let stagingConfig = try loader.loadConfiguration(
            profileName: "staging",
            cacheDirectoryOverride: nil,
            configPath: configPath
        )
        #expect(stagingConfig.loginSession == "staging-session")
        #expect(stagingConfig.region == .uswest1)

        // Test production profile
        let prodConfig = try loader.loadConfiguration(
            profileName: "production",
            cacheDirectoryOverride: nil,
            configPath: configPath
        )
        #expect(prodConfig.loginSession == "prod-session")
        #expect(prodConfig.region == .eucentral1)
    }

    @Test("Load configuration with profile containing extra fields")
    func loadConfigurationWithExtraFields() throws {
        let configContent = """
            [default]
            login_session = test-session
            region = us-east-1
            output = json
            cli_pager = 
            some_other_field = value
            """

        let configPath = try createTempConfigFile(content: configContent)
        defer { removeTempFile(configPath) }

        let loader = ProfileConfigurationLoader()
        let config = try loader.loadConfiguration(
            profileName: nil,
            cacheDirectoryOverride: nil,
            configPath: configPath
        )

        // Should successfully load despite extra fields
        #expect(config.loginSession == "test-session")
        #expect(config.region == .useast1)
    }

    @Test(
        "Endpoint construction for various regions",
        arguments: [
            (Region.useast1, "us-east-1.signin.aws.amazon.com"),
            (Region.euwest1, "eu-west-1.signin.aws.amazon.com"),
            (Region.apsoutheast2, "ap-southeast-2.signin.aws.amazon.com"),
        ]
    )
    func endpointConstruction(region: Region, expectedEndpoint: String) throws {
        // Test endpoint construction directly
        let endpoint = "\(region.rawValue).\(LoginConfiguration.loginServiceHostPrefix).aws.amazon.com"
        #expect(endpoint == expectedEndpoint)
    }
}
