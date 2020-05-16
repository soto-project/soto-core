// swift-tools-version:5.1
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

import PackageDescription

let package = Package(
    name: "aws-sdk-swift-core",
    products: [
        .library(name: "AWSSDKSwiftCore", targets: ["AWSSDKSwiftCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-metrics.git", "1.0.0" ..< "3.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", .upToNextMajor(from:"2.16.1")),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", .upToNextMajor(from:"2.7.2")),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", .upToNextMajor(from:"1.0.0")),
        .package(url: "https://github.com/swift-server/async-http-client.git", .upToNextMajor(from:"1.0.0"))
    ],
    targets: [
        .target(
            name: "AWSSDKSwiftCore",
            dependencies: [
                "AsyncHTTPClient",
                "AWSSignerV4",
                "Metrics",
                "NIO",
                "NIOHTTP1",
                "NIOSSL",
                "NIOTransportServices",
                "NIOFoundationCompat",
                "INIParser"
            ]),
        .target(name: "AWSSignerV4", dependencies: ["AWSCrypto", "NIOHTTP1"]),
        .target(name: "INIParser", dependencies: []),
        .target(name: "AWSCrypto", dependencies: []),

        .testTarget(name: "AWSCryptoTests", dependencies: ["AWSCrypto"]),
        .testTarget(name: "AWSSDKSwiftCoreTests", dependencies: ["AWSSDKSwiftCore", "NIOTestUtils"]),
        .testTarget(name: "AWSSignerTests", dependencies: ["AWSSignerV4"])
    ]
)

// switch for whether to use swift crypto. Swift crypto requires macOS10.15 or iOS13.I'd rather not pass this requirement on
#if os(Linux)
let useSwiftCrypto = true
#else
let useSwiftCrypto = false
#endif

// Use Swift cypto on Linux.
if useSwiftCrypto {
    package.dependencies.append(.package(url: "https://github.com/apple/swift-crypto.git", from: "1.0.0"))
    package.targets.first{$0.name == "AWSCrypto"}?.dependencies.append("Crypto")
}
