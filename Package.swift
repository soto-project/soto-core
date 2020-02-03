// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "AWSSDKSwiftCore",
    platforms: [.macOS(.v10_15), .iOS(.v13), .watchOS(.v6), .tvOS(.v13)],
    products: [
        .library(name: "AWSSDKSwiftCore", targets: ["AWSSDKSwiftCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMajor(from:"1.0.0")),
        .package(url: "https://github.com/apple/swift-nio.git", .upToNextMajor(from:"2.11.0")),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", .upToNextMajor(from:"2.4.0")),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", .upToNextMajor(from:"1.0.0")),
        .package(url: "https://github.com/swift-server/async-http-client.git", .upToNextMajor(from:"1.0.0")),
        .package(url: "https://github.com/swift-aws/HypertextApplicationLanguage.git", .upToNextMinor(from: "1.1.0")),
        .package(url: "https://github.com/swift-aws/Perfect-INIParser.git", .upToNextMinor(from: "3.0.0")),
    ],
    targets: [
        .target(
            name: "AWSSDKSwiftCore",
            dependencies: [
                "AsyncHTTPClient",
                "AWSSignerV4",
                "HypertextApplicationLanguage",
                "NIO",
                "NIOHTTP1",
                "NIOSSL",
                "NIOTransportServices",
                "NIOFoundationCompat",
                "INIParser"
            ]),
        .target(name: "AWSSignerV4", dependencies: ["Crypto", "NIOHTTP1"]),

        .testTarget(name: "AWSSDKSwiftCoreTests", dependencies: ["AWSSDKSwiftCore", "NIOTestUtils"]),
        .testTarget(name: "AWSSignerTests", dependencies: ["AWSSignerV4"])
    ]
)

