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

class ExpiringCredentialTests: XCTestCase {
    func testRotatingCredential() {
        let expiringIn: TimeInterval = 300
        let accessKeyId = "abc123"
        let secretAccessKey = "123abc"
        let sessionToken = "xyz987"
        let expiration = Date(timeIntervalSinceNow: expiringIn)
        let cred = RotatingCredential(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            sessionToken: sessionToken,
            expiration: expiration)
        
        XCTAssertEqual(cred.accessKeyId, accessKeyId)
        XCTAssertEqual(cred.secretAccessKey, secretAccessKey)
        XCTAssertEqual(cred.sessionToken, sessionToken)
        XCTAssertEqual(cred.expiration, expiration)
        
        XCTAssert(cred.isExpiring(within: expiringIn + 1))
        XCTAssert(!cred.isExpiring(within: expiringIn - 1))
        XCTAssert(!cred.isExpired)
        
        /*let neverExpiring = RotatingCredential(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            sessionToken: sessionToken,
            expiration: nil)
        
        XCTAssert(!neverExpiring.isExpiring(within: -5000))
        XCTAssert(!neverExpiring.isExpired)*/
    }
}

