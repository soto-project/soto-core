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

import struct Foundation.UUID
import INIParser
import Logging
import NIO
#if os(Linux)
import Glibc
#else
import Foundation.NSString
#endif

public enum ConfigFile {
    public static let defaultCredentialsPath = "~/.aws/credentials"
    public static let defaultProfileConfigPath = "~/.aws/config"
    public static let defaultProfile = "default"
}

/// Load settings from AWS credentials and profile configuration files
/// https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html
enum ConfigFileLoader {
    /// Specific type of credentials loaded from disk
    enum SharedCredentials {
        case staticCredential(credential: StaticCredential)
        case assumeRole(roleArn: String, sessionName: String, region: Region?, sourceCredentialProvider: CredentialProviderFactory)
    }

    /// Credentials file – The credentials and config file are updated when you run the command aws configure. The credentials file is located
    /// at `~/.aws/credentials` on Linux or macOS, or at C:\Users\USERNAME\.aws\credentials on Windows. This file can contain the credential
    /// details for the default profile and any named profiles.
    struct ProfileCredentials: Equatable {
        let accessKey: String?
        let secretAccessKey: String?
        let sessionToken: String?
        let roleArn: String?
        let roleSessionName: String?
        let sourceProfile: String?
        let credentialSource: CredentialSource?
    }

    /// The credentials and config file are updated when you run the command aws configure. The config file is located at `~/.aws/config` on Linux
    /// or macOS, or at C:\Users\USERNAME\.aws\config on Windows. This file contains the configuration settings for the default profile and any named profiles.
    struct ProfileConfig: Equatable {
        let region: Region?
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
    /// - invalidCredentialFile: If credentials could not be loaded from disk because of invalid configuration or syntax
    /// - missingProfile: If the profile requested was not found
    /// - missingAccessKeyId: If the access key ID was not found
    /// - missingSecretAccessKey: If the secret access key was not found
    enum ConfigFileError: Error, Equatable {
        case invalidCredentialFile
        case missingProfile(String)
        case missingAccessKeyId
        case missingSecretAccessKey
    }

    // MARK: - File IO

    /// Load credentials from disk
    /// - Parameters:
    ///   - credentialsFilePath: file path for AWS credentials file
    ///   - configFilePath: file path for AWS config file
    ///   - profile: named profile to load
    ///   - context: credential provider factory context
    /// - Returns: Promise of SharedCredentials
    static func loadSharedCredentials(
        credentialsFilePath: String,
        configFilePath: String,
        profile: String,
        context: CredentialProviderFactory.Context
    ) -> EventLoopFuture<SharedCredentials> {
        let threadPool = NIOThreadPool(numberOfThreads: 1)
        threadPool.start()
        let fileIO = NonBlockingFileIO(threadPool: threadPool)

        // Load credentials file
        return self.loadFile(path: credentialsFilePath, on: context.eventLoop, using: fileIO)
            .flatMap { credentialsByteBuffer in
                // Load profile config file
                return loadFile(path: configFilePath, on: context.eventLoop, using: fileIO)
                    .map {
                        (credentialsByteBuffer, $0)
                    }
                    .flatMapError { _ in
                        // Recover from error if profile config file does not exist
                        context.eventLoop.makeSucceededFuture((credentialsByteBuffer, nil))
                    }
            }
            .flatMapErrorThrowing { _ in
                // Throw `.noProvider` error if credential file cannot be loaded
                throw CredentialProviderError.noProvider
            }
            .flatMapThrowing { credentialsByteBuffer, configByteBuffer in
                return try parseSharedCredentials(from: credentialsByteBuffer, configByteBuffer: configByteBuffer, for: profile)
            }
            .always { _ in
                // shutdown the threadpool async
                threadPool.shutdownGracefully { _ in }
            }
    }

    /// Load a file from disk without blocking the current thread
    /// - Parameters:
    ///   - path: path for the file to load
    ///   - eventLoop: event loop to run everything on
    ///   - fileIO: non-blocking file IO
    /// - Returns: Event loop future with file contents in a byte-buffer
    static func loadFile(path: String, on eventLoop: EventLoop, using fileIO: NonBlockingFileIO) -> EventLoopFuture<ByteBuffer> {
        let path = self.expandTildeInFilePath(path)

        return fileIO.openFile(path: path, eventLoop: eventLoop)
            .flatMap { handle, region in
                fileIO.read(fileRegion: region, allocator: ByteBufferAllocator(), eventLoop: eventLoop)
                    .map {
                        ($0, handle)
                    }
            }
            .flatMapThrowing { byteBuffer, handle in
                try handle.close()
                return byteBuffer
            }
    }

    // MARK: - Byte Buffer parsing (INIParser)

