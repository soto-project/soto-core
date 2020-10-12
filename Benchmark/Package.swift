// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "soto-benchmark",
    dependencies: [
        .package(url: "https://github.com/soto-project/soto-core", .branch("main")),
        .package(name: "Benchmark", url: "https://github.com/google/swift-benchmark", .branch("master")),
    ],
    targets: [
        .target(name: "soto-benchmark", dependencies: [
            .product(name: "SotoCore", package: "soto-core"),
            .product(name: "Benchmark", package: "Benchmark"),
        ]),
    ]
)
