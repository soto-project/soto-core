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

// Profile Configuration Loader Tests

import Foundation
import SotoCore
import Testing

@testable import SotoCore

@Suite("Profile Configuration Loader")
struct ProfileConfigurationLoaderTests {

    @Test("Load configuration with missing profile throws error")
    func loadConfigurationMissingProfile() {
        let loader = ProfileConfigurationLoader()

        // Trying to load a non-existent profile should throw
        #expect(throws: LoginError.self) {
            try loader.loadConfiguration(
                profileName: "nonexistent-profile-12345",
                cacheDirectoryOverride: nil
            )
        }
    }

    @Test(
        "Endpoint construction for various regions",
        arguments: [
            (Region.useast1, "us-east-1.signin.aws.amazon.com"),
            (Region.euwest1, "eu-west-1.signin.aws.amazon.com"),
            (Region.apsoutheast2, "ap-southeast-2.signin.aws.amazon.com"),
        ]
    )
    func endpointConstruction(region: Region, expectedEndpoint: String) throws {
        // Test endpoint construction directly
        let endpoint = "\(region.rawValue).\(LoginConfiguration.loginServiceHostPrefix).aws.amazon.com"
        #expect(endpoint == expectedEndpoint)
    }
}