    /// Parse credentials from files (passed in as byte-buffers).
    /// This method ensures credentials are valid according to AWS documentation.
    ///
    /// Credentials file settings have precedence over profile configuration settings.
    /// https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html#cli-configure-quickstart-precedence
    ///
    /// - Parameters:
    ///   - credentialsBuffer: contents of AWS shared credentials file (usually `~/.aws/credentials`)
    ///   - configByteBuffer: contents of AWS profile configuration file (usually `~/.aws/config`)
    ///   - profile: named profile to load (optional)
    /// - Returns: Parsed SharedCredentials
    static func parseSharedCredentials(from credentialsByteBuffer: ByteBuffer, configByteBuffer: ByteBuffer?, for profile: String) throws -> SharedCredentials {
        let config = try configByteBuffer.flatMap { try parseProfileConfig(from: $0, for: profile) }
        let credentials = try parseCredentials(from: credentialsByteBuffer, for: profile, sourceProfile: config?.sourceProfile)

        // If `role_arn` is defined, check for source profile or credential source
        if let roleArn = credentials.roleArn ?? config?.roleArn {
            let sessionName = credentials.roleSessionName ?? config?.roleSessionName ?? UUID().uuidString
            let region = config?.region ?? .useast1
            // If `source_profile` is defined, temporary credentials must be loaded via STS AssumeRole operation
            if let _ = credentials.sourceProfile ?? config?.sourceProfile {
                guard let accessKey = credentials.accessKey else {
                    throw ConfigFileError.missingAccessKeyId
                }
                guard let secretAccessKey = credentials.secretAccessKey else {
                    throw ConfigFileError.missingSecretAccessKey
                }
                let provider: CredentialProviderFactory = .static(accessKeyId: accessKey, secretAccessKey: secretAccessKey, sessionToken: credentials.sessionToken)
                return .assumeRole(roleArn: roleArn, sessionName: sessionName, region: region, sourceCredentialProvider: provider)
            }
            // If `credental_source` is defined, temporary credentials must be loaded from source
            else if let credentialSource = credentials.credentialSource ?? config?.credentialSource
            {
                let provider: CredentialProviderFactory
                switch credentialSource {
                case .environment:
                    provider = .environment
                case .ec2Instance:
                    provider = .ec2
                case .ecsContainer:
                    provider = .ecs
                }
                return .assumeRole(roleArn: roleArn, sessionName: sessionName, region: region, sourceCredentialProvider: provider)
            }
            // Invalid configuration
            throw ConfigFileError.invalidCredentialFile
        }

        // Return static credentials
        guard let accessKey = credentials.accessKey else {
            throw ConfigFileError.missingAccessKeyId
        }
        guard let secretAccessKey = credentials.secretAccessKey else {
            throw ConfigFileError.missingSecretAccessKey
        }
        let credential = StaticCredential(accessKeyId: accessKey, secretAccessKey: secretAccessKey, sessionToken: credentials.sessionToken)
        return .staticCredential(credential: credential)
    }

    /// Parse profile configuraton from a file (passed in as byte-buffer), usually `~/.aws/config`
    ///
    /// - Parameters:
    ///   - byteBuffer: contents of the file to parse
    ///   - profile: AWS named profile to load (usually `default`)
    /// - Returns: Combined profile settings
    static func parseProfileConfig(from byteBuffer: ByteBuffer, for profile: String) throws -> ProfileConfig? {
        guard let content = byteBuffer.getString(at: 0, length: byteBuffer.readableBytes),
              let parser = try? INIParser(content)
        else {
            throw ConfigFileError.invalidCredentialFile
        }

        // The credentials file uses a different naming format than the CLI config file for named profiles. Include
        // the prefix word "profile" only when configuring a named profile in the config file. Do not use the word
        // profile when creating an entry in the credentials file.
        // https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html
        let loadedProfile = profile == ConfigFile.defaultProfile ? profile : "profile \(profile)"

        // Gracefully fail if there is no configuration for the given profile
        guard let settings = parser.sections[loadedProfile] else {
            return nil
        }

        // All values are optional for profile configuration
        return ProfileConfig(
            region: settings["region"].flatMap(Region.init(awsRegionName:)),
            roleArn: settings["role_arn"],
            roleSessionName: settings["role_session_name"],
            sourceProfile: settings["source_profile"],
            credentialSource: settings["credential_source"].flatMap(CredentialSource.init(rawValue:))
        )
    }

    /// Parse profile credentials from a file (passed in as byte-buffer), usually `~/.aws/credentials`
    ///
    /// - Parameters:
    ///   - byteBuffer: contents of the file to parse
    ///   - profile: AWS named profile to load (usually `default`)
    ///   - sourceProfile: specifies a named profile with long-term credentials that the AWS CLI can use to assume a role that you specified with the `role_arn` parameter.
    /// - Returns: Combined profile credentials
    static func parseCredentials(from byteBuffer: ByteBuffer, for profile: String, sourceProfile: String?) throws -> ProfileCredentials {
        guard let content = byteBuffer.getString(at: 0, length: byteBuffer.readableBytes),
              let parser = try? INIParser(content)
        else {
            throw ConfigFileError.invalidCredentialFile
        }

        guard let settings = parser.sections[profile] else {
            throw ConfigFileError.missingProfile(profile)
        }

        var accessKey = settings["aws_access_key_id"]
        var secretAccessKey = settings["aws_secret_access_key"]
        var sessionToken = settings["aws_session_token"]

        // If a source profile is indicated, load credentials for STS Assume Role operation.
        // Credentials file settings have precedence over profile configuration settings.
        if let sourceProfile = settings["source_profile"] ?? sourceProfile {
            guard let sourceSettings = parser.sections[sourceProfile] else {
                throw ConfigFileError.missingProfile(sourceProfile)
            }
            accessKey = sourceSettings["aws_access_key_id"]
            secretAccessKey = sourceSettings["aws_secret_access_key"]
            sessionToken = sourceSettings["aws_session_token"]
        }

        return ProfileCredentials(
            accessKey: accessKey,
            secretAccessKey: secretAccessKey,
            sessionToken: sessionToken,
            roleArn: settings["role_arn"],
            roleSessionName: settings["role_session_name"],
            sourceProfile: sourceProfile ?? settings["source_profile"],
            credentialSource: settings["credential_source"].flatMap(CredentialSource.init(rawValue:))
        )
    }

    // MARK: - Path Expansion

    static func expandTildeInFilePath(_ filePath: String) -> String {
        #if os(Linux)
        // We don't want to add more dependencies on Foundation than needed.
        // For this reason we get the expanded filePath on Linux from libc.
        // Since `wordexp` and `wordfree` are not available on iOS we stay
        // with NSString on Darwin.
        return filePath.withCString { ptr -> String in
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
