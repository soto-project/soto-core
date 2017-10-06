// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "AWSSDKSwiftCore",
    products: [
        .library(name: "AWSSDKSwiftCore", targets: ["AWSSDKSwiftCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/noppoMan/Prorsum.git", .upToNextMajor(from: "0.1.15")),
        .package(url: "https://github.com/noppoMan/HypertextApplicationLanguage.git", .upToNextMajor(from: "1.0.0"))
    ],
    targets: [
        .target(name: "AWSSDKSwiftCore", dependencies: ["Prorsum", "HypertextApplicationLanguage"]),
        .testTarget(name: "AWSSDKSwiftCoreTests", dependencies: ["AWSSDKSwiftCore"])
    ]
)
