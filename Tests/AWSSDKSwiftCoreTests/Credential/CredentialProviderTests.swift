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
import AWSTestUtils

class CredentialProviderTests: XCTestCase {

    func testCredentialProvider() {
        let cred = StaticCredential(accessKeyId: "abc", secretAccessKey: "123", sessionToken: "xyz")
        
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        let loop = group.next()
        var returned: Credential?
        XCTAssertNoThrow(returned = try cred.getCredential(on: loop).wait())
        
        XCTAssertEqual(returned as? StaticCredential, cred)
    }

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
}
