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

// Login Error Tests

import Testing

@testable import SotoCore

@Suite("Login Errors")
struct LoginErrorTests {

    @Test("Error with associated values can be extracted")
    func errorWithAssociatedValues() {
        let profileError = LoginError.profileNotFound("my-profile")
        if case .profileNotFound(let profile) = profileError {
            #expect(profile == "my-profile")
        } else {
            Issue.record("Expected profileNotFound error")
        }

        let tokenError = LoginError.tokenLoadFailed("file not found")
        if case .tokenLoadFailed(let message) = tokenError {
            #expect(message == "file not found")
        } else {
            Issue.record("Expected tokenLoadFailed error")
        }

        let httpError = LoginError.httpRequestFailed("500")
        if case .httpRequestFailed(let status) = httpError {
            #expect(status == "500")
        } else {
            Issue.record("Expected httpRequestFailed error")
        }
    }
}
