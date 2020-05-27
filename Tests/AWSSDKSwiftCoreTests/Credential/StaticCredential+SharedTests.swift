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

import XCTest
import NIO
@testable import AWSSDKSwiftCore

class StaticCredential_SharedTests: XCTestCase {

    func testSharedCredentials() {
        let profile = "profile1"
        let accessKey = "FAKE-ACCESS-KEY123"
        let secretKey = "Asecretreglkjrd"
        let sessionToken = "xyz"
        let credential = """
            [\(profile)]
            aws_access_key_id=\(accessKey)
            aws_secret_access_key=\(secretKey)
            aws_session_token=\(sessionToken)
            """
        
        var byteBuffer = ByteBufferAllocator().buffer(capacity: credential.utf8.count)
        byteBuffer.writeString(credential)
        var cred: StaticCredential?
        XCTAssertNoThrow(cred = try StaticCredential.sharedCredentials(from: byteBuffer, for: profile))
        
        XCTAssertEqual(cred?.accessKeyId, accessKey)
        XCTAssertEqual(cred?.secretAccessKey, secretKey)
        XCTAssertEqual(cred?.sessionToken, sessionToken)
    }

    func testSharedCredentialsMissingAccessKey() {
        let profile = "profile1"
        let secretKey = "Asecretreglkjrd"
        let credential = """
            [\(profile)]
            aws_secret_access_key=\(secretKey)
            """
        
        var byteBuffer = ByteBufferAllocator().buffer(capacity: credential.utf8.count)
        byteBuffer.writeString(credential)
        XCTAssertThrowsError(_ = try StaticCredential.sharedCredentials(from: byteBuffer, for: profile)) {
            XCTAssertEqual($0 as? StaticCredential.SharedCredentialError, .missingAccessKeyId)
        }
    }

    func testSharedCredentialsMissingSecretKey() {
        let profile = "profile1"
        let accessKey = "FAKE-ACCESS-KEY123"
        let credential = """
            [\(profile)]
            aws_access_key_id=\(accessKey)
            """
        
        var byteBuffer = ByteBufferAllocator().buffer(capacity: credential.utf8.count)
        byteBuffer.writeString(credential)
        XCTAssertThrowsError(_ = try StaticCredential.sharedCredentials(from: byteBuffer, for: profile)) {
            XCTAssertEqual($0 as? StaticCredential.SharedCredentialError, .missingSecretAccessKey)
        }
    }
    
    func testSharedCredentialsMissingSessionToken() {
        let profile = "profile1"
        let accessKey = "FAKE-ACCESS-KEY123"
        let secretKey = "Asecretreglkjrd"
        let credential = """
            [\(profile)]
            aws_access_key_id=\(accessKey)
            aws_secret_access_key=\(secretKey)
            """
        
        var byteBuffer = ByteBufferAllocator().buffer(capacity: credential.utf8.count)
        byteBuffer.writeString(credential)
        var cred: StaticCredential?
        XCTAssertNoThrow(cred = try StaticCredential.sharedCredentials(from: byteBuffer, for: profile))
        
        XCTAssertEqual(cred?.accessKeyId, accessKey)
        XCTAssertEqual(cred?.secretAccessKey, secretKey)
        XCTAssertNil(cred?.sessionToken)
    }
    
    func testSharedCredentialsMissingProfile() {
        let profile = "profile1"
        let accessKey = "FAKE-ACCESS-KEY123"
        let secretKey = "Asecretreglkjrd"
        let credential = """
            [\(profile)]
            aws_access_key_id=\(accessKey)
            aws_secret_access_key=\(secretKey)
            """
        
        var byteBuffer = ByteBufferAllocator().buffer(capacity: credential.utf8.count)
        byteBuffer.writeString(credential)
        XCTAssertThrowsError(_ = try StaticCredential.sharedCredentials(from: byteBuffer, for: "profile2")) {
            XCTAssertEqual($0 as? StaticCredential.SharedCredentialError, .missingProfile("profile2"))
        }
    }
    
    func testSharedCredentialsParseFailure() {
        let credential = """
        [default]
        aws_access_key_id
        """
        
        var byteBuffer = ByteBufferAllocator().buffer(capacity: credential.utf8.count)
        byteBuffer.writeString(credential)
        XCTAssertThrowsError(_ = try StaticCredential.sharedCredentials(from: byteBuffer, for: "default")) {
            XCTAssertEqual($0 as? StaticCredential.SharedCredentialError, .invalidCredentialFileSyntax)
        }
    }
    
    func testExpandTildeInFilePath() {
        let expandableFilePath = "~/.aws/credentials"
        let expandedNewPath = StaticCredential.expandTildeInFilePath(expandableFilePath)
        
        #if os(Linux)
        XCTAssert(!expandedNewPath.hasPrefix("~"))
        #else
        // this doesn't work on linux because of SR-12843
        let expandedNSString = NSString(string: expandableFilePath).expandingTildeInPath
        XCTAssertEqual(expandedNewPath, expandedNSString)
        #endif
        
        let unexpandableFilePath = "/.aws/credentials"
        let unexpandedNewPath = StaticCredential.expandTildeInFilePath(unexpandableFilePath)
        let unexpandedNSString = NSString(string: unexpandableFilePath).expandingTildeInPath
        
        XCTAssertEqual(unexpandedNewPath, unexpandedNSString)
        XCTAssertEqual(unexpandedNewPath, unexpandableFilePath)
    }
    
    func testSharedCredentialINIParser() {
        // setup
        let credentials = """
            [default]
            aws_access_key_id = AWSACCESSKEYID
            aws_secret_access_key = AWSSECRETACCESSKEY
            """
        let filename = "credentials"
        let filenameURL = URL(fileURLWithPath: filename)
        XCTAssertNoThrow(try Data(credentials.utf8).write(to: filenameURL))
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: filenameURL)) }

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let eventLoop = eventLoopGroup.next()
//        let path = filenameURL.absoluteString
        let future = StaticCredential.fromSharedCredentials(credentialsFilePath: filenameURL.path, on: eventLoop)
        
        var credential: StaticCredential?
        XCTAssertNoThrow(credential = try future.wait())
        XCTAssertEqual(credential?.accessKeyId, "AWSACCESSKEYID")
        XCTAssertEqual(credential?.secretAccessKey, "AWSSECRETACCESSKEY")
    }
}
