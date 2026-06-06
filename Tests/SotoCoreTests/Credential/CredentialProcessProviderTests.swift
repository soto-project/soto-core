//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if os(macOS) || os(Linux)

import AsyncHTTPClient
import Logging
import NIOCore
import NIOPosix
import Testing

@testable import SotoCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite("Credential Process Provider")
struct CredentialProcessProviderTests {
    /// swift test always runs from the project root directory.
    let testHelperPath = ".build/debug/credential-process-test-helper"
    let logger = Logger(label: "test")

    func save(content: String, prefix: String) throws -> String {
        let filepath = "\(prefix)-\(UUID().uuidString)"
        try content.write(toFile: filepath, atomically: true, encoding: .utf8)
        return filepath
    }

    // MARK: - Config Parsing

    @Test("credential_process in credentials file returns credentialProcess case")
    func credentialProcessInCredentialsFile() async throws {
        let profile = ConfigFileLoader.defaultProfile
        let credentialsFile = """
            [\(profile)]
            credential_process = /usr/bin/my-credential-helper
            """

        let credentialsPath = try save(content: credentialsFile, prefix: "creds")
        defer { try? FileManager.default.removeItem(atPath: credentialsPath) }

        let sharedCredentials = try await ConfigFileLoader.loadSharedCredentials(
            credentialsFilePath: credentialsPath,
            configFilePath: "/dev/null",
            profile: profile
        )
        guard case .credentialProcess(let command) = sharedCredentials else {
            Issue.record("Expected .credentialProcess, got \(sharedCredentials)")
            return
        }
        #expect(command == "/usr/bin/my-credential-helper")
    }

    @Test("credential_process in config file only returns credentialProcess case")
    func credentialProcessInConfigFileOnly() async throws {
        let profile = "myprofile"
        let configFile = """
            [profile \(profile)]
            credential_process = /opt/bin/get-creds
            """

        let configPath = try save(content: configFile, prefix: "configonly")
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let sharedCredentials = try await ConfigFileLoader.loadSharedCredentials(
            credentialsFilePath: "/dev/null",
            configFilePath: configPath,
            profile: profile
        )
        guard case .credentialProcess(let command) = sharedCredentials else {
            Issue.record("Expected .credentialProcess, got \(sharedCredentials)")
            return
        }
        #expect(command == "/opt/bin/get-creds")
    }

    @Test("credential_process in both files uses credentials file value")
    func credentialProcessInBothFilesCredentialsTakesPrecedence() async throws {
        let profile = ConfigFileLoader.defaultProfile
        let credentialsFile = """
            [\(profile)]
            credential_process = /from/credentials
            """
        let configFile = """
            [\(profile)]
            credential_process = /from/config
            """

        let credentialsPath = try save(content: credentialsFile, prefix: "both-creds")
        let configPath = try save(content: configFile, prefix: "both-config")
        defer {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? FileManager.default.removeItem(atPath: configPath)
        }

        let sharedCredentials = try await ConfigFileLoader.loadSharedCredentials(
            credentialsFilePath: credentialsPath,
            configFilePath: configPath,
            profile: profile
        )
        guard case .credentialProcess(let command) = sharedCredentials else {
            Issue.record("Expected .credentialProcess, got \(sharedCredentials)")
            return
        }
        #expect(command == "/from/credentials")
    }

    @Test("credential_process with role_arn returns assumeRole case")
    func credentialProcessWithRoleArn() async throws {
        let profile = ConfigFileLoader.defaultProfile
        let credentialsFile = """
            [\(profile)]
            credential_process = /usr/bin/get-creds
            role_arn = arn:aws:iam::123456789012:role/myrole
            """

        let credentialsPath = try save(content: credentialsFile, prefix: "role-arn")
        defer { try? FileManager.default.removeItem(atPath: credentialsPath) }

        let sharedCredentials = try await ConfigFileLoader.loadSharedCredentials(
            credentialsFilePath: credentialsPath,
            configFilePath: "/dev/null",
            profile: profile
        )
        guard case .assumeRole(let roleArn, _, _, _) = sharedCredentials else {
            Issue.record("Expected .assumeRole, got \(sharedCredentials)")
            return
        }
        #expect(roleArn == "arn:aws:iam::123456789012:role/myrole")
    }

