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
@testable import AWSSDKSwiftCore

class CredentialTests: XCTestCase {
    /// Fake parser that returns mocked values and keeps track of calls to parse
    class FakeParser: SharedCredentialsConfigParser {
        var calls: [String] = []
        private let toReturn: [String: [String:String]]
        init(toReturn: [String: [String:String]]) {
            self.toReturn = toReturn
        }
        func parse(filename: String) throws -> [String : [String : String]] {
            calls.append(filename)
            return toReturn
        }
    }

    func testSharedCredentials() {
        // Given
        let profile = "profile1"
        let accessKey = "FAKE-ACCESS-KEY123"
        let secretKey = "Asecretreglkjrd"
        let sessionToken = "xyz"
        let expected = [
            profile: [
                "aws_access_key_id": accessKey,
                "aws_secret_access_key": secretKey,
                "aws_session_token": sessionToken,
            ]
        ]
        let filename = "example/file/path/credentials"
        let parser = FakeParser(toReturn: expected)
        do {
            // When
            let credentials = try SharedCredential(
                filename: filename,
                profile: profile,
                parser: parser
            )
            // Then
            XCTAssertEqual(accessKey, credentials.accessKeyId)
            XCTAssertEqual(secretKey, credentials.secretAccessKey)
            XCTAssertEqual(sessionToken, credentials.sessionToken)
            // Verify called with correct filename
            XCTAssertEqual(filename, parser.calls.first)
        } catch {
            XCTFail("Unexpected failure \(error)")
        }
    }

    func testSharedCredentialsMissingSessionToken() {
        // Given
        let profile = "profile1"
        let accessKey = "FAKE-ACCESS-KEY123"
        let secretKey = "Asecretreglkjrd"
        let expected = [
            profile: [
                "aws_access_key_id": accessKey,
                "aws_secret_access_key": secretKey,
            ]
        ]
        let filename = "example/file/path/credentials"
        let parser = FakeParser(toReturn: expected)
        do {
            // When
            let credentials = try SharedCredential(
                filename: filename,
                profile: profile,
                parser: parser
            )
            // Then
            XCTAssertEqual(accessKey, credentials.accessKeyId)
            XCTAssertEqual(secretKey, credentials.secretAccessKey)
            XCTAssertNil(credentials.sessionToken)
        } catch {
            XCTFail("Unexpected failure \(error)")
        }
    }

    func testSharedCredentialsMissingAccessKey() {
        // Given
        let profile = "profile1"
        let secretKey = "Asecretreglkjrd"
        let expected = [
            profile: [
                "aws_secret_access_key": secretKey,
            ]
        ]
        let filename = "example/file/path/credentials"
        let parser = FakeParser(toReturn: expected)
        do {
            // When
            let _ = try SharedCredential(
                filename: filename,
                profile: profile,
                parser: parser
            )
            XCTFail("Unexpected success")
        } catch let e as SharedCredential.SharedCredentialError {
            XCTAssertEqual(
                SharedCredential.SharedCredentialError.missingAccessKeyId,
                e
            )
        } catch {
            XCTFail("Unexpected failure \(error)")
        }
    }

    func testSharedCredentialsMissingSecretKey() {
        // Given
        let profile = "profile1"
        let accessKey = "FAKE-ACCESS-KEY123"
        let expected = [
            profile: [
                "aws_access_key_id": accessKey,
            ]
        ]
        let filename = "example/file/path/credentials"
        let parser = FakeParser(toReturn: expected)
        do {
            // When
            let _ = try SharedCredential(
                filename: filename,
                profile: profile,
                parser: parser
            )
            XCTFail("Unexpected success")
        } catch let e as SharedCredential.SharedCredentialError {
            XCTAssertEqual(
                SharedCredential.SharedCredentialError.missingSecretAccessKey,
                e
            )
        } catch {
            XCTFail("Unexpected failure \(error)")
        }
    }

    func testSharedCredentialsMissingProfile() {
        // Given
        let profile = "profile1"
        let accessKey = "FAKE-ACCESS-KEY123"
        let expected = [
            // Different profile
            "profile2": [
                "aws_access_key_id": accessKey,
            ]
        ]
        let filename = "example/file/path/credentials"
        let parser = FakeParser(toReturn: expected)
        do {
            // When
            let _ = try SharedCredential(
                filename: filename,
                profile: profile,
                parser: parser
            )
            XCTFail("Unexpected success")
        } catch let e as SharedCredential.SharedCredentialError {
            XCTAssertEqual(
                SharedCredential.SharedCredentialError.missingProfile(profile),
                e
            )
        } catch {
            XCTFail("Unexpected failure \(error)")
        }
    }

    func testSharedCredentialsParseFailure() {
        // Given
        enum FakeError: Error, Equatable {
            case test
        }
        class ErrorParser: SharedCredentialsConfigParser {
            func parse(filename: String) throws -> [String : [String : String]] {
                throw FakeError.test
            }
        }
        let parser = ErrorParser()
        do {
            // When
            let _ = try SharedCredential(
                filename: "x",
                profile: "y",
                parser: parser
            )
            XCTFail("Unexpected success")
        } catch let e as FakeError {
            XCTAssertEqual(
                FakeError.test,
                e
            )
        } catch {
            XCTFail("Unexpected failure \(error)")
        }
    }

    func testExpiringCredential() {
        let credential: Credential = ExpiringCredential(accessKeyId: "", secretAccessKey: "", expiration: Date.init(timeIntervalSince1970: 0))
        guard let ecredential = credential as? ExpiringCredential else {XCTFail(); return }
        XCTAssertEqual(ecredential.nearExpiration(), true)

        let credential2: Credential = ExpiringCredential(accessKeyId: "", secretAccessKey: "", expiration: Date(timeIntervalSinceNow: 3600))
        guard let ecredential2 = credential2 as? ExpiringCredential else {XCTFail(); return }
        XCTAssertEqual(ecredential2.nearExpiration(), false)
    }
    
    static var allTests : [(String, (CredentialTests) -> () throws -> Void)] {
        return [
            ("testSharedCredentials", testSharedCredentials),
            ("testSharedCredentialsMissingSessionToken", testSharedCredentialsMissingSessionToken),
            ("testSharedCredentialsMissingAccessKey", testSharedCredentialsMissingAccessKey),
            ("testSharedCredentialsMissingSecretKey", testSharedCredentialsMissingSecretKey),
            ("testSharedCredentialsMissingProfile", testSharedCredentialsMissingProfile),
            ("testSharedCredentialsParseFailure", testSharedCredentialsParseFailure),
            ("testExpiringCredential", testExpiringCredential),
        ]
    }
}
