// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "AWSSDKSwiftCore",
    platforms: [.iOS(.v12), .tvOS(.v12), .watchOS(.v5)],
    products: [
        .library(name: "AWSSDKSwiftCore", targets: ["AWSSDKSwiftCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", .upToNextMajor(from:"2.8.0")),
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
                "AWSSigner",
                "CAWSSDKOpenSSL",
                "HypertextApplicationLanguage",
                "NIO",
                "NIOHTTP1",
                "NIOSSL",
                "NIOTransportServices",
                "NIOFoundationCompat",
                "INIParser"
            ]),
        .target(name: "AWSSigner", dependencies: ["CAWSSDKOpenSSL", "NIOHTTP1"]),
        .target(name: "CAWSSDKOpenSSL", dependencies: []),
        .testTarget(name: "AWSSDKSwiftCoreTests", dependencies: ["AWSSDKSwiftCore"]),
        .testTarget(name: "AWSSignerTests", dependencies: ["AWSSigner"])
    ]
)

// switch for whether to use CAWSSDKOpenSSL to shim between OpenSSL versions
#if os(Linux)
let useOpenSSL = true
#else
let useOpenSSL = false
#endif

// Decide on where we get our SSL support from. Linux usses NIOSSL to provide SSL. Linux also needs CAWSSDKOpenSSL to shim across different OpenSSL versions for the HMAC functions.
if useOpenSSL {
    package.dependencies.append(.package(url: "https://github.com/apple/swift-nio-ssl-support.git", from: "1.0.0"))
}
