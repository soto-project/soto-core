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
#if os(Linux)
import Glibc
#else
import Darwin
#endif
import AWSTestUtils
@testable import AWSSDKSwiftCore

extension Environment {
    
    static func set(_ value: String, for name: String) {
        guard 0 == setenv(name, value, 1) else {
            XCTFail()
            return
        }
    }
    
    static func unset(name: String) {
        XCTAssertEqual(unsetenv(name), 0)
    }
    
}

class EnvironmentCredentialProviderTests: XCTestCase {
    
    override func tearDown() {
        Environment.unset(name: "AWS_ACCESS_KEY_ID")
        Environment.unset(name: "AWS_SECRET_ACCESS_KEY")
        Environment.unset(name: "AWS_SESSION_TOKEN")
    }
    
    func testSuccess() throws {
        let accessKeyId = "AWSACCESSKEYID"
        let secretAccessKet = "AWSSECRETACCESSKEY"
        let sessionToken = "AWSSESSIONTOKEN"
        
        Environment.set(accessKeyId, for: "AWS_ACCESS_KEY_ID")
        Environment.set(secretAccessKet, for: "AWS_SECRET_ACCESS_KEY")
        Environment.set(sessionToken, for: "AWS_SESSION_TOKEN")
        
        let client = createAWSClient(credentialProvider: EnvironmentCredentialProvider())
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        
        let credential = try XCTUnwrap(client.credentialProvider as? StaticCredential)
        XCTAssertEqual(credential.accessKeyId, accessKeyId)
        XCTAssertEqual(credential.secretAccessKey, secretAccessKet)
        XCTAssertEqual(credential.sessionToken, sessionToken)
    }
    
    func testFailWithoutAccessKeyId() {
        let secretAccessKet = "AWSSECRETACCESSKEY"
        let sessionToken = "AWSSESSIONTOKEN"
        
        Environment.set(secretAccessKet, for: "AWS_SECRET_ACCESS_KEY")
        Environment.set(sessionToken, for: "AWS_SESSION_TOKEN")
        
        let client = createAWSClient(credentialProvider: EnvironmentCredentialProvider())
        defer { XCTAssertNoThrow(try client.syncShutdown()) }

        XCTAssert(client.credentialProvider is NullCredentialProvider)
    }
    
    func testFailWithoutSecretAccessKey() {
        let accessKeyId = "AWSACCESSKEYID"
        let sessionToken = "AWSSESSIONTOKEN"
        
        Environment.set(accessKeyId, for: "AWS_ACCESS_KEY_ID")
        Environment.set(sessionToken, for: "AWS_SESSION_TOKEN")
        
        let client = createAWSClient(credentialProvider: EnvironmentCredentialProvider())
        defer { XCTAssertNoThrow(try client.syncShutdown()) }

        XCTAssert(client.credentialProvider is NullCredentialProvider)
    }
    
    func testSuccessWithoutSessionToken() throws {
        let accessKeyId = "AWSACCESSKEYID"
        let secretAccessKet = "AWSSECRETACCESSKEY"
        
        Environment.set(accessKeyId, for: "AWS_ACCESS_KEY_ID")
        Environment.set(secretAccessKet, for: "AWS_SECRET_ACCESS_KEY")
        
        let client = createAWSClient(credentialProvider: EnvironmentCredentialProvider())
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        
        let credential = try XCTUnwrap(client.credentialProvider as? StaticCredential)
        XCTAssertEqual(credential.accessKeyId, accessKeyId)
        XCTAssertEqual(credential.secretAccessKey, secretAccessKet)
        XCTAssertNil(credential.sessionToken)
    }
}
