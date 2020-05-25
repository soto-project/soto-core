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
        .target(name: "AWSSDKSwiftCore", dependencies: [
            .byName(name: "AWSSignerV4"),
            .byName(name: "AWSXML"),
            .byName(name: "INIParser"),
            .product(name: "AsyncHTTPClient", package: "async-http-client"),
            .product(name: "Metrics", package: "swift-metrics"),
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
            .product(name: "NIOSSL", package: "swift-nio-ssl"),
            .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
            .product(name: "NIOFoundationCompat", package: "swift-nio"),
        ]),
        .target(name: "AWSCrypto", dependencies: []),
        .target(name: "AWSSignerV4", dependencies: [
            .byName(name: "AWSCrypto"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
        ]),
        .target(name: "AWSTestUtils", dependencies: [
            .byName(name: "AWSSDKSwiftCore"),
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
            .product(name: "NIOFoundationCompat", package: "swift-nio"),
            .product(name: "NIOTestUtils", package: "swift-nio"),
        ]),
        .target(name: "AWSXML", dependencies: []),
        .target(name: "INIParser", dependencies: []),

        .testTarget(name: "AWSCryptoTests", dependencies: [
            .byName(name: "AWSCrypto"),
        ]),
        .testTarget(name: "AWSSDKSwiftCoreTests", dependencies: [
            .byName(name: "AWSSDKSwiftCore"),
            .byName(name: "AWSTestUtils"),
        ]),
        .testTarget(name: "AWSSignerTests", dependencies: [
            .byName(name: "AWSSignerV4"),
        ]),
        .testTarget(name: "AWSXMLTests", dependencies: [
            .byName(name: "AWSXML"),
            .byName(name: "AWSSDKSwiftCore"),
        ]),
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
