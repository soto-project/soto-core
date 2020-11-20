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
#if os(Linux)
import Glibc
#else
import Foundation.NSString
#endif

class AWSConfigFileCredentialProvider: CredentialProviderSelector {
    /// Errors occurring when initializing a FileCredential
    ///
    /// - missingAccessKeyId: If the access key ID was not found
    /// - missingSecretAccessKey: If the secret access key was not found
    enum ConfigFileCredentialProviderError: Error, Equatable {
        case missingAccessKeyId
        case missingSecretAccessKey
    }

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
        let profile = profile ?? Environment["AWS_PROFILE"] ?? "default"
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
        let filePath = ConfigFileLoader.expandTildeInFilePath(credentialsFilePath)

        return fileIO.openFile(path: filePath, eventLoop: eventLoop)
            .flatMap { handle, region in
                fileIO.read(fileRegion: region, allocator: ByteBufferAllocator(), eventLoop: eventLoop).map { ($0, handle) }
            }
            .flatMapThrowing { byteBuffer, handle in
                try handle.close()
                return try Self.sharedCredentials(from: byteBuffer, for: profile)
            }
    }

    static func sharedCredentials(from byteBuffer: ByteBuffer, for profile: String) throws -> StaticCredential {
        let settings = try ConfigFileLoader.loadCredentials(from: byteBuffer, for: profile, sourceProfile: nil)

        guard let accessKeyId = settings["aws_access_key_id"] else {
            throw ConfigFileCredentialProviderError.missingAccessKeyId
        }

        guard let secretAccessKey = settings["aws_secret_access_key"] else {
            throw ConfigFileCredentialProviderError.missingSecretAccessKey
        }

        let sessionToken = settings["aws_session_token"]

        return StaticCredential(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey, sessionToken: sessionToken)
    }

}
