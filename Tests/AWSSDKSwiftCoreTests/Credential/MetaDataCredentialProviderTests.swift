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

class MetaDataCredentialProviderTests: XCTestCase {

    class MetaDataTestClient: MetaDataClient {
        typealias MetaData = LocalMetaData
        
        struct LocalMetaData: CredentialContainer {
            var credential: ExpiringCredential
            
            init(from decoder: Decoder) throws {
                fatalError("Unimplemented")
            }
            
            init(credential: RotatingCredential) {
                self.credential = credential
            }
        }
        
        let callback: (EventLoop) -> EventLoopFuture<LocalMetaData>
        
        init(_ callback: @escaping (EventLoop) -> EventLoopFuture<LocalMetaData>) {
            self.callback = callback
        }
        
        func getMetaData(on eventLoop: EventLoop) -> EventLoopFuture<LocalMetaData> {
            eventLoop.flatSubmit() {
                self.callback(eventLoop)
            }
        }
    }
    
    func testGetCredentialAndReuseIfStillValid() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        let loop = group.next()
        
        let cred = RotatingCredential(
            accessKeyId: "abc123",
            secretAccessKey: "abc123",
            sessionToken: "abc123",
            expiration: Date(timeIntervalSinceNow: 60 * 5))
        let meta = MetaDataTestClient.LocalMetaData(credential: cred)
        
        var hitCount = 0
        let client = MetaDataTestClient {
            hitCount += 1
            return $0.makeSucceededFuture(meta)
        }
        let provider = MetaDataCredentialProvider(eventLoop: loop, client: client)
        
        // get credentials for first time
        var returned: Credential?
        XCTAssertNoThrow(returned = try provider.getCredential(on: loop).wait())
        
        XCTAssertEqual(returned?.accessKeyId, cred.accessKeyId)
        XCTAssertEqual(returned?.secretAccessKey, cred.secretAccessKey)
        XCTAssertEqual(returned?.sessionToken, cred.sessionToken)
        XCTAssertEqual((returned as? RotatingCredential)?.expiration, cred.expiration)
        
        // get credentials a second time, callback must not be hit
        XCTAssertNoThrow(returned = try provider.getCredential(on: loop).wait())
        XCTAssertEqual(returned?.accessKeyId, cred.accessKeyId)
        XCTAssertEqual(returned?.secretAccessKey, cred.secretAccessKey)
        XCTAssertEqual(returned?.sessionToken, cred.sessionToken)
        XCTAssertEqual((returned as? RotatingCredential)?.expiration, cred.expiration)
        
        // ensure callback was only hit once
        XCTAssertEqual(hitCount, 1)
    }
    
    func testGetCredentialHighlyConcurrent() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        let loop = group.next()
        
        let cred = RotatingCredential(
            accessKeyId: "abc123",
            secretAccessKey: "abc123",
            sessionToken: "abc123",
            expiration: Date(timeIntervalSinceNow: 60 * 5))
        let meta = MetaDataTestClient.LocalMetaData(credential: cred)
        
        let promise = loop.makePromise(of: MetaDataTestClient.LocalMetaData.self)
        
        var hitCount = 0
        let client = MetaDataTestClient { _ in
            hitCount += 1
            return promise.futureResult
        }
        let provider = MetaDataCredentialProvider(eventLoop: loop, client: client)
        
        var futures = [EventLoopFuture<Void>]()
        for _ in 1...10000 {
            let loop = group.next()
            let future: EventLoopFuture<Void> = loop.flatSubmit {
                // this should be executed right away
                provider.getCredential(on: loop).map { returned in
                    // this should be executed after the promise is fulfilled.
                    XCTAssertEqual(returned.accessKeyId, cred.accessKeyId)
                    XCTAssertEqual(returned.secretAccessKey, cred.secretAccessKey)
                    XCTAssertEqual(returned.sessionToken, cred.sessionToken)
                    XCTAssertEqual((returned as? RotatingCredential)?.expiration, cred.expiration)
                    XCTAssert(loop.inEventLoop)
                }
            }
            futures.append(future)
        }
        
        promise.succeed(meta)
        
        XCTAssertNoThrow(try futures.forEach { try $0.wait() })
        
        // ensure callback was only hit once
        XCTAssertEqual(hitCount, 1)
    }
    
    func testAlwaysGetNewTokenIfTokenLifetimeForUseIsShorterThanLifetime() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        let loop = group.next()
        
        var hitCount = 0
        let client = MetaDataTestClient { (eventLoop) in
            hitCount += 1
            let cred = RotatingCredential(
                accessKeyId: "abc123",
                secretAccessKey: "abc123",
                sessionToken: "abc123",
                expiration: Date(timeIntervalSinceNow: 60 * 2))
            let meta = MetaDataTestClient.LocalMetaData(credential: cred)
            return eventLoop.makeSucceededFuture(meta)
        }
        let provider = MetaDataCredentialProvider(eventLoop: loop, client: client)
        
        let iterations = 100
        for _ in 0..<100 {
            XCTAssertNoThrow(_ = try provider.getCredential(on: loop).wait())
        }
        
        // ensure callback was only hit once
        XCTAssertEqual(hitCount, iterations)
    }
}
