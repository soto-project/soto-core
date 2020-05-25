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
    
    func testECSMetaDataClient() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        
        let loop = group.next()
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(loop))
        defer { XCTAssertNoThrow( try httpClient.syncShutdown()) }
        let testServer = AWSTestServer(serviceProtocol: .json)
        
        let path = "/" + UUID().uuidString
        Environment.set(path, for: ECSMetaDataClient.RelativeURIEnvironmentName)
        defer { Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName) }
        
        let client = ECSMetaDataClient(httpClient: httpClient, host: "localhost:\(testServer.web.serverPort)")
        let future = client!.getMetaData(on: loop)
        
        let accessKeyId = "abc123"
        let secretAccessKey = "123abc"
        let sessionToken = "xyz987"
        let expiration = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded() + 60 * 2)
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        let roleArn = "asd:aws:asd"
        
        XCTAssertNoThrow(try testServer.process { (request) -> AWSTestServer.Result<AWSTestServer.Response> in
            XCTAssertEqual(request.uri, path)
            XCTAssertEqual(request.method, .GET)
            
            let json = """
                {
                    "AccessKeyId": "\(accessKeyId)",
                    "SecretAccessKey": "\(secretAccessKey)",
                    "Token": "\(sessionToken)",
                    "Expiration": "\(dateFormatter.string(from: expiration))",
                    "RoleArn": "\(roleArn)"
                }
                """
            var byteButter = ByteBufferAllocator().buffer(capacity: json.utf8.count)
            byteButter.writeString(json)
            return .init(output: .init(httpStatus: .ok, body: byteButter), continueProcessing: false)
        })
        
        var metaData: ECSMetaDataClient.MetaData?
        XCTAssertNoThrow(metaData = try future.wait())
        
        XCTAssertEqual(metaData?.accessKeyId, accessKeyId)
        XCTAssertEqual(metaData?.secretAccessKey, secretAccessKey)
        XCTAssertEqual(metaData?.token, sessionToken)
        XCTAssertEqual(metaData?.expiration, expiration)
        XCTAssertEqual(metaData?.roleArn, roleArn)
        
        XCTAssertEqual(metaData?.credential.accessKeyId, accessKeyId)
        XCTAssertEqual(metaData?.credential.secretAccessKey, secretAccessKey)
        XCTAssertEqual(metaData?.credential.sessionToken, sessionToken)
    }
    
    func testECSMetaDataClientDefaultHost() {
        XCTAssertEqual(ECSMetaDataClient.Host, "169.254.170.2")
        XCTAssertEqual(ECSMetaDataClient.RelativeURIEnvironmentName, "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")
    }
    
    func testECSMetaDataClientIsNotCreatedWithoutEnvVariable() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        
        let loop = group.next()
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(loop))
        defer { XCTAssertNoThrow( try httpClient.syncShutdown()) }

        Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName)
        
        XCTAssertNil(ECSMetaDataClient(httpClient: httpClient, host: "localhost"))
    }
}
