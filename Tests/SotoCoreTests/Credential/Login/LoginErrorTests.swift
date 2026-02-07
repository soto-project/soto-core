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

@Suite("AWS Login Credential Errors")
struct AWSLoginCredentialErrorTests {

    @Test("Error codes and messages are accessible")
    func errorCodesAndMessages() {
        let profileError = AWSLoginCredentialError.profileNotFound("my-profile")
        #expect(profileError.code == "profileNotFound")
        #expect(profileError.message.contains("my-profile"))

        let tokenError = AWSLoginCredentialError.tokenLoadFailed("file not found")
        #expect(tokenError.code == "tokenLoadFailed")
        #expect(tokenError.message == "file not found")

        let httpError = AWSLoginCredentialError.httpRequestFailed("500")
        #expect(httpError.code == "httpRequestFailed")
        #expect(httpError.message == "500")
    }
    
    @Test("Errors are equatable")
    func errorsAreEquatable() {
        let error1 = AWSLoginCredentialError.profileNotFound("test")
        let error2 = AWSLoginCredentialError.profileNotFound("test")
        let error3 = AWSLoginCredentialError.profileNotFound("other")
        
        #expect(error1 == error2)
        #expect(error1 != error3)
    }
    
    @Test("Error description includes code and message")
    func errorDescription() {
        let error = AWSLoginCredentialError.tokenLoadFailed("test message")
        #expect(error.description == "tokenLoadFailed: test message")
    }
}
