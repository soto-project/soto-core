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

import Logging
import NIO
import NIOConcurrencyHelpers
import SotoSignerV4

class AWSConfigFileCredentialProvider: CredentialProviderSelector {

    /// promise to find a credential provider
    let startupPromise: EventLoopPromise<CredentialProvider>
    /// lock for access to _internalProvider.
    let lock = Lock()
    /// internal version of internal provider. Should access this through `internalProvider`
    var _internalProvider: CredentialProvider?

    init(credentialsFilePath: String, configFilePath: String? = nil, profile: String? = nil, context: CredentialProviderFactory.Context) {
        self.startupPromise = context.eventLoop.makePromise(of: CredentialProvider.self)
        self.startupPromise.futureResult.whenSuccess { result in
            self.internalProvider = result
        }
        self.fromSharedCredentials(credentialsFilePath: credentialsFilePath, configFilePath: configFilePath, profile: profile, on: context.eventLoop)
    }

    /// Load credentials from AWS cli credentials and profile configuration files
    ///
    /// - Parameters:
    ///   - credentialsFilePath: credential config file
    ///   - configFilePath: profile configuration file
    ///   - profile: profile to use
    ///   - eventLoop: eventLoop to run everything on
    func fromSharedCredentials(
        credentialsFilePath: String,
        configFilePath: String?,
        profile: String?,
        on eventLoop: EventLoop
    ) {
        let profile = profile ?? Environment["AWS_PROFILE"] ?? ConfigFileLoader.default
        let threadPool = NIOThreadPool(numberOfThreads: 1)
        threadPool.start()
        let fileIO = NonBlockingFileIO(threadPool: threadPool)

        // TODO:
        // - Identify if a profile configuration is needed/exists
        // - Determine if need to load temporary credentials from STS
        Self.getSharedCredentialsFromDisk(credentialsFilePath: credentialsFilePath, configFilePath: configFilePath, profile: profile, on: eventLoop, using: fileIO)
            .always { _ in
                // shutdown the threadpool async
                threadPool.shutdownGracefully { _ in }
            }
            .cascade(to: self.startupPromise)
    }

    static func getSharedCredentialsFromDisk(
        credentialsFilePath: String,
        configFilePath: String?,
        profile: String,
        on eventLoop: EventLoop,
        using fileIO: NonBlockingFileIO
    ) -> EventLoopFuture<CredentialProvider> {
        let credentialsFilePath = ConfigFileLoader.expandTildeInFilePath(credentialsFilePath)
        let configFilePath = configFilePath.flatMap(ConfigFileLoader.expandTildeInFilePath(_:))

        return fileIO.openFile(path: credentialsFilePath, eventLoop: eventLoop)
            .flatMap { handle, region in
                fileIO.read(fileRegion: region, allocator: ByteBufferAllocator(), eventLoop: eventLoop).map { ($0, handle) }
            }
            .flatMap { credentialsByteBuffer, credentialsHandle in
                if let path = configFilePath {
                    return fileIO.openFile(path: configFilePath, eventLoop: eventLoop).map { handle, region in
                        (credentialsByteBuffer, credentialsHandle, handle, region)
                    }
                } else {
                    return (credentialsByteBuffer, credentialsHandle, nil, nil)
                }
            }
            .flatMap { credentialsByteBuffer, credentialsHandle, configHandle, configRegion in
                fileIO.read(fileRegion: configRegion, allocator: ByteBufferAllocator(), eventLoop: eventLoop).map { content, handle in
                    return (credentialsByteBuffer, credentialsHandle, content, configHandle)
                }
            }
            .flatMapThrowing { credentialsByteBuffer, credentialsHandle, configByteBuffer, configHandle in
                try credentialsHandle.close()
                try configByteBuffer?.close()
                return try Self.sharedCredentials(from: credentialsByteBuffer, configByteBuffer: configByteBuffer, for: profile)
            }
    }

    /// Load shared credentials and profile configuration from passed in byte-buffers
    ///
    /// - Parameters:
    ///   - credentialsByteBuffer: contents of AWS shared credentials file (usually `~/.aws/credentials`
    ///   - configByteBuffer: contents of AWS profile configuration file (usually `~/.aws/config`
    ///   - profile: named profile to load (usually `default`)
    static func sharedCredentials(from credentialsByteBuffer: ByteBuffer, configByteBuffer: ByteBuffer?, for profile: String) throws -> StaticCredential {
        var config: ConfigFileLoader.ProfileConfig?
        if let byteBuffer = configByteBuffer {
            config = try ConfigFileLoader.loadProfileConfig(from: byteBuffer, for: profile)
        }
        let credentials = try ConfigFileLoader.loadCredentials(from: credentialsByteBuffer, for: profile, sourceProfile: config?.sourceProfile)


        return StaticCredential(accessKeyId: credentials.accessKey,
                                secretAccessKey: credentials.secretAccessKey,
                                sessionToken: credentials.sessionToken)
    }

}
