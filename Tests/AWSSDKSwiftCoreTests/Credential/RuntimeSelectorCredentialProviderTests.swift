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
import AWSTestUtils
import NIO
@testable import AWSSDKSwiftCore

class RuntimeSelectorCredentialProviderTests: XCTestCase {
    
    func testSetupFail() {
        let client = createAWSClient(credentialProvider: .selector(.custom {_ in return NullCredentialProvider()} ))
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let futureResult = client.credentialProvider.getCredential(on: client.eventLoopGroup.next())
        XCTAssertThrowsError(try futureResult.wait()) { error in
            switch error {
            case let error as CredentialProviderError where error == CredentialProviderError.noProvider:
                break
            default:
                XCTFail()
            }
        }

    }
    
    func testFoundEnvironmentProvider() throws {
        let accessKeyId = "AWSACCESSKEYID"
        let secretAccessKey = "AWSSECRETACCESSKEY"
        let sessionToken = "AWSSESSIONTOKEN"
        
        Environment.set(accessKeyId, for: "AWS_ACCESS_KEY_ID")
        Environment.set(secretAccessKey, for: "AWS_SECRET_ACCESS_KEY")
        Environment.set(sessionToken, for: "AWS_SESSION_TOKEN")

        let client = createAWSClient(credentialProvider: .selector(.environment, .empty))
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let futureResult = client.credentialProvider.getCredential(on: client.eventLoopGroup.next()).flatMapThrowing { credential in
            XCTAssertEqual(credential.accessKeyId, accessKeyId)
            XCTAssertEqual(credential.secretAccessKey, secretAccessKey)
            XCTAssertEqual(credential.sessionToken, sessionToken)
            let internalProvider = try XCTUnwrap((client.credentialProvider as? RuntimeSelectorCredentialProvider)?.internalProvider)
            XCTAssert(internalProvider is StaticCredential)
        }
        XCTAssertNoThrow(try futureResult.wait())
        
        Environment.unset(name: "AWS_ACCESS_KEY_ID")
        Environment.unset(name: "AWS_SECRET_ACCESS_KEY")
        Environment.unset(name: "AWS_SESSION_TOKEN")
    }
    
    func testEnvironmentProviderFail() throws {
        Environment.unset(name: "AWS_ACCESS_KEY_ID")

        let provider: CredentialProviderFactory = .selector(.environment)
        let client = createAWSClient(credentialProvider: provider)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let futureResult = client.credentialProvider.getCredential(on: client.eventLoopGroup.next())
        XCTAssertThrowsError(try futureResult.wait()) { error in
            switch error {
            case let error as CredentialProviderError where error == CredentialProviderError.noProvider:
                break
            default:
                XCTFail()
            }
        }
    }
    
    func testFoundEmptyProvider() throws {
        let provider: CredentialProviderFactory = .selector(.empty, .environment)
        let client = createAWSClient(credentialProvider: provider)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let futureResult = client.credentialProvider.getCredential(on: client.eventLoopGroup.next()).flatMapThrowing { credential in
            XCTAssertEqual(credential.accessKeyId, "")
            XCTAssertEqual(credential.secretAccessKey, "")
            XCTAssertEqual(credential.sessionToken, nil)
            let internalProvider = try XCTUnwrap((client.credentialProvider as? RuntimeSelectorCredentialProvider)?.internalProvider)
            XCTAssert(internalProvider is StaticCredential)
        }
        XCTAssertNoThrow(try futureResult.wait())
    }
    
    func testFoundSelectorWithOneProvider() throws {
        let provider: CredentialProviderFactory = .selector(.empty)
        let client = createAWSClient(credentialProvider: provider)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let futureResult = client.credentialProvider.getCredential(on: client.eventLoopGroup.next()).flatMapThrowing { credential in
            XCTAssert(credential.isEmpty())
            XCTAssert(client.credentialProvider is StaticCredential)
        }
        XCTAssertNoThrow(try futureResult.wait())
    }
    
