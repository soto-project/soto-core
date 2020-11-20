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

        Self.getSharedCredentialsFromDisk(credentialsFilePath: credentialsFilePath, configFilePath: configFilePath, profile: profile, on: eventLoop, using: fileIO)
            .always { _ in
                // shutdown the threadpool async
                threadPool.shutdownGracefully { _ in }
            }
            .cascade(to: self.startupPromise)
    }

    /// Load credentials from disk
    /// - Parameters:
    ///   - credentialsFilePath: file path for AWS credentials file
    ///   - configFilePath: file path for AWS config file (optional)
    ///   - profile: named profile to load (optional)
    ///   - eventLoop: event loop to run everything on
    ///   - fileIO: non-blocking file IO
    /// - Returns: Promise of a Credential Provider (StaticCredentials or STSAssumeRole)
    static func getSharedCredentialsFromDisk(
        credentialsFilePath: String,
        configFilePath: String?,
        profile: String,
        on eventLoop: EventLoop,
        using fileIO: NonBlockingFileIO
    ) -> EventLoopFuture<CredentialProvider> {

        return loadFile(path: credentialsFilePath, on: eventLoop, using: fileIO)
            .flatMap { credentialsByteBuffer -> EventLoopFuture<(ByteBuffer, ByteBuffer?)> in
                if let path = configFilePath {
                    return Self.loadFile(path: path, on: eventLoop, using: fileIO).map { (credentialsByteBuffer, $0) }
                }
                else {
                    return eventLoop.makeSucceededFuture((credentialsByteBuffer, nil))
                }
            }
            .flatMapThrowing { credentialsByteBuffer, configByteBuffer in
                return try Self.sharedCredentials(from: credentialsByteBuffer, configByteBuffer: configByteBuffer, for: profile)
            }
    }

    /// Load a file from disk without blocking the current thread
    /// - Parameters:
    ///   - path: path for the file to load
    ///   - eventLoop: event loop to run everything on
    ///   - fileIO: non-blocking file IO
    /// - Returns: Event loop future with file contents in a byte-buffer
    static func loadFile(path: String, on eventLoop: EventLoop, using fileIO: NonBlockingFileIO) -> EventLoopFuture<ByteBuffer> {
        let path = ConfigFileLoader.expandTildeInFilePath(path)

        return fileIO.openFile(path: path, eventLoop: eventLoop)
            .flatMap { handle, region in
                fileIO.read(fileRegion: region, allocator: ByteBufferAllocator(), eventLoop: eventLoop).map { ($0, handle) }
            }
            .flatMapThrowing { byteBuffer, handle in
                try handle.close()
                return byteBuffer
            }
    }

    /// Load shared credentials and profile configuration from passed in byte-buffers
    ///
    /// - Parameters:
    ///   - credentialsByteBuffer: contents of AWS shared credentials file (usually `~/.aws/credentials`
    ///   - configByteBuffer: contents of AWS profile configuration file (usually `~/.aws/config`
    ///   - profile: named profile to load (usually `default`)
    /// - Returns: Credential Provider (StaticCredentials or STSAssumeRole)
    static func sharedCredentials(from credentialsByteBuffer: ByteBuffer, configByteBuffer: ByteBuffer? = nil, for profile: String) throws -> StaticCredential {
        var config: ConfigFileLoader.ProfileConfig?
        if let byteBuffer = configByteBuffer {
            config = try ConfigFileLoader.loadProfileConfig(from: byteBuffer, for: profile)
        }
        let credentials = try ConfigFileLoader.loadCredentials(from: credentialsByteBuffer, for: profile, sourceProfile: config?.sourceProfile)
        dump(config)
        dump(credentials)

        // TODO: Check if credentials containe a `role_arn`, in which case an STSAssumeRole credentails provided is needed.

        return StaticCredential(accessKeyId: credentials.accessKey,
                                secretAccessKey: credentials.secretAccessKey,
                                sessionToken: credentials.sessionToken)
    }

}
