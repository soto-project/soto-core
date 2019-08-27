// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "AWSSDKSwiftCore",
    products: [
        .library(name: "AWSSDKSwiftCore", targets: ["AWSSDKSwiftCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", .upToNextMajor(from:"2.1.0")),
        .package(url: "https://github.com/apple/swift-nio-ssl-support.git", from: "1.0.0"),
        .package(url: "https://github.com/Yasumoto/HypertextApplicationLanguage.git", .upToNextMajor(from: "1.1.0")),
        .package(url: "https://github.com/PerfectlySoft/Perfect-INIParser.git", .upToNextMajor(from: "3.0.0")),
    ],
    targets: [
        .target(
            name: "AWSSDKSwiftCore",
            dependencies: [
                "CAWSSDKOpenSSL",
                "HypertextApplicationLanguage",
                "NIO",
                "NIOHTTP1",
                "NIOFoundationCompat",
                "INIParser"
            ]),
        .target(name: "CAWSSDKOpenSSL"),
        .testTarget(name: "AWSSDKSwiftCoreTests", dependencies: ["AWSSDKSwiftCore"])
    ]
)

// switch for moving from NIOSSL to NIOTransportServices
let useNIOTransportServices = false
let awsSdkSwiftCoreTarget = package.targets.first(where: {$0.name == "AWSSDKSwiftCore"})

if useNIOTransportServices {
    package.platforms = [ .iOS(.v12), .macOS(.v10_14), .tvOS(.v12) ]
    package.dependencies.append(.package(url: "https://github.com/apple/swift-nio-transport-services.git", .upToNextMajor(from:"1.0.0")))
    awsSdkSwiftCoreTarget?.dependencies.append("NIOTransportServices")
} else {
    package.dependencies.append(.package(url: "https://github.com/apple/swift-nio-ssl.git", .upToNextMajor(from:"2.0.0")))
    awsSdkSwiftCoreTarget?.dependencies.append("NIOSSL")
}
