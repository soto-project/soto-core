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

import AsyncHTTPClient
import INIParser
import NIOCore
import NIOPosix
import SotoTestUtils
import XCTest

@testable import SotoCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

class ConfigFileLoadersTests: XCTestCase {
    // MARK: - File Loading

    func makeContext() throws -> (CredentialProviderFactory.Context, HTTPClient) {
        let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
        return (.init(httpClient: httpClient, logger: TestEnvironment.logger, options: .init()), httpClient)
    }

    func save(content: String, prefix: String) throws -> String {
        let filepath = "\(prefix)-\(UUID().uuidString)"
        try content.write(toFile: filepath, atomically: true, encoding: .utf8)
        return filepath
    }

    func testLoadFileJustCredentials() async throws {
        let accessKey = "AKIAIOSFODNN7EXAMPLE"
        let secretKey = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        let profile = ConfigFileLoader.defaultProfile
        let credentialsFile = """
            [\(profile)]
            aws_access_key_id=\(accessKey)
            aws_secret_access_key= \(secretKey)
            """

        let credentialsPath = try save(content: credentialsFile, prefix: #function)
        let (_, httpClient) = try makeContext()

        try await withTeardown {
            let sharedCredentials = try await ConfigFileLoader.loadSharedCredentials(
                credentialsFilePath: credentialsPath,
                configFilePath: "/dev/null",
                profile: profile
            )

            switch sharedCredentials {
            case .staticCredential(let credentials):
                XCTAssertEqual(credentials.accessKeyId, accessKey)
                XCTAssertEqual(credentials.secretAccessKey, secretKey)
            default:
                XCTFail("Expected static credentials")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? await httpClient.shutdown()
        }
    }

    func testLoadFileCredentialsAndConfig() async throws {
        let accessKey = "AKIAIOSFODNN7EXAMPLE"
        let secretKey = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        let profile = "marketingadmin"
        let sourceProfile = ConfigFileLoader.defaultProfile
        let sessionName = "foo@example.com"
        let roleArn = "arn:aws:iam::123456789012:role/marketingadminrole"
        let credentialsFile = """
            [\(sourceProfile)]
            aws_access_key_id = \(accessKey)
            aws_secret_access_key=\(secretKey)
            [\(profile)]
            role_arn = \(roleArn)
            source_profile = \(sourceProfile)
            """
        let configFile = """
            [profile \(profile)]
            role_session_name = \(sessionName)
            region = us-west-1
            """

        let credentialsPath = try save(content: credentialsFile, prefix: #function)
        let configPath = try save(content: configFile, prefix: "config")
        let (context, httpClient) = try makeContext()

        try await withTeardown {
            let sharedCredentials = try await ConfigFileLoader.loadSharedCredentials(
                credentialsFilePath: credentialsPath,
                configFilePath: configPath,
                profile: profile
            )

            switch sharedCredentials {
            case .assumeRole(let aRoleArn, let aSessionName, let region, let sourceCredentialProvider):
                let credentials = try await sourceCredentialProvider.createProvider(context: context).getCredential(logger: context.logger)
                XCTAssertEqual(credentials.accessKeyId, accessKey)
                XCTAssertEqual(credentials.secretAccessKey, secretKey)
                XCTAssertEqual(aRoleArn, roleArn)
                XCTAssertEqual(aSessionName, sessionName)
                XCTAssertEqual(region, .uswest1)
            default:
                XCTFail("Expected STS Assume Role")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? FileManager.default.removeItem(atPath: configPath)
            try? await httpClient.shutdown()
        }
    }

    func testLoadFileConfigNotFound() async throws {
        let profile = "marketingadmin"
        let roleArn = "arn:aws:iam::123456789012:role/marketingadminrole"
        let credentialsFile = """
            [\(profile)]
            role_arn = \(roleArn)
            credential_source = Ec2InstanceMetadata
            """

        let credentialsPath = try save(content: credentialsFile, prefix: #function)
        let (context, httpClient) = try makeContext()

        try await withTeardown {
            let sharedCredentials = try await ConfigFileLoader.loadSharedCredentials(
                credentialsFilePath: credentialsPath,
                configFilePath: "non-existing-file-path",
                profile: profile
            )

            switch sharedCredentials {
            case .assumeRole(let aRoleArn, _, _, let source):
                let credentialProvider = source.createProvider(context: context)
                XCTAssertEqual(aRoleArn, roleArn)
                let rotatingCredentials: RotatingCredentialProvider = try XCTUnwrap(credentialProvider as? RotatingCredentialProvider)
                XCTAssert(rotatingCredentials.provider is InstanceMetaDataClient)
                try await credentialProvider.shutdown()
            default:
                XCTFail("Expected credential source")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? await httpClient.shutdown()
        }
    }

    func testLoadFileMissingAccessKey() async throws {
        let secretKey = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        let profile = ConfigFileLoader.defaultProfile
        let credentialsFile = """
            [\(profile)]
            aws_secret_access_key= \(secretKey)
            """

        let credentialsPath = try save(content: credentialsFile, prefix: #function)
        let (_, httpClient) = try makeContext()

        try await withTeardown {
            do {
                _ = try await ConfigFileLoader.loadSharedCredentials(
                    credentialsFilePath: credentialsPath,
                    configFilePath: "/dev/null",
                    profile: profile
                )
            } catch let error as ConfigFileLoader.ConfigFileError where error == .missingAccessKeyId {
                // Pass
            } catch {
                XCTFail("Expected ConfigFileLoader.ConfigFileError.missingAccessKeyId, got \(error.localizedDescription)")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? await httpClient.shutdown()
        }
    }

    func testLoadFileMissingSecretKey() async throws {
        let accessKey = "AKIAIOSFODNN7EXAMPLE"
        let profile = ConfigFileLoader.defaultProfile
        let credentialsFile = """
            [\(profile)]
            aws_access_key_id = \(accessKey)
            """

        let credentialsPath = try save(content: credentialsFile, prefix: #function)
        let (_, httpClient) = try makeContext()

        try await withTeardown {
            do {
                _ = try await ConfigFileLoader.loadSharedCredentials(
                    credentialsFilePath: credentialsPath,
                    configFilePath: "/dev/null",
                    profile: profile
                )
            } catch let error as ConfigFileLoader.ConfigFileError where error == .missingSecretAccessKey {
                // Pass
            } catch {
                XCTFail("Expected ConfigFileLoader.ConfigFileError.missingSecretAccessKey, got \(error.localizedDescription)")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? await httpClient.shutdown()
        }
    }

    func testLoadFileMissingSourceAccessKey() async throws {
        let secretKey = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        let profile = "marketingadmin"
        let sourceProfile = ConfigFileLoader.defaultProfile
        let roleArn = "arn:aws:iam::123456789012:role/marketingadminrole"
        let credentialsFile = """
            [\(sourceProfile)]
            aws_secret_access_key=\(secretKey)
            [\(profile)]
            role_arn = \(roleArn)
            source_profile = \(sourceProfile)
            """

        let credentialsPath = try save(content: credentialsFile, prefix: #function)
        let (_, httpClient) = try makeContext()

        try await withTeardown {
            do {
                _ = try await ConfigFileLoader.loadSharedCredentials(
                    credentialsFilePath: credentialsPath,
                    configFilePath: "/dev/null",
                    profile: profile
                )
            } catch let error as ConfigFileLoader.ConfigFileError where error == .missingAccessKeyId {
                // Pass
            } catch {
                XCTFail("Expected ConfigFileLoader.ConfigFileError.missingAccessKeyId, got \(error.localizedDescription)")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? await httpClient.shutdown()
        }
    }

    func testLoadFileMissingSourceSecretKey() async throws {
        let accessKey = "AKIAIOSFODNN7EXAMPLE"
        let profile = "marketingadmin"
        let sourceProfile = ConfigFileLoader.defaultProfile
        let roleArn = "arn:aws:iam::123456789012:role/marketingadminrole"
        let credentialsFile = """
            [\(sourceProfile)]
            aws_access_key_id = \(accessKey)
            [\(profile)]
            role_arn = \(roleArn)
            source_profile = \(sourceProfile)
            """

        let credentialsPath = try save(content: credentialsFile, prefix: #function)
        let (_, httpClient) = try makeContext()

        try await withTeardown {
            do {
                _ = try await ConfigFileLoader.loadSharedCredentials(
                    credentialsFilePath: credentialsPath,
                    configFilePath: "/dev/null",
                    profile: profile
                )
            } catch let error as ConfigFileLoader.ConfigFileError where error == .missingSecretAccessKey {
                // Pass
            } catch {
                XCTFail("Expected ConfigFileLoader.ConfigFileError.missingSecretAccessKey, got \(error.localizedDescription)")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? await httpClient.shutdown()
        }
    }

    func testLoadFileRoleArnOnly() async throws {
        let profile = "marketingadmin"
        let roleArn = "arn:aws:iam::123456789012:role/marketingadminrole"
        let credentialsFile = """
            [\(profile)]
            role_arn = \(roleArn)
            """

        let credentialsPath = try save(content: credentialsFile, prefix: #function)
        let (_, httpClient) = try makeContext()

        try await withTeardown {
            do {
                _ = try await ConfigFileLoader.loadSharedCredentials(
                    credentialsFilePath: credentialsPath,
                    configFilePath: "/dev/null",
                    profile: profile
                )
            } catch let error as ConfigFileLoader.ConfigFileError where error == .invalidINIFile {
                // Pass
            } catch {
                XCTFail("Expected ConfigFileLoader.ConfigFileError.invalidINIFile, got \(error.localizedDescription)")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? await httpClient.shutdown()
        }
    }

    // MARK: - Config File parsing

    func testConfigFileDefault() throws {
        let profile = ConfigFileLoader.defaultProfile
        let sourceProfile = "user1"
        let roleArn = "arn:aws:iam::123456789012:role/marketingadminrole"
        let content = """
            [\(profile)]
            role_arn = \(roleArn)
            source_profile = \(sourceProfile)
            region=us-west-2
            """
        var byteBuffer = ByteBufferAllocator().buffer(capacity: content.utf8.count)
        byteBuffer.writeString(content)

        let config = try ConfigFileLoader.parseProfileConfig(from: try! INIParser(content), for: ConfigFileLoader.defaultProfile)
        XCTAssertEqual(config?.roleArn, roleArn)
        XCTAssertEqual(config?.sourceProfile, sourceProfile)
        XCTAssertEqual(config?.region, .uswest2)
    }

    func testConfigFileNamedProfile() throws {
        let content = """
            [default]
            region=us-west-2
            output=json

            [profile marketingadmin]
            role_arn = arn:aws:iam::123456789012:role/marketingadminrole
            source_profile = user1
            role_session_name = foo@example.com
            region = us-west-1
            """

        let config = try ConfigFileLoader.parseProfileConfig(from: try! INIParser(content), for: "marketingadmin")
        XCTAssertEqual(config?.roleArn, "arn:aws:iam::123456789012:role/marketingadminrole")
        XCTAssertEqual(config?.sourceProfile, "user1")
        XCTAssertEqual(config?.roleSessionName, "foo@example.com")
        XCTAssertEqual(config?.region, .uswest1)
    }

    func testConfigFileCredentialSourceEc2() throws {
        let content = """
            [profile marketingadmin]
            role_arn = arn:aws:iam::123456789012:role/marketingadminrole
            credential_source = Ec2InstanceMetadata
            """

        let config = try ConfigFileLoader.parseProfileConfig(from: try! INIParser(content), for: "marketingadmin")
        XCTAssertEqual(config?.credentialSource, .ec2Instance)
    }

    func testConfigFileCredentialSourceEcs() throws {
        let content = """
            [profile marketingadmin]
            role_arn = arn:aws:iam::123456789012:role/marketingadminrole
            credential_source = EcsContainer
            """

        let config = try ConfigFileLoader.parseProfileConfig(from: try! INIParser(content), for: "marketingadmin")
        XCTAssertEqual(config?.credentialSource, .ecsContainer)
    }

    func testConfigFileCredentialSourceEnvironment() throws {
        let content = """
            [profile marketingadmin]
            role_arn = arn:aws:iam::123456789012:role/marketingadminrole
            credential_source = Environment
            """

        let config = try ConfigFileLoader.parseProfileConfig(from: try! INIParser(content), for: "marketingadmin")
        XCTAssertEqual(config?.credentialSource, .environment)
    }

    func testConfigMissingProfile() {
        let content = """
            [profile foo]
            bar = foo
            """

        do {
            _ = try ConfigFileLoader.parseProfileConfig(from: try! INIParser(content), for: "bar")
        } catch let error as ConfigFileLoader.ConfigFileError where error == .missingProfile {
        } catch {
            XCTFail("Expected missingProfile error, got \(error.localizedDescription)")
        }
    }

    // MARK: - Credentials File parsing

    func testCredentials() throws {
        let profile = "profile1"
        let accessKey = "FAKE-ACCESS-KEY123"
        let secretKey = "Asecretreglkjrd"
        let sessionToken = "xyz"
        let credential = """
            [\(profile)]
            aws_access_key_id=\(accessKey)
            aws_secret_access_key = \(secretKey)
            aws_session_token =\(sessionToken)
            """

        let cred = try ConfigFileLoader.parseCredentials(from: try! INIParser(credential), for: profile, sourceProfile: nil)
        XCTAssertEqual(cred.accessKey, accessKey)
        XCTAssertEqual(cred.secretAccessKey, secretKey)
        XCTAssertEqual(cred.sessionToken, sessionToken)
    }

    func testCredentialsMissingSessionToken() throws {
        let profile = "profile1"
        let accessKey = "FAKE-ACCESS-KEY123"
        let secretKey = "Asecretreglkjrd"
        let credential = """
            [\(profile)]
            aws_access_key_id=\(accessKey)
            aws_secret_access_key=\(secretKey)
            """

        let cred = try ConfigFileLoader.parseCredentials(from: try! INIParser(credential), for: profile, sourceProfile: nil)
        XCTAssertEqual(cred.accessKey, accessKey)
        XCTAssertEqual(cred.secretAccessKey, secretKey)
        XCTAssertNil(cred.sessionToken)
    }

    func testCredentialsNamedProfile() throws {
        let profile = "profile1"
        let defaultAccessKey = "FAKE-ACCESS-KEY123"
        let defaultSecretKey = "Asecretreglkjrd"
        let profileAccessKey = "profile-FAKE-ACCESS-KEY123"
        let profileSecretKey = "profile-Asecretreglkjrd"
        let content = """
            [default]
            aws_access_key_id=\(defaultAccessKey)
            aws_secret_access_key=\(defaultSecretKey)

            [\(profile)]
            aws_access_key_id=\(profileAccessKey)
            aws_secret_access_key=\(profileSecretKey)
            """

        let config = try ConfigFileLoader.parseCredentials(from: try! INIParser(content), for: profile, sourceProfile: nil)
        XCTAssertEqual(config.accessKey, profileAccessKey)
        XCTAssertEqual(config.secretAccessKey, profileSecretKey)
    }

    func testCredentialsWithSourceProfile() throws {
        let content = """
            [default]
            aws_access_key_id=AKIAIOSFODNN7EXAMPLE
            aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

            [user1]
            role_arn = arn:aws:iam::123456789012:role/marketingadminrole
            source_profile = default
            role_session_name = foo@example.com
            """

        let config = try ConfigFileLoader.parseCredentials(from: try! INIParser(content), for: "user1", sourceProfile: nil)
        XCTAssertEqual(config.accessKey, "AKIAIOSFODNN7EXAMPLE")
        XCTAssertEqual(config.secretAccessKey, "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
        XCTAssertEqual(config.roleArn, "arn:aws:iam::123456789012:role/marketingadminrole")
        XCTAssertEqual(config.sourceProfile, ConfigFileLoader.defaultProfile)
    }

    func testCredentialsMissingProfile() {
        let content = """
            [default]
            aws_access_key_id=AKIAIOSFODNN7EXAMPLE
            aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
            """

        do {
            _ = try ConfigFileLoader.parseCredentials(from: try! INIParser(content), for: "user1", sourceProfile: nil)
        } catch let error as ConfigFileLoader.ConfigFileError where error == .missingProfile {
        } catch {
            XCTFail("Expected missingProfile error, got \(error.localizedDescription)")
        }
    }

    func testCredentialsMissingSourceProfile() {
        let content = """
            [foo]
            aws_access_key_id=AKIAIOSFODNN7EXAMPLE
            aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
            """

        do {
            _ = try ConfigFileLoader.parseCredentials(from: try! INIParser(content), for: "foo", sourceProfile: ConfigFileLoader.defaultProfile)
        } catch let error as ConfigFileLoader.ConfigFileError where error == .missingProfile {
        } catch {
            XCTFail("Expected missingProfile error, got \(error.localizedDescription)")
        }
    }

    func testCredentialsMissingAccessKey() {
        let content = """
            [foo]
            aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
            """

        do {
            _ = try ConfigFileLoader.parseCredentials(from: try! INIParser(content), for: "foo", sourceProfile: nil)
        } catch let error as ConfigFileLoader.ConfigFileError where error == .missingAccessKeyId {
            // pass
        } catch {
            XCTFail("Expected missingProfile error, got \(error.localizedDescription)")
        }
    }

    func testCredentialsMissingSecretAccessKey() {
        let content = """
            [foo]
            aws_access_key_id=AKIAIOSFODNN7EXAMPLE
            """

        do {
            _ = try ConfigFileLoader.parseCredentials(from: try! INIParser(content), for: "foo", sourceProfile: nil)
        } catch let error as ConfigFileLoader.ConfigFileError where error == .missingSecretAccessKey {
            // pass
        } catch {
            XCTFail("Expected missingProfile error, got \(error.localizedDescription)")
        }
    }

    func testCredentialsMissingAccessKeyFromSourceProfile() {
        let content = """
            [foo]
            aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
            [bar]
            role_arn = arn:aws:iam::123456789012:role/marketingadminrole
            source_profile = foo
            """

        do {
            _ = try ConfigFileLoader.parseCredentials(from: try! INIParser(content), for: "bar", sourceProfile: "foo")
        } catch let error as ConfigFileLoader.ConfigFileError where error == .missingAccessKeyId {
            // pass
        } catch {
            XCTFail("Expected missingProfile error, got \(error.localizedDescription)")
        }
    }

    func testCredentialsMissingSecretAccessKeyFromSourceProfile() {
        let content = """
            [foo]
            aws_access_key_id=AKIAIOSFODNN7EXAMPLE
            [bar]
            role_arn = arn:aws:iam::123456789012:role/marketingadminrole
            source_profile = foo
            """

        do {
            _ = try ConfigFileLoader.parseCredentials(from: try! INIParser(content), for: "bar", sourceProfile: "foo")
        } catch let error as ConfigFileLoader.ConfigFileError where error == .missingSecretAccessKey {
            // pass
        } catch {
            XCTFail("Expected missingProfile error, got \(error.localizedDescription)")
        }
    }

    func testCredentialSourceEc2() throws {
        let content = """
            [default]
            aws_access_key_id=AKIAIOSFODNN7EXAMPLE
            aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
            [marketingadmin]
            role_arn = arn:aws:iam::123456789012:role/marketingadminrole
            credential_source = Ec2InstanceMetadata
            """

        let config = try ConfigFileLoader.parseCredentials(
            from: try! INIParser(content),
            for: "marketingadmin",
            sourceProfile: ConfigFileLoader.defaultProfile
        )
        XCTAssertEqual(config.credentialSource, .ec2Instance)
    }

    func testCredentialSourceEcs() throws {
        let content = """
            [default]
            aws_access_key_id=AKIAIOSFODNN7EXAMPLE
            aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
            [marketingadmin]
            role_arn = arn:aws:iam::123456789012:role/marketingadminrole
            credential_source = EcsContainer
            """

        let config = try ConfigFileLoader.parseCredentials(
            from: try! INIParser(content),
            for: "marketingadmin",
            sourceProfile: ConfigFileLoader.defaultProfile
        )
        XCTAssertEqual(config.credentialSource, .ecsContainer)
    }

    func testCredentialSourceEnvironment() throws {
        let content = """
            [default]
            aws_access_key_id=AKIAIOSFODNN7EXAMPLE
            aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
            [marketingadmin]
            role_arn = arn:aws:iam::123456789012:role/marketingadminrole
            credential_source = Environment
            """

        let config = try ConfigFileLoader.parseCredentials(
            from: try! INIParser(content),
            for: "marketingadmin",
            sourceProfile: ConfigFileLoader.defaultProfile
        )
        XCTAssertEqual(config.credentialSource, .environment)
    }

    // MARK: - Config file path expansion

    func testExpandTildeInFilePath() {
        let expandableFilePath = "~/.aws/credentials"
        let expandedNewPath = ConfigFileLoader.expandTildeInFilePath(expandableFilePath)

        #if os(Linux)
        XCTAssert(!expandedNewPath.hasPrefix("~"))
        #else

        #if os(macOS)
        // on macOS, we want to be sure the expansion produces the posix $HOME and
        // not the sanboxed home $HOME/Library/Containers/<bundle-id>/Data
        let macOSHomePrefix = "/Users/"
        XCTAssert(expandedNewPath.starts(with: macOSHomePrefix))
        XCTAssert(!expandedNewPath.contains("/Library/Containers/"))
        #endif

        // this doesn't work on linux because of SR-12843
        let expandedNSString = NSString(string: expandableFilePath).expandingTildeInPath
        XCTAssertEqual(expandedNewPath, expandedNSString)
        #endif

        let unexpandableFilePath = "/.aws/credentials"
        let unexpandedNewPath = ConfigFileLoader.expandTildeInFilePath(unexpandableFilePath)
        let unexpandedNSString = NSString(string: unexpandableFilePath).expandingTildeInPath

        XCTAssertEqual(unexpandedNewPath, unexpandedNSString)
        XCTAssertEqual(unexpandedNewPath, unexpandableFilePath)
    }
}
