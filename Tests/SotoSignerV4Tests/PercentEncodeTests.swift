//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import SotoSignerV4
import Testing

struct PercentEncodeTests {
    @Test(arguments: [
        ("abc", "abc"),
        ("ABC", "ABC"),
        ("8903", "8903"),
        ("~._-", "~._-"),
        ("!@$%^&*()/", "%21%40%24%25%5E%26%2A%28%29%2F"),
    ])
    func uriEncode(original: String, encoded: String) {
        #expect(original.addingAWSPercentEncoding(forURLComponent: .uriEncode) == encoded)
    }

    @Test(arguments: [
        ("abc", "abc"),
        ("ABC", "ABC"),
        ("8903", "8903"),
        ("~._-", "~._-"),
        ("!@$%^&*()/", "%21%40%24%25%5E%26%2A%28%29/"),
    ])
    func uriPathEncode(original: String, encoded: String) {
        #expect(original.addingAWSPercentEncoding(forURLComponent: .uriEncodePath) == encoded)
    }

    @Test(arguments: [
        ("abc", "abc"),
        ("ABC", "ABC"),
        ("8903", "8903"),
        ("~._-", "~._-"),
        ("!@$%^&*()/", "%21%40%24%25%5E%26%2A%28%29/"),
    ])
    func s3PathEncode(original: String, encoded: String) {
        #expect(original.addingAWSPercentEncoding(forURLComponent: .uriEncodePath) == encoded)
    }
}
