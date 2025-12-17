// swift-tools-version:6.1
//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency=complete"),
    .enableExperimentalFeature("AccessLevelOnImport"),
]

let package = Package(
    name: "soto-core",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(name: "SotoCore", targets: ["SotoCore"]),
        .library(name: "SotoTestUtils", targets: ["SotoTestUtils"]),
        .library(name: "SotoSignerV4", targets: ["SotoSignerV4"]),
    ],
    traits: [
        "ServiceLifecycleSupport",
        .default(
            enabledTraits: [
                "ServiceLifecycleSupport"
            ]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.77.0"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0"..<"5.0.0"),
        .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-metrics.git", "1.0.0"..<"3.0.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.7.2"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.13.1"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.30.0"),
        .package(url: "https://github.com/jmespath/jmespath.swift.git", from: "1.0.2"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.8.0"),
    ],
    targets: [
        .target(
            name: "SotoCore",
            dependencies: [
                .byName(name: "SotoSignerV4"),
                .byName(name: "SotoXML"),
                .byName(name: "INIParser"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "Metrics", package: "swift-metrics"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "_NIOFileSystem", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "JMESPath", package: "jmespath.swift"),
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(
                    name: "ServiceLifecycle",
                    package: "swift-service-lifecycle",
                    condition: .when(traits: ["ServiceLifecycleSupport"])
                ),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SotoSignerV4",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SotoTestUtils",
            dependencies: [
                .byName(name: "SotoCore"),
                .byName(name: "SotoXML"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOTestUtils", package: "swift-nio"),
            ]
        ),
        .target(
            name: "SotoXML",
            dependencies: [
                .byName(name: "CSotoExpat")
            ],
            swiftSettings: swiftSettings
        ),
        .target(name: "CSotoExpat", dependencies: []),
        .target(
            name: "INIParser",
            dependencies: [],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SotoCoreTests",
            dependencies: [
                .byName(name: "SotoCore"),
                .byName(name: "SotoTestUtils"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "InMemoryTracing", package: "swift-distributed-tracing"),
            ]
        ),
        .testTarget(
            name: "SotoSignerV4Tests",
            dependencies: [
                .byName(name: "SotoSignerV4")
            ]
        ),
        .testTarget(
            name: "SotoXMLTests",
            dependencies: [
                .byName(name: "SotoXML"),
                .byName(name: "SotoCore"),
            ]
        ),
        .testTarget(
            name: "INIParserTests",
            dependencies: [
                .byName(name: "INIParser")
            ]
        ),
    ]
)
