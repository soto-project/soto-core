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

class ConfigFileCredentialProvider: CredentialProviderSelector {

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
        self.fromSharedCredentials(credentialsFilePath: credentialsFilePath, configFilePath: configFilePath, profile: profile, context: context)
    }

    /// Load credentials from AWS cli credentials and profile configuration files
    ///
    /// - Parameters:
    ///   - credentialsFilePath: credential config file
    ///   - configFilePath: profile configuration file
    ///   - profile: profile to use
    ///   - context: credential provider factory context
    func fromSharedCredentials(
        credentialsFilePath: String,
        configFilePath: String?,
        profile: String?,
        context: CredentialProviderFactory.Context
    ) {
        let profile = profile ?? Environment["AWS_PROFILE"] ?? ConfigFileLoader.default
        let threadPool = NIOThreadPool(numberOfThreads: 1)
        threadPool.start()
        let fileIO = NonBlockingFileIO(threadPool: threadPool)

        Self.getSharedCredentialsFromDisk(credentialsFilePath: credentialsFilePath, configFilePath: configFilePath,
                                          profile: profile, context: context, using: fileIO)
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
    ///   - context: credential provider factory context
    ///   - fileIO: non-blocking file IO
    /// - Returns: Promise of a Credential Provider (StaticCredentials or STSAssumeRole)
    static func getSharedCredentialsFromDisk(
        credentialsFilePath: String,
        configFilePath: String?,
        profile: String,
        context: CredentialProviderFactory.Context,
        using fileIO: NonBlockingFileIO
    ) -> EventLoopFuture<CredentialProvider> {

        return loadFile(path: credentialsFilePath, on: context.eventLoop, using: fileIO)
            .flatMap { credentialsByteBuffer -> EventLoopFuture<(ByteBuffer, ByteBuffer?)> in
                if let path = configFilePath {
                    return Self.loadFile(path: path, on: context.eventLoop, using: fileIO).map { (credentialsByteBuffer, $0) }
                }
                else {
                    return context.eventLoop.makeSucceededFuture((credentialsByteBuffer, nil))
                }
            }
            .flatMapThrowing { credentialsByteBuffer, configByteBuffer in
                return try ConfigFileLoader.sharedCredentials(from: credentialsByteBuffer, configByteBuffer: configByteBuffer,
                                                              for: profile, context: context)
            }
    }

    /// Load a file from disk without blocking the current thread
    /// - Parameters:
    ///   - path: path for the file to load
    ///   - eventLoop: event loop to run everything on
    ///   - fileIO: non-blocking file IO
    /// - Returns: Event loop future with file contents in a byte-buffer
    static func loadFile(path: String, on eventLoop: EventLoop, using fileIO: NonBlockingFileIO) -> EventLoopFuture<ByteBuffer> {
        let path = expandTildeInFilePath(path)

        return fileIO.openFile(path: path, eventLoop: eventLoop)
            .flatMap { handle, region in
                fileIO.read(fileRegion: region, allocator: ByteBufferAllocator(), eventLoop: eventLoop).map { ($0, handle) }
            }
            .flatMapThrowing { byteBuffer, handle in
                try handle.close()
                return byteBuffer
            }
    }

    static func expandTildeInFilePath(_ filePath: String) -> String {
        #if os(Linux)
        // We don't want to add more dependencies on Foundation than needed.
        // For this reason we get the expanded filePath on Linux from libc.
        // Since `wordexp` and `wordfree` are not available on iOS we stay
        // with NSString on Darwin.
        return filePath.withCString { (ptr) -> String in
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
