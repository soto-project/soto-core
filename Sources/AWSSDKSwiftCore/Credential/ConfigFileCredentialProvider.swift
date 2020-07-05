//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Logging
import NIO
import INIParser
import AWSSignerV4
#if os(Linux)
import Glibc
#else
import Foundation.NSString
#endif


struct AWSConfigFileCredentialProvider: CredentialProvider {
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

    let credentialsFilePath: String
    let profile: String

    init(credentialsFilePath: String, profile: String? = nil) {
        self.credentialsFilePath = credentialsFilePath
        self.profile = profile ?? Environment["AWS_PROFILE"] ?? "default"
    }

    func getCredential(on eventLoop: EventLoop, logger: Logger) -> EventLoopFuture<Credential> {
        return AWSConfigFileCredentialProvider.fromSharedCredentials(credentialsFilePath: credentialsFilePath, profile: profile, on: eventLoop)
            .map { $0 }
    }

    /// Load static credentials from the aws cli config path `~/.aws/credentials`
    ///
    /// - returns: An `EventLoopFuture` with a `SharedCredentialError` in the error
    ///            case or a `StaticCredential` in the success case
    static func fromSharedCredentials(
        credentialsFilePath: String,
        profile: String = Environment["AWS_PROFILE"] ?? "default",
        on eventLoop: EventLoop) -> EventLoopFuture<StaticCredential>
    {
        let threadPool = NIOThreadPool(numberOfThreads: 1)
        threadPool.start()
        let fileIO = NonBlockingFileIO(threadPool: threadPool)
        
        return Self.getSharedCredentialsFromDisk(credentialsFilePath: credentialsFilePath, profile: profile, on: eventLoop, using: fileIO)
            .always { (_) in
                // shutdown the threadpool async
                threadPool.shutdownGracefully { (_) in }
            }
    }
    
    static func getSharedCredentialsFromDisk(
        credentialsFilePath: String,
        profile: String,
        on eventLoop: EventLoop,
        using fileIO: NonBlockingFileIO) -> EventLoopFuture<StaticCredential>
    {
        let filePath = Self.expandTildeInFilePath(credentialsFilePath)
        
        return fileIO.openFile(path: filePath, eventLoop: eventLoop)
            .flatMap { (handle, region) in
                fileIO.read(fileRegion: region, allocator: ByteBufferAllocator(), eventLoop: eventLoop).map { ($0, handle) }
            }
            .flatMapThrowing { (byteBuffer, handle) in
                try handle.close()
                return try Self.sharedCredentials(from: byteBuffer, for: profile)
            }
    }
    
    static func sharedCredentials(from byteBuffer: ByteBuffer, for profile: String) throws -> StaticCredential {
        let string = byteBuffer.getString(at: 0, length: byteBuffer.readableBytes)!
        var parser: INIParser
        do {
            parser = try INIParser(string)
        }
        catch INIParser.Error.invalidSyntax {
            throw ConfigFileError.invalidCredentialFileSyntax
        }
        
        guard let config = parser.sections[profile] else {
            throw ConfigFileError.missingProfile(profile)
        }
        
        guard let accessKeyId = config["aws_access_key_id"] else {
            throw ConfigFileError.missingAccessKeyId
        }
        
        guard let secretAccessKey = config["aws_secret_access_key"] else {
            throw ConfigFileError.missingSecretAccessKey
        }
        
        let sessionToken = config["aws_session_token"]
        
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
            guard 0 == wordexp(ptr, &wexp, 0), let we_wordv = wexp.we_wordv else {
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
        #else
        return NSString(string: filePath).expandingTildeInPath
        #endif
    }
}