    @Test("credential_process takes precedence over static keys when both present")
    func credentialProcessTakesPrecedenceOverStaticKeys() async throws {
        let profile = ConfigFileLoader.defaultProfile
        let credentialsFile = """
            [\(profile)]
            aws_access_key_id = AKIAIOSFODNN7EXAMPLE
            aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
            credential_process = /usr/bin/get-creds
            """

        let credentialsPath = try save(content: credentialsFile, prefix: "precedence")
        defer { try? FileManager.default.removeItem(atPath: credentialsPath) }

        let sharedCredentials = try await ConfigFileLoader.loadSharedCredentials(
            credentialsFilePath: credentialsPath,
            configFilePath: "/dev/null",
            profile: profile
        )
        guard case .credentialProcess(let command) = sharedCredentials else {
            Issue.record("Expected .credentialProcess, got \(sharedCredentials)")
            return
        }
        #expect(command == "/usr/bin/get-creds")
    }

    @Test("ConfigFileCredentialProvider dispatches credentialProcess case to CredentialProcessProvider")
    func credentialProviderFactory() async throws {
        let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)

        let context = CredentialProviderFactory.Context(
            httpClient: httpClient,
            logger: logger,
            options: .init()
        )
        let sharedCredentials = ConfigFileLoader.SharedCredentials.credentialProcess(
            command: testHelperPath
        )
        let provider = try ConfigFileCredentialProvider.credentialProvider(
            from: sharedCredentials,
            context: context,
            endpoint: nil
        )
        #expect(provider is CredentialProcessProvider)
        try await httpClient.shutdown()
    }

    // MARK: - Process Execution

    @Test("Successful execution returns static credentials when no Expiration")
    func successfulExecutionStaticCredentials() async throws {
        let provider = CredentialProcessProvider(command: testHelperPath)
        let credential = try await provider.getCredential(logger: logger)

        #expect(credential.accessKeyId == "AKID-CREDENTIAL-PROCESS")
        #expect(credential.secretAccessKey == "SECRET-CREDENTIAL-PROCESS")
        #expect(credential.sessionToken == "TOKEN-CREDENTIAL-PROCESS")
        #expect(!(credential is ExpiringCredential))
    }

    @Test("Successful execution returns expiring credentials when Expiration present")
    func successfulExecutionExpiringCredentials() async throws {
        let provider = CredentialProcessProvider(command: "\(testHelperPath) --expiring")
        let credential = try await provider.getCredential(logger: logger)

        #expect(credential.accessKeyId == "AKID-CREDENTIAL-PROCESS")
        #expect(credential.secretAccessKey == "SECRET-CREDENTIAL-PROCESS")
        #expect(credential.sessionToken == "TOKEN-CREDENTIAL-PROCESS")
        let expiring = try #require(credential as? ExpiringCredential)
        #expect(expiring.expiration > Date())
    }

    @Test("Missing SessionToken results in nil sessionToken")
    func noSessionToken() async throws {
        let provider = CredentialProcessProvider(command: "\(testHelperPath) --no-session-token")
        let credential = try await provider.getCredential(logger: logger)

        #expect(credential.accessKeyId == "AKID-CREDENTIAL-PROCESS")
        #expect(credential.secretAccessKey == "SECRET-CREDENTIAL-PROCESS")
        #expect(credential.sessionToken == nil)
    }

    @Test("Non-zero exit code throws processExitedWithError")
    func nonZeroExitCode() async throws {
        let provider = CredentialProcessProvider(command: "\(testHelperPath) --exit-code 42")

        await #expect {
            try await provider.getCredential(logger: logger)
        } throws: { error in
            (error as? CredentialProcessError) == .processExitedWithError(42)
        }
    }

    @Test("Invalid Version throws invalidVersion error")
    func invalidVersion() async throws {
        let provider = CredentialProcessProvider(command: "\(testHelperPath) --invalid-version")

        await #expect {
            try await provider.getCredential(logger: logger)
        } throws: { error in
            (error as? CredentialProcessError) == .invalidVersion(2)
        }
    }

    @Test("Invalid JSON output throws failedToDecodeOutput error")
    func invalidJSON() async throws {
        let provider = CredentialProcessProvider(command: "\(testHelperPath) --invalid-json")

        await #expect {
            try await provider.getCredential(logger: logger)
        } throws: { error in
            (error as? CredentialProcessError) == .failedToDecodeOutput
        }
    }

    @Test("Empty command throws commandEmpty error")
    func emptyCommand() async throws {
        let provider = CredentialProcessProvider(command: "")

        await #expect {
            try await provider.getCredential(logger: logger)
        } throws: { error in
            (error as? CredentialProcessError) == .commandEmpty
        }
    }

    @Test("Nonexistent command throws processExitedWithError(127)")
    func commandNotFound() async throws {
        let provider = CredentialProcessProvider(command: "/nonexistent/binary/that/does/not/exist")

        await #expect {
            try await provider.getCredential(logger: logger)
        } throws: { error in
            (error as? CredentialProcessError) == .processExitedWithError(127)
        }
    }

    // MARK: - End-to-End

    @Test("End-to-end: config file with credential_process yields valid credentials")
    func endToEndWithConfigFile() async throws {
        let profile = ConfigFileLoader.defaultProfile
        let credentialsFile = """
            [\(profile)]
            credential_process = \(testHelperPath)
            """

        let credentialsPath = try save(content: credentialsFile, prefix: "e2e")
        defer { try? FileManager.default.removeItem(atPath: credentialsPath) }

        let sharedCredentials = try await ConfigFileLoader.loadSharedCredentials(
            credentialsFilePath: credentialsPath,
            configFilePath: "/dev/null",
            profile: profile
        )
        guard case .credentialProcess(let command) = sharedCredentials else {
            Issue.record("Expected .credentialProcess, got \(sharedCredentials)")
            return
        }

        let provider = CredentialProcessProvider(command: command)
        let credential = try await provider.getCredential(logger: logger)

        #expect(credential.accessKeyId == "AKID-CREDENTIAL-PROCESS")
        #expect(credential.secretAccessKey == "SECRET-CREDENTIAL-PROCESS")
        #expect(credential.sessionToken == "TOKEN-CREDENTIAL-PROCESS")
    }

    @Test("End-to-end: credential_process with --expiring returns ExpiringCredential")
    func endToEndExpiringWithConfigFile() async throws {
        // The INI parser strips spaces from values, so we use a wrapper script
        // to pass arguments to the test helper.
        let cwd = FileManager.default.currentDirectoryPath
        let absoluteHelperPath = "\(cwd)/\(testHelperPath)"
        let scriptContent = "#!/bin/sh\nexec \"\(absoluteHelperPath)\" --expiring\n"
        let scriptPath = "\(cwd)/" + (try save(content: scriptContent, prefix: "expiring-script"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptPath
        )
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }

        let profile = ConfigFileLoader.defaultProfile
        let credentialsFile = """
            [\(profile)]
            credential_process = \(scriptPath)
            """

        let credentialsPath = try save(content: credentialsFile, prefix: "expiring-creds")
        defer { try? FileManager.default.removeItem(atPath: credentialsPath) }

        let sharedCredentials = try await ConfigFileLoader.loadSharedCredentials(
            credentialsFilePath: credentialsPath,
            configFilePath: "/dev/null",
            profile: profile
        )
        guard case .credentialProcess(let command) = sharedCredentials else {
            Issue.record("Expected .credentialProcess, got \(sharedCredentials)")
            return
        }

        let provider = CredentialProcessProvider(command: command)
        let credential = try await provider.getCredential(logger: logger)

        #expect(credential.accessKeyId == "AKID-CREDENTIAL-PROCESS")
        let expiring = try #require(credential as? ExpiringCredential)
        #expect(expiring.expiration > Date())
    }
}
#endif
