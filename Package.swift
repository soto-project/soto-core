// swift-tools-version:4.1
import PackageDescription

let package = Package(
    name: "AWSSDKSwiftCore",
    products: [
        .executable(name: "tester", targets: ["AWSSDKSwiftCore"]),
        .library(name: "AWSSDKSwiftCore", targets: ["AWSSDKSwiftCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "1.5.1"),
        .package(url: "https://github.com/Yasumoto/swift-nio-ssl.git", from: "1.0.2"),
        .package(url: "https://github.com/Yasumoto/HypertextApplicationLanguage.git", .upToNextMajor(from: "1.1.0"))
    ],
    targets: [
        .target(name: "AWSSDKSwiftCore", dependencies: ["HypertextApplicationLanguage", "NIO", "NIOHTTP1", "NIOOpenSSL"]),
        .testTarget(name: "AWSSDKSwiftCoreTests", dependencies: ["AWSSDKSwiftCore"])
    ]
)
