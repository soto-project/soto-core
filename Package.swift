// swift-tools-version:4.1
import PackageDescription

let package = Package(
    name: "AWSSDKSwiftCore",
    products: [
        .library(name: "AWSSDKSwiftCore", targets: ["AWSSDKSwiftCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "1.8.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "1.1.0"),
        .package(url: "https://github.com/Yasumoto/HypertextApplicationLanguage.git", .upToNextMajor(from: "1.1.0"))
    ],
    targets: [
        .target(name: "AWSSDKSwiftCore", dependencies: ["HypertextApplicationLanguage", "NIO", "NIOHTTP1", "NIOOpenSSL"]),
        .testTarget(name: "AWSSDKSwiftCoreTests", dependencies: ["AWSSDKSwiftCore"])
    ]
)
