//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
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
@testable import SotoCore

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
    func testSuccess() async throws {
        let accessKeyId = "AWSACCESSKEYID"
        let secretAccessKet = "AWSSECRETACCESSKEY"
        let sessionToken = "AWSSESSIONTOKEN"

        Environment.set(accessKeyId, for: "AWS_ACCESS_KEY_ID")
        Environment.set(secretAccessKet, for: "AWS_SECRET_ACCESS_KEY")
        Environment.set(sessionToken, for: "AWS_SESSION_TOKEN")
        defer {
            Environment.unset(name: "AWS_ACCESS_KEY_ID")
            Environment.unset(name: "AWS_SECRET_ACCESS_KEY")
            Environment.unset(name: "AWS_SESSION_TOKEN")
        }

        let staticCredentials = StaticCredential.fromEnvironment()
        let cred = try await staticCredentials?.getCredential(logger: .init(label: #function))

        XCTAssertEqual(cred?.accessKeyId, accessKeyId)
        XCTAssertEqual(cred?.secretAccessKey, secretAccessKet)
        XCTAssertEqual(cred?.sessionToken, sessionToken)
    }

    func testFailWithoutAccessKeyId() {
        let secretAccessKet = "AWSSECRETACCESSKEY"
        let sessionToken = "AWSSESSIONTOKEN"

        Environment.set(secretAccessKet, for: "AWS_SECRET_ACCESS_KEY")
        Environment.set(sessionToken, for: "AWS_SESSION_TOKEN")
        defer {
            Environment.unset(name: "AWS_ACCESS_KEY_ID")
            Environment.unset(name: "AWS_SECRET_ACCESS_KEY")
        }

        let cred = StaticCredential.fromEnvironment()

        XCTAssertNil(cred)
    }

    func testFailWithoutSecretAccessKey() {
        let accessKeyId = "AWSACCESSKEYID"
        let sessionToken = "AWSSESSIONTOKEN"

        Environment.set(accessKeyId, for: "AWS_ACCESS_KEY_ID")
        Environment.set(sessionToken, for: "AWS_SESSION_TOKEN")
        defer {
            Environment.unset(name: "AWS_ACCESS_KEY_ID")
            Environment.unset(name: "AWS_SECRET_ACCESS_KEY")
        }

        let cred = StaticCredential.fromEnvironment()

        XCTAssertNil(cred)
    }

    func testSuccessWithoutSessionToken() async throws {
        let accessKeyId = "AWSACCESSKEYID"
        let secretAccessKet = "AWSSECRETACCESSKEY"

        Environment.set(accessKeyId, for: "AWS_ACCESS_KEY_ID")
        Environment.set(secretAccessKet, for: "AWS_SECRET_ACCESS_KEY")
        defer {
            Environment.unset(name: "AWS_ACCESS_KEY_ID")
            Environment.unset(name: "AWS_SECRET_ACCESS_KEY")
        }

        let staticCredentials = StaticCredential.fromEnvironment()
        let cred = try await staticCredentials?.getCredential(logger: .init(label: #function))

        XCTAssertEqual(cred?.accessKeyId, accessKeyId)
        XCTAssertEqual(cred?.secretAccessKey, secretAccessKet)
        XCTAssertNil(cred?.sessionToken)
    }
}