    func testECSProvider() {
        Environment.unset(name: "AWS_ACCESS_KEY_ID")

        let testServer = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try testServer.stop()) }
        let path = "/" + UUID().uuidString
        Environment.set(path, for: ECSMetaDataClient.RelativeURIEnvironmentName)
        defer { Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName) }

        let customECS: CredentialProviderFactory = .custom { context in 
            if let client = ECSMetaDataClient(httpClient: context.httpClient, host: "\(testServer.host):\(testServer.serverPort)") {
                return RotatingCredentialProvider(eventLoop: context.eventLoop, provider: client)
            }
            // fallback
            return NullCredentialProvider()
        }
        let provider: CredentialProviderFactory = .selector(.environment, customECS, .empty)
        let client = createAWSClient(credentialProvider: provider)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }

        let accessKeyId = "abc123"
        let secretAccessKey = "123abc"
        let sessionToken = "xyz987"
        let expiration = Date(timeIntervalSinceNow: 5*60*60)
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        let roleArn = "asd:aws:asd"
        
        XCTAssertNoThrow(try testServer.processRaw { request in
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

        let futureResult = client.credentialProvider.getCredential(on: client.eventLoopGroup.next()).flatMapThrowing { credential in
            XCTAssertEqual(credential.accessKeyId, accessKeyId)
            XCTAssertEqual(credential.secretAccessKey, secretAccessKey)
            XCTAssertEqual(credential.sessionToken, sessionToken)
            let internalProvider = try XCTUnwrap((client.credentialProvider as? RuntimeSelectorCredentialProvider)?.internalProvider)
            XCTAssert(internalProvider is RotatingCredentialProvider)
        }
        XCTAssertNoThrow(try futureResult.wait())
    }
    
    func testECSProviderFail() {
        Environment.unset(name: "AWS_ACCESS_KEY_ID")
        Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName)
        
        let provider: CredentialProviderFactory = .selector(.ecs)
        let client = createAWSClient(credentialProvider: provider)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let futureResult = client.credentialProvider.getCredential(on: client.eventLoopGroup.next())
        XCTAssertThrowsError(try futureResult.wait()) { error in
            switch error {
            case let error as CredentialProviderError where error == CredentialProviderError.noProvider:
                break
            default:
                XCTFail()
            }
        }
    }
    
    func testConfigFileProvider() {
        let credentials = """
            [default]
            aws_access_key_id = AWSACCESSKEYID
            aws_secret_access_key = AWSSECRETACCESSKEY
            """
        let filename = "credentials"
        let filenameURL = URL(fileURLWithPath: filename)
        XCTAssertNoThrow(try Data(credentials.utf8).write(to: filenameURL))
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: filenameURL)) }

        let client = createAWSClient(credentialProvider: .selector(.configFile(credentialsFilePath: filename), .empty))
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let futureResult = client.credentialProvider.getCredential(on: client.eventLoopGroup.next()).flatMapThrowing { credential in
            XCTAssertEqual(credential.accessKeyId, "AWSACCESSKEYID")
            XCTAssertEqual(credential.secretAccessKey, "AWSSECRETACCESSKEY")
            XCTAssertEqual(credential.sessionToken, nil)
            let internalProvider = try XCTUnwrap((client.credentialProvider as? RuntimeSelectorCredentialProvider)?.internalProvider)
            XCTAssert(internalProvider is DeferredCredentialProvider)
        }
        XCTAssertNoThrow(try futureResult.wait())
    }
    
    func testConfigFileProviderFail() {
        let client = createAWSClient(credentialProvider: .selector(.configFile(credentialsFilePath: "nonExistentCredentialFile"), .empty))
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let futureResult = client.credentialProvider.getCredential(on: client.eventLoopGroup.next()).flatMapThrowing { credential in
            let internalProvider = try XCTUnwrap((client.credentialProvider as? RuntimeSelectorCredentialProvider)?.internalProvider)
            XCTAssert(internalProvider is StaticCredential)
            XCTAssert((internalProvider as? StaticCredential)?.isEmpty() == true)
        }
        XCTAssertNoThrow(try futureResult.wait())
    }
    
}
