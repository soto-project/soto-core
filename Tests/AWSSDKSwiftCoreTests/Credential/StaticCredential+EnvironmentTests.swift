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
@testable import AWSSDKSwiftCore

extension Environment {
    static func set(_ value: String, for name: String) {
        guard setenv(name, value, 1) == 0 else {
            XCTFail()
            return
        }
    }

    static func unset(name: String) {
        XCTAssertEqual(unsetenv(name), 0)
    }
}

class StaticCredential_EnvironmentTests: XCTestCase {
    override func tearDown() {
        Environment.unset(name: "AWS_ACCESS_KEY_ID")
        Environment.unset(name: "AWS_SECRET_ACCESS_KEY")
        Environment.unset(name: "AWS_SESSION_TOKEN")
    }

    func testSuccess() {
        let accessKeyId = "AWSACCESSKEYID"
        let secretAccessKet = "AWSSECRETACCESSKEY"
        let sessionToken = "AWSSESSIONTOKEN"

        Environment.set(accessKeyId, for: "AWS_ACCESS_KEY_ID")
        Environment.set(secretAccessKet, for: "AWS_SECRET_ACCESS_KEY")
        Environment.set(sessionToken, for: "AWS_SESSION_TOKEN")

        let cred = StaticCredential.fromEnvironment()

        XCTAssertEqual(cred?.accessKeyId, accessKeyId)
        XCTAssertEqual(cred?.secretAccessKey, secretAccessKet)
        XCTAssertEqual(cred?.sessionToken, sessionToken)
    }

    func testFailWithoutAccessKeyId() {
        let secretAccessKet = "AWSSECRETACCESSKEY"
        let sessionToken = "AWSSESSIONTOKEN"

        Environment.set(secretAccessKet, for: "AWS_SECRET_ACCESS_KEY")
        Environment.set(sessionToken, for: "AWS_SESSION_TOKEN")

        let cred = StaticCredential.fromEnvironment()

        XCTAssertNil(cred)
    }

    func testFailWithoutSecretAccessKey() {
        let accessKeyId = "AWSACCESSKEYID"
        let sessionToken = "AWSSESSIONTOKEN"

        Environment.set(accessKeyId, for: "AWS_ACCESS_KEY_ID")
        Environment.set(sessionToken, for: "AWS_SESSION_TOKEN")

        let cred = StaticCredential.fromEnvironment()

        XCTAssertNil(cred)
    }

    func testSuccessWithoutSessionToken() {
        let accessKeyId = "AWSACCESSKEYID"
        let secretAccessKet = "AWSSECRETACCESSKEY"

        Environment.set(accessKeyId, for: "AWS_ACCESS_KEY_ID")
        Environment.set(secretAccessKet, for: "AWS_SECRET_ACCESS_KEY")

        let cred = StaticCredential.fromEnvironment()

        XCTAssertEqual(cred?.accessKeyId, accessKeyId)
        XCTAssertEqual(cred?.secretAccessKey, secretAccessKet)
        XCTAssertNil(cred?.sessionToken)
    }
}
