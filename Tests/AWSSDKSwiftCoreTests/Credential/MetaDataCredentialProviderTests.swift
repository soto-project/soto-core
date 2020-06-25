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

class MetaDataCredentialProviderTests: XCTestCase {
    
    // MARK: - ECSMetaDataClient -
    
    func testECSMetaDataClient() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        
        let loop = group.next()
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(loop))
        defer { XCTAssertNoThrow( try httpClient.syncShutdown()) }
        let awsClient = createAWSClient(httpClientProvider: .shared(httpClient))
        defer { XCTAssertNoThrow( try awsClient.syncShutdown()) }
        let testServer = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try testServer.stop()) }
        
        let path = "/" + UUID().uuidString
        Environment.set(path, for: ECSMetaDataClient.RelativeURIEnvironmentName)
        defer { Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName) }
        
        let client = ECSMetaDataClient(host: "\(testServer.host):\(testServer.serverPort)")
        XCTAssertEqual(client.setup(with: awsClient), true)
        let future = client.getMetaData(on: loop)
        
        let accessKeyId = "abc123"
        let secretAccessKey = "123abc"
        let sessionToken = "xyz987"
        let expiration = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded() + 60 * 2)
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        let roleArn = "asd:aws:asd"
        
        XCTAssertNoThrow(try testServer.processRaw {
            (request: AWSTestServer.Request) -> AWSTestServer.Result<AWSTestServer.Response> in
            
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
            return .result(.init(httpStatus: .ok, body: byteButter), continueProcessing: false)
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
    
    func testECSMetaDataClientThrowsErrorWithoutEnvVariable() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        
        let loop = group.next()
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(loop))
        defer { XCTAssertNoThrow( try httpClient.syncShutdown()) }
        let awsClient = createAWSClient(httpClientProvider: .shared(httpClient))
        defer { XCTAssertNoThrow( try awsClient.syncShutdown()) }

        Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName)
        
        let ecsClient = ECSMetaDataClient(host: "localhost")
        XCTAssertEqual(ecsClient.setup(with: awsClient), false)
        XCTAssertThrowsError(_ = try ecsClient.getCredential(on: loop).wait()) { error in
            switch error {
            case MetaDataClientError.noECSMetaDataService:
                break
            default:
                XCTFail()
            }
        }
    }
    
    // MARK: - InstanceMetaDataClient -
    
    func testEC2InstanceMetaDataClientUsingVersion2() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        
        let loop = group.next()
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(loop))
        defer { XCTAssertNoThrow( try httpClient.syncShutdown()) }
        let awsClient = createAWSClient(httpClientProvider: .shared(httpClient))
        defer { XCTAssertNoThrow( try awsClient.syncShutdown()) }
        let testServer = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try testServer.stop()) }
        
        let path = "/" + UUID().uuidString
        Environment.set(path, for: ECSMetaDataClient.RelativeURIEnvironmentName)
        defer { Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName) }
        
        let client = InstanceMetaDataClient(host: "\(testServer.host):\(testServer.serverPort)")
        XCTAssertEqual(client.setup(with: awsClient), true)
        let future = client.getMetaData(on: loop)
        
        let token = UUID().uuidString
        XCTAssertNoThrow(try testServer.processRaw { (request) -> AWSTestServer.Result<AWSTestServer.Response> in
            XCTAssertEqual(request.uri, InstanceMetaDataClient.TokenUri)
            XCTAssertEqual(request.method, .PUT)
            XCTAssertEqual(request.headers[InstanceMetaDataClient.TokenTimeToLiveHeader.name], InstanceMetaDataClient.TokenTimeToLiveHeader.value)
            
            var byteBuffer = ByteBufferAllocator().buffer(capacity: token.utf8.count)
            byteBuffer.writeString(token)
            return .result(.init(httpStatus: .ok, body: byteBuffer), continueProcessing: false)
        })
        
        let roleName = "MySuperDuperAwesomeRoleName"
        XCTAssertNoThrow(try testServer.processRaw { (request) -> AWSTestServer.Result<AWSTestServer.Response> in
            XCTAssertEqual(request.uri, InstanceMetaDataClient.CredentialUri)
            XCTAssertEqual(request.method, .GET)
            XCTAssertEqual(request.headers[InstanceMetaDataClient.TokenHeaderName], token)
            
            var byteBuffer = ByteBufferAllocator().buffer(capacity: roleName.utf8.count)
            byteBuffer.writeString(roleName)
            return .result(.init(httpStatus: .ok, body: byteBuffer), continueProcessing: false)
        })
        
        let accessKeyId = "abc123"
        let secretAccessKey = "123abc"
        let sessionToken = "xyz987"
        let code = "Success"
        let type = "AWS-HMAC"
        let expiration = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded() + 60 * 2)
        let lastUpdated = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded() - 60 * 2)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        XCTAssertNoThrow(try testServer.processRaw { (request) -> AWSTestServer.Result<AWSTestServer.Response> in
            XCTAssertEqual(request.uri, InstanceMetaDataClient.CredentialUri.appending(roleName))
            XCTAssertEqual(request.method, .GET)
            XCTAssertEqual(request.headers[InstanceMetaDataClient.TokenHeaderName], token)
            
            let json = """
                {
                    "AccessKeyId": "\(accessKeyId)",
                    "SecretAccessKey": "\(secretAccessKey)",
                    "Token": "\(sessionToken)",
                    "Expiration": "\(dateFormatter.string(from: expiration))",
                    "Code": "\(code)",
                    "LastUpdated": "\(dateFormatter.string(from: lastUpdated))",
                    "Type": "\(type)"
                }
                """

            var byteBuffer = ByteBufferAllocator().buffer(capacity: json.utf8.count)
            byteBuffer.writeString(json)
            return .result(.init(httpStatus: .ok, body: byteBuffer), continueProcessing: false)
        })
        
        var metaData: InstanceMetaDataClient.MetaData?
        XCTAssertNoThrow(metaData = try future.wait())
        
        XCTAssertEqual(metaData?.accessKeyId, accessKeyId)
        XCTAssertEqual(metaData?.secretAccessKey, secretAccessKey)
        XCTAssertEqual(metaData?.token, sessionToken)
        XCTAssertEqual(metaData?.expiration, expiration)
        XCTAssertEqual(metaData?.code, code)
        XCTAssertEqual(metaData?.lastUpdated, lastUpdated)
        XCTAssertEqual(metaData?.type, type)
        
        XCTAssertEqual(metaData?.credential.accessKeyId, accessKeyId)
        XCTAssertEqual(metaData?.credential.secretAccessKey, secretAccessKey)
        XCTAssertEqual(metaData?.credential.sessionToken, sessionToken)
    }
    
    func testEC2InstanceMetaDataClientUsingVersion1() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        
        let loop = group.next()
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(loop))
        defer { XCTAssertNoThrow( try httpClient.syncShutdown()) }
        let awsClient = createAWSClient(httpClientProvider: .shared(httpClient))
        defer { XCTAssertNoThrow( try awsClient.syncShutdown()) }
        let testServer = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try testServer.stop()) }
        
        let path = "/" + UUID().uuidString
        Environment.set(path, for: ECSMetaDataClient.RelativeURIEnvironmentName)
        defer { Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName) }
        
        let client = InstanceMetaDataClient(host: "\(testServer.host):\(testServer.serverPort)")
        XCTAssertEqual(client.setup(with: awsClient), true)
        let future = client.getMetaData(on: loop)
        
        XCTAssertNoThrow(try testServer.processRaw { (request) -> AWSTestServer.Result<AWSTestServer.Response> in
            // we try to use version 2, but this endpoint is not available, so we respond with 404
            XCTAssertEqual(request.uri, InstanceMetaDataClient.TokenUri)
            XCTAssertEqual(request.method, .PUT)
            XCTAssertEqual(request.headers[InstanceMetaDataClient.TokenTimeToLiveHeader.name], InstanceMetaDataClient.TokenTimeToLiveHeader.value)
            
            return .result(.init(httpStatus: .notFound), continueProcessing: false)
        })
        
        let roleName = "MySuperDuperAwesomeRoleName"
        XCTAssertNoThrow(try testServer.processRaw { (request) -> AWSTestServer.Result<AWSTestServer.Response> in
            XCTAssertEqual(request.uri, InstanceMetaDataClient.CredentialUri)
            XCTAssertEqual(request.method, .GET)
            XCTAssertNil(request.headers[InstanceMetaDataClient.TokenHeaderName])
            
            var byteBuffer = ByteBufferAllocator().buffer(capacity: roleName.utf8.count)
            byteBuffer.writeString(roleName)
            return .result(.init(httpStatus: .ok, body: byteBuffer), continueProcessing: false)
        })
        
        let accessKeyId = "abc123"
        let secretAccessKey = "123abc"
        let sessionToken = "xyz987"
        let code = "Success"
        let type = "AWS-HMAC"
        let expiration = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded() + 60 * 2)
        let lastUpdated = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded() - 60 * 2)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        XCTAssertNoThrow(try testServer.processRaw { (request) -> AWSTestServer.Result<AWSTestServer.Response> in
            XCTAssertEqual(request.uri, InstanceMetaDataClient.CredentialUri.appending(roleName))
            XCTAssertEqual(request.method, .GET)
            XCTAssertNil(request.headers[InstanceMetaDataClient.TokenHeaderName])
            
            let json = """
                {
                    "AccessKeyId": "\(accessKeyId)",
                    "SecretAccessKey": "\(secretAccessKey)",
                    "Token": "\(sessionToken)",
                    "Expiration": "\(dateFormatter.string(from: expiration))",
                    "Code": "\(code)",
                    "LastUpdated": "\(dateFormatter.string(from: lastUpdated))",
                    "Type": "\(type)"
                }
                """

            var byteBuffer = ByteBufferAllocator().buffer(capacity: json.utf8.count)
            byteBuffer.writeString(json)
            return .result(.init(httpStatus: .ok, body: byteBuffer), continueProcessing: false)
        })
        
        var metaData: InstanceMetaDataClient.MetaData?
        XCTAssertNoThrow(metaData = try future.wait())
        
        XCTAssertEqual(metaData?.accessKeyId, accessKeyId)
        XCTAssertEqual(metaData?.secretAccessKey, secretAccessKey)
        XCTAssertEqual(metaData?.token, sessionToken)
        XCTAssertEqual(metaData?.expiration, expiration)
        XCTAssertEqual(metaData?.code, code)
        XCTAssertEqual(metaData?.lastUpdated, lastUpdated)
        XCTAssertEqual(metaData?.type, type)
        
        XCTAssertEqual(metaData?.credential.accessKeyId, accessKeyId)
        XCTAssertEqual(metaData?.credential.secretAccessKey, secretAccessKey)
        XCTAssertEqual(metaData?.credential.sessionToken, sessionToken)
    }
    
    func testEC2UInstanceMetaDataClientDefaultHost() {
        XCTAssertEqual(InstanceMetaDataClient.Host, "169.254.169.254")
    }
}
