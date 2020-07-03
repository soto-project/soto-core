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

@testable import AWSSDKSwiftCore
import XCTest
import NIO
import AsyncHTTPClient

class CredentialProviderTests: XCTestCase {

    // make sure getCredential in client CredentialProvider doesnt get called more than once
    func testDeferredCredentialProvider() {
        class MyCredentialProvider: CredentialProvider {
            var alreadyCalled = false
            func getCredential(on eventLoop: EventLoop) -> EventLoopFuture<Credential> {
                if alreadyCalled == false {
                    self.alreadyCalled = true
                    return eventLoop.makeSucceededFuture(StaticCredential(accessKeyId: "ACCESSKEYID", secretAccessKey: "SECRETACCESSKET"))
                } else {
                    return eventLoop.makeFailedFuture(CredentialProviderError.noProvider)
                }
            }
        }
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let eventLoop = eventLoopGroup.next()
        let deferredProvider = DeferredCredentialProvider(eventLoop: eventLoop, provider: MyCredentialProvider())
        XCTAssertNoThrow(_ = try deferredProvider.getCredential(on: eventLoop).wait())
        XCTAssertNoThrow(_ = try deferredProvider.getCredential(on: eventLoop).wait())
    }

    func testConfigFileSuccess() {
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
        let eventLoop = eventLoopGroup.next()
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoop))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let factory = CredentialProviderFactory.configFile(credentialsFilePath: filenameURL.path)
        
        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop))
        
        var credential: Credential?
        XCTAssertNoThrow(credential = try provider.getCredential(on: eventLoop).wait())
        XCTAssertEqual(credential?.accessKeyId, "AWSACCESSKEYID")
        XCTAssertEqual(credential?.secretAccessKey, "AWSSECRETACCESSKEY")
    }
    
    func testConfigFileNotAvailable() {
        let filename = "credentials_not_existing"
        let filenameURL = URL(fileURLWithPath: filename)

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop = eventLoopGroup.next()
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoop))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let factory = CredentialProviderFactory.configFile(credentialsFilePath: filenameURL.path)
        
        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop))
        
        XCTAssertThrowsError(_ = try provider.getCredential(on: eventLoop).wait()) { (error) in
            print("\(error)")
            XCTAssertEqual(error as? CredentialProviderError, .noProvider)
        }
    }
}
