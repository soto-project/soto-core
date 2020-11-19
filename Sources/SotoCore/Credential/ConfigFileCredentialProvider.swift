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

import INIParser
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
    /// - missingProfile: If the profile requested was not found
    /// - missingAccessKeyId: If the access key ID was not found
    /// - missingSecretAccessKey: If the secret access key was not found
    enum ConfigFileError: Error, Equatable {
        case invalidCredentialFileSyntax
        case missingProfile(String)
        case missingAccessKeyId
        case missingSecretAccessKey
    }

    /// promise to find a credential provider
    let startupPromise: EventLoopPromise<CredentialProvider>
    /// lock for access to _internalProvider.
    let lock = Lock()
    /// internal version of internal provider. Should access this through `internalProvider`
    var _internalProvider: CredentialProvider?

    init(credentialsFilePath: String, profile: String? = nil, context: CredentialProviderFactory.Context) {
        self.startupPromise = context.eventLoop.makePromise(of: CredentialProvider.self)
        self.startupPromise.futureResult.whenSuccess { result in
            self.internalProvider = result
        }
        self.fromSharedCredentials(credentialsFilePath: credentialsFilePath, profile: profile, on: context.eventLoop)
    }

    /// Load credentials from the aws cli config path `~/.aws/credentials`
    ///
    /// - Parameters:
    ///   - credentialsFilePath: credential config file
    ///   - profile: profile to use
    ///   - eventLoop: eventLoop to run everything on
    func fromSharedCredentials(
        credentialsFilePath: String,
        profile: String?,
        on eventLoop: EventLoop
    ) {
        let profile = profile ?? Environment["AWS_PROFILE"] ?? "default"
        let threadPool = NIOThreadPool(numberOfThreads: 1)
        threadPool.start()
        let fileIO = NonBlockingFileIO(threadPool: threadPool)

        Self.getSharedCredentialsFromDisk(credentialsFilePath: credentialsFilePath, profile: profile, on: eventLoop, using: fileIO)
            .always { _ in
                // shutdown the threadpool async
                threadPool.shutdownGracefully { _ in }
            }
            .cascade(to: self.startupPromise)
    }

    static func getSharedCredentialsFromDisk(
        credentialsFilePath: String,
        profile: String,
        on eventLoop: EventLoop,
        using fileIO: NonBlockingFileIO
    ) -> EventLoopFuture<CredentialProvider> {
        let filePath = Self.expandTildeInFilePath(credentialsFilePath)

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
        let string = byteBuffer.getString(at: 0, length: byteBuffer.readableBytes)!
        var parser: INIParser
        do {
            parser = try INIParser(string)
        } catch INIParser.Error.invalidSyntax {
            throw ConfigFileError.invalidCredentialFileSyntax
        }

        guard let config = parser.sections[profile] else {
            throw ConfigFileError.missingProfile(profile)
        }

        // Profile credentials can "borrow" values from the 'default' profile when they have not been overriden
        let defaultConfig = parser.sections["default"]

        guard let accessKeyId = config["aws_access_key_id"] ?? defaultConfig?["aws_access_key_id"] else {
            throw ConfigFileError.missingAccessKeyId
        }

        guard let secretAccessKey = config["aws_secret_access_key"] ?? defaultConfig?["aws_secret_access_key"] else {
            throw ConfigFileError.missingSecretAccessKey
        }

        let sessionToken = config["aws_session_token"] ?? defaultConfig?["aws_session_token"]

        return StaticCredential(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey, sessionToken: sessionToken)
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
