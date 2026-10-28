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
import Testing

@testable import SotoCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct ConfigFileLoadersTests {
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

    @Test func testLoadFileJustCredentials() async throws {
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
            case .staticCredential(let accessKeyId, let secretAccessKey, _):
                #expect(accessKeyId == accessKey)
                #expect(secretAccessKey == secretKey)
            default:
                Issue.record("Expected static credentials")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? await httpClient.shutdown()
        }
    }

    @Test func testLoadFileCredentialsAndConfig() async throws {
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
                #expect(credentials.accessKeyId == accessKey)
                #expect(credentials.secretAccessKey == secretKey)
                #expect(aRoleArn == roleArn)
                #expect(aSessionName == sessionName)
                #expect(region == .uswest1)
            default:
                Issue.record("Expected STS Assume Role")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? FileManager.default.removeItem(atPath: configPath)
            try? await httpClient.shutdown()
        }
    }

    @Test func testLoadFileConfigNotFound() async throws {
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
                #expect(aRoleArn == roleArn)
                let rotatingCredentials: RotatingCredentialProvider = try #require(credentialProvider as? RotatingCredentialProvider)
                #expect(rotatingCredentials.provider is InstanceMetaDataClient)
                try await credentialProvider.shutdown()
            default:
                Issue.record("Expected credential source")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? await httpClient.shutdown()
        }
    }

    @Test func testLoadFileMissingAccessKey() async throws {
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
                Issue.record("Expected ConfigFileLoader.ConfigFileError.missingAccessKeyId, got \(error)")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? await httpClient.shutdown()
        }
    }

    @Test func testLoadFileMissingSecretKey() async throws {
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
                Issue.record("Expected ConfigFileLoader.ConfigFileError.missingSecretAccessKey, got \(error)")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? await httpClient.shutdown()
        }
    }

    @Test func testLoadFileMissingSourceAccessKey() async throws {
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
                Issue.record("Expected ConfigFileLoader.ConfigFileError.missingAccessKeyId, got \(error)")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? await httpClient.shutdown()
        }
    }

    @Test func testLoadFileMissingSourceSecretKey() async throws {
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
                Issue.record("Expected ConfigFileLoader.ConfigFileError.missingSecretAccessKey, got \(error)")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? await httpClient.shutdown()
        }
    }

    @Test func testLoadFileSSOSourceProfile() async throws {
        // Assume-role profile lives only in ~/.aws/config and points at an SSO source profile.
        // This is the standard layout written by `aws configure sso` for multi-account setups.
        let profile = "dev"
        let sourceProfile = "sso-base"
        let roleArn = "arn:aws:iam::222222222222:role/Developer"
        let credentialsFile = ""
        let configFile = """
            [profile \(profile)]
            role_arn = \(roleArn)
            source_profile = \(sourceProfile)
            region = us-west-2

            [profile \(sourceProfile)]
            sso_session = my-org
            sso_account_id = 111111111111
            sso_role_name = SSOAccess

            [sso-session my-org]
            sso_start_url = https://my-org.awsapps.com/start
            sso_region = us-east-1
            """

        let credentialsPath = try save(content: credentialsFile, prefix: "creds-\(#function)")
        let configPath = try save(content: configFile, prefix: "config-\(#function)")
        let (context, httpClient) = try makeContext()

        try await withTeardown {
            let shared = try await ConfigFileLoader.loadSharedCredentials(
                credentialsFilePath: credentialsPath,
                configFilePath: configPath,
                profile: profile
            )

            switch shared {
            case .assumeRole(let aRoleArn, _, let region, let sourceFactory):
                #expect(aRoleArn == roleArn)
                #expect(region == .uswest2)
                let sourceProvider = sourceFactory.createProvider(context: context)
                let rotating = try #require(sourceProvider as? RotatingCredentialProvider)
                #expect(
                    rotating.provider is SSOCredentialProvider,
                    "Expected SSOCredentialProvider as the source, got \(type(of: rotating.provider))"
                )
                try await sourceProvider.shutdown()
            default:
                Issue.record("Expected .assumeRole with an SSO source provider")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? FileManager.default.removeItem(atPath: configPath)
            try? await httpClient.shutdown()
        }
    }

    @Test func testLoadFileMissingCredentialsButConfigHasSSOSource() async throws {
        // Many SSO-only setups have no ~/.aws/credentials file at all. As long as the config
        // file fully describes the assume-role chain (and its SSO source), credential loading
        // should still succeed instead of falling through to .noProvider.
        let profile = "dev"
        let sourceProfile = "sso-base"
        let roleArn = "arn:aws:iam::222222222222:role/Developer"
        let configFile = """
            [profile \(profile)]
            role_arn = \(roleArn)
            source_profile = \(sourceProfile)

            [profile \(sourceProfile)]
            sso_session = my-org
            sso_account_id = 111111111111
            sso_role_name = SSOAccess

            [sso-session my-org]
            sso_start_url = https://my-org.awsapps.com/start
            sso_region = us-east-1
            """

        let credentialsPath = "missing-credentials-\(UUID().uuidString)"
        let configPath = try save(content: configFile, prefix: "config-\(#function)")
        let (context, httpClient) = try makeContext()

        try await withTeardown {
            let shared = try await ConfigFileLoader.loadSharedCredentials(
                credentialsFilePath: credentialsPath,
                configFilePath: configPath,
                profile: profile
            )

            switch shared {
            case .assumeRole(let aRoleArn, _, _, let sourceFactory):
                #expect(aRoleArn == roleArn)
                let sourceProvider = sourceFactory.createProvider(context: context)
                let rotating = try #require(sourceProvider as? RotatingCredentialProvider)
                #expect(rotating.provider is SSOCredentialProvider)
                try await sourceProvider.shutdown()
            default:
                Issue.record("Expected .assumeRole with an SSO source provider")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: configPath)
            try? await httpClient.shutdown()
        }
    }

    @Test func testLoadFileBothFilesMissing() async throws {
        // Neither file exists at all — provider must still report `.noProvider` so the
        // credential chain can move on to the next provider.
        let credentialsPath = "missing-credentials-\(UUID().uuidString)"
        let configPath = "missing-config-\(UUID().uuidString)"
        let (_, httpClient) = try makeContext()

        try await withTeardown {
            do {
                _ = try await ConfigFileLoader.loadSharedCredentials(
                    credentialsFilePath: credentialsPath,
                    configFilePath: configPath,
                    profile: ConfigFileLoader.defaultProfile
                )
                Issue.record("Expected CredentialProviderError.noProvider")
            } catch let error as CredentialProviderError where error == .noProvider {
                // pass
            } catch {
                Issue.record("Expected CredentialProviderError.noProvider, got \(error)")
            }
        } teardown: {
            try? await httpClient.shutdown()
        }
    }

    @Test func testLoadFileMissingCredentialsAndConfigHasNoRoleArn() async throws {
        // Credentials file is unavailable and the config file exists but doesn't supply a
        // `role_arn` for the requested profile. The provider must signal `.noProvider` so the
        // credential chain can move on (e.g. to the standalone `.sso()` step).
        let configFile = """
            [profile dev]
            region = us-east-1
            """
        let credentialsPath = "missing-credentials-\(#function)"
        let configPath = try save(content: configFile, prefix: "config-\(#function)")
        let (_, httpClient) = try makeContext()

        try await withTeardown {
            do {
                _ = try await ConfigFileLoader.loadSharedCredentials(
                    credentialsFilePath: credentialsPath,
                    configFilePath: configPath,
                    profile: "dev"
                )
                Issue.record("Expected CredentialProviderError.noProvider")
            } catch let error as CredentialProviderError where error == .noProvider {
                // pass
            } catch {
                Issue.record("Expected CredentialProviderError.noProvider, got \(error)")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: configPath)
            try? await httpClient.shutdown()
        }
    }

    @Test func testLoadFileMalformedCredentialsFileSurfacesError() async throws {
        // A credentials file that exists but cannot be parsed must surface `.invalidINIFile`
        // rather than being silently treated as "no credentials file". Only ENOENT should
        // degrade to a soft miss.
        let credentialsPath = try save(content: "this line is not valid ini\n", prefix: "creds-\(#function)")
        let configPath = "missing-config-\(UUID().uuidString)"
        let (_, httpClient) = try makeContext()

        try await withTeardown {
            do {
                _ = try await ConfigFileLoader.loadSharedCredentials(
                    credentialsFilePath: credentialsPath,
                    configFilePath: configPath,
                    profile: ConfigFileLoader.defaultProfile
                )
                Issue.record("Expected ConfigFileError.invalidINIFile")
            } catch let error as ConfigFileLoader.ConfigFileError where error == .invalidINIFile {
                // pass
            } catch {
                Issue.record("Expected ConfigFileError.invalidINIFile, got \(error)")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? await httpClient.shutdown()
        }
    }

    @Test func testLoadFileMalformedConfigFileSurfacesError() async throws {
        // Same contract for the config file: a parseable credentials file alongside a
        // malformed config file must propagate the parse error rather than silently
        // proceeding with the credentials file alone.
        let credentialsFile = """
            [\(ConfigFileLoader.defaultProfile)]
            aws_access_key_id = AKIAIOSFODNN7EXAMPLE
            aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
            """
        let credentialsPath = try save(content: credentialsFile, prefix: "creds-\(#function)")
        let configPath = try save(content: "this line is not valid ini\n", prefix: "config-\(#function)")
        let (_, httpClient) = try makeContext()

        try await withTeardown {
            do {
                _ = try await ConfigFileLoader.loadSharedCredentials(
                    credentialsFilePath: credentialsPath,
                    configFilePath: configPath,
                    profile: ConfigFileLoader.defaultProfile
                )
                Issue.record("Expected ConfigFileError.invalidINIFile")
            } catch let error as ConfigFileLoader.ConfigFileError where error == .invalidINIFile {
                // pass
            } catch {
                Issue.record("Expected ConfigFileError.invalidINIFile, got \(error)")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? FileManager.default.removeItem(atPath: configPath)
            try? await httpClient.shutdown()
        }
    }

    @Test func testLoadFileMissingCredentialsWithMalformedConfigSurfacesError() async throws {
        // A missing credentials file is fine on its own, but if the config file that we'd
        // fall back to is malformed, we must surface the parse error rather than reporting
        // `.noProvider` (which would hide the real problem from the user).
        let credentialsPath = "missing-credentials-\(UUID().uuidString)"
        let configPath = try save(content: "this line is not valid ini\n", prefix: "config-\(#function)")
        let (_, httpClient) = try makeContext()

        try await withTeardown {
            do {
                _ = try await ConfigFileLoader.loadSharedCredentials(
                    credentialsFilePath: credentialsPath,
                    configFilePath: configPath,
                    profile: ConfigFileLoader.defaultProfile
                )
                Issue.record("Expected ConfigFileError.invalidINIFile")
            } catch let error as ConfigFileLoader.ConfigFileError where error == .invalidINIFile {
                // pass
            } catch {
                Issue.record("Expected ConfigFileError.invalidINIFile, got \(error)")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: configPath)
            try? await httpClient.shutdown()
        }
    }

    @Test func testLoadFileSSOSourceProfileLegacyFormat() async throws {
        // Same scenario, but the source profile uses the legacy SSO format (direct sso_start_url
        // rather than an sso_session reference). Both should be detected.
        let profile = "dev"
        let sourceProfile = "sso-base"
        let roleArn = "arn:aws:iam::222222222222:role/Developer"
        let credentialsFile = ""
        let configFile = """
            [profile \(profile)]
            role_arn = \(roleArn)
            source_profile = \(sourceProfile)

            [profile \(sourceProfile)]
            sso_start_url = https://my-org.awsapps.com/start
            sso_region = us-east-1
            sso_account_id = 111111111111
            sso_role_name = SSOAccess
            """

        let credentialsPath = try save(content: credentialsFile, prefix: "creds-\(#function)")
        let configPath = try save(content: configFile, prefix: "config-\(#function)")
        let (context, httpClient) = try makeContext()

        try await withTeardown {
            let shared = try await ConfigFileLoader.loadSharedCredentials(
                credentialsFilePath: credentialsPath,
                configFilePath: configPath,
                profile: profile
            )

            switch shared {
            case .assumeRole(_, _, _, let sourceFactory):
                let sourceProvider = sourceFactory.createProvider(context: context)
                let rotating = try #require(sourceProvider as? RotatingCredentialProvider)
                #expect(rotating.provider is SSOCredentialProvider)
                try await sourceProvider.shutdown()
            default:
                Issue.record("Expected .assumeRole with an SSO source provider")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? FileManager.default.removeItem(atPath: configPath)
            try? await httpClient.shutdown()
        }
    }

    @Test func testLoadFileRoleArnOnly() async throws {
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
                Issue.record("Expected ConfigFileLoader.ConfigFileError.invalidINIFile, got \(error)")
            }
        } teardown: {
            try? FileManager.default.removeItem(atPath: credentialsPath)
            try? await httpClient.shutdown()
        }
    }

    // MARK: - Config File parsing

    @Test func testConfigFileDefault() throws {
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
        #expect(config?.roleArn == roleArn)
        #expect(config?.sourceProfile == sourceProfile)
        #expect(config?.region == .uswest2)
    }

    @Test func testConfigFileNamedProfile() throws {
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
        #expect(config?.roleArn == "arn:aws:iam::123456789012:role/marketingadminrole")
        #expect(config?.sourceProfile == "user1")
        #expect(config?.roleSessionName == "foo@example.com")
        #expect(config?.region == .uswest1)
    }

    @Test func testConfigFileCredentialSourceEc2() throws {
        let content = """
            [profile marketingadmin]
            role_arn = arn:aws:iam::123456789012:role/marketingadminrole
            credential_source = Ec2InstanceMetadata
            """

        let config = try ConfigFileLoader.parseProfileConfig(from: try! INIParser(content), for: "marketingadmin")
        #expect(config?.credentialSource == .ec2Instance)
    }

    @Test func testConfigFileCredentialSourceEcs() throws {
        let content = """
            [profile marketingadmin]
            role_arn = arn:aws:iam::123456789012:role/marketingadminrole
            credential_source = EcsContainer
            """

        let config = try ConfigFileLoader.parseProfileConfig(from: try! INIParser(content), for: "marketingadmin")
        #expect(config?.credentialSource == .ecsContainer)
    }

    @Test func testConfigFileCredentialSourceEnvironment() throws {
        let content = """
            [profile marketingadmin]
            role_arn = arn:aws:iam::123456789012:role/marketingadminrole
            credential_source = Environment
            """

        let config = try ConfigFileLoader.parseProfileConfig(from: try! INIParser(content), for: "marketingadmin")
        #expect(config?.credentialSource == .environment)
    }

    @Test func testConfigMissingProfile() {
        let content = """
            [profile foo]
            bar = foo
            """

        do {
            _ = try ConfigFileLoader.parseProfileConfig(from: try! INIParser(content), for: "bar")
        } catch let error as ConfigFileLoader.ConfigFileError where error == .missingProfile {
        } catch {
            Issue.record("Expected missingProfile error, got \(error)")
        }
    }

    // MARK: - Credentials File parsing

    @Test func testCredentials() throws {
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
        #expect(cred.accessKey == accessKey)
        #expect(cred.secretAccessKey == secretKey)
        #expect(cred.sessionToken == sessionToken)
    }

    @Test func testCredentialsMissingSessionToken() throws {
        let profile = "profile1"
        let accessKey = "FAKE-ACCESS-KEY123"
        let secretKey = "Asecretreglkjrd"
        let credential = """
            [\(profile)]
            aws_access_key_id=\(accessKey)
            aws_secret_access_key=\(secretKey)
            """

        let cred = try ConfigFileLoader.parseCredentials(from: try! INIParser(credential), for: profile, sourceProfile: nil)
        #expect(cred.accessKey == accessKey)
        #expect(cred.secretAccessKey == secretKey)
        #expect(cred.sessionToken == nil)
    }

    @Test func testCredentialsNamedProfile() throws {
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
        #expect(config.accessKey == profileAccessKey)
        #expect(config.secretAccessKey == profileSecretKey)
    }

    @Test func testCredentialsWithSourceProfile() throws {
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
        #expect(config.accessKey == "AKIAIOSFODNN7EXAMPLE")
        #expect(config.secretAccessKey == "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
        #expect(config.roleArn == "arn:aws:iam::123456789012:role/marketingadminrole")
        #expect(config.sourceProfile == ConfigFileLoader.defaultProfile)
    }

    @Test func testCredentialsMissingProfile() {
        let content = """
            [default]
            aws_access_key_id=AKIAIOSFODNN7EXAMPLE
            aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
            """

        do {
            _ = try ConfigFileLoader.parseCredentials(from: try! INIParser(content), for: "user1", sourceProfile: nil)
        } catch let error as ConfigFileLoader.ConfigFileError where error == .missingProfile {
        } catch {
            Issue.record("Expected missingProfile error, got \(error)")
        }
    }

    @Test func testCredentialsMissingSourceProfile() {
        let content = """
            [foo]
            aws_access_key_id=AKIAIOSFODNN7EXAMPLE
            aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
            """

        do {
            _ = try ConfigFileLoader.parseCredentials(from: try! INIParser(content), for: "foo", sourceProfile: ConfigFileLoader.defaultProfile)
        } catch let error as ConfigFileLoader.ConfigFileError where error == .missingProfile {
        } catch {
            Issue.record("Expected missingProfile error, got \(error)")
        }
    }

    @Test func testCredentialsMissingAccessKey() {
        let content = """
            [foo]
            aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
            """

        do {
            _ = try ConfigFileLoader.parseCredentials(from: try! INIParser(content), for: "foo", sourceProfile: nil)
        } catch let error as ConfigFileLoader.ConfigFileError where error == .missingAccessKeyId {
            // pass
        } catch {
            Issue.record("Expected missingProfile error, got \(error)")
        }
    }

    @Test func testCredentialsMissingSecretAccessKey() {
        let content = """
            [foo]
            aws_access_key_id=AKIAIOSFODNN7EXAMPLE
            """

        do {
            _ = try ConfigFileLoader.parseCredentials(from: try! INIParser(content), for: "foo", sourceProfile: nil)
        } catch let error as ConfigFileLoader.ConfigFileError where error == .missingSecretAccessKey {
            // pass
        } catch {
            Issue.record("Expected missingProfile error, got \(error)")
        }
    }

    @Test func testCredentialsMissingAccessKeyFromSourceProfile() {
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
            Issue.record("Expected missingProfile error, got \(error)")
        }
    }

    @Test func testCredentialsMissingSecretAccessKeyFromSourceProfile() {
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
            Issue.record("Expected missingProfile error, got \(error)")
        }
    }

    @Test func testCredentialSourceEc2() throws {
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
        #expect(config.credentialSource == .ec2Instance)
    }

    @Test func testCredentialSourceEcs() throws {
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
        #expect(config.credentialSource == .ecsContainer)
    }

    @Test func testCredentialSourceEnvironment() throws {
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
        #expect(config.credentialSource == .environment)
    }

    // MARK: - Config file path expansion

    @Test func testExpandTildeInFilePath() {
        let expandableFilePath = "~/.aws/credentials"
        let expandedNewPath = ConfigFileLoader.expandTildeInFilePath(expandableFilePath)

        #if os(Linux)
        #expect(!expandedNewPath.hasPrefix("~"))
        #else

        #if os(macOS)
        // on macOS, we want to be sure the expansion produces the posix $HOME and
        // not the sanboxed home $HOME/Library/Containers/<bundle-id>/Data
        let macOSHomePrefix = "/Users/"
        #expect(expandedNewPath.starts(with: macOSHomePrefix))
        #expect(!expandedNewPath.contains("/Library/Containers/"))
        #endif

        // this doesn't work on linux because of SR-12843
        let expandedNSString = NSString(string: expandableFilePath).expandingTildeInPath
        #expect(expandedNewPath == expandedNSString)
        #endif

        let unexpandableFilePath = "/.aws/credentials"
        let unexpandedNewPath = ConfigFileLoader.expandTildeInFilePath(unexpandableFilePath)
        let unexpandedNSString = NSString(string: unexpandableFilePath).expandingTildeInPath

        #expect(unexpandedNewPath == unexpandedNSString)
        #expect(unexpandedNewPath == unexpandableFilePath)
    }
}
