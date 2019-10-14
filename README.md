# aws-sdk-swift-core

[<img src="http://img.shields.io/badge/swift-5.0-brightgreen.svg" alt="Swift 5.0" />](https://swift.org)
[<img src="https://travis-ci.org/swift-aws/aws-sdk-swift-core.svg?branch=master" alt="Travis Build" />](https://travis-ci.org/swift-aws/aws-sdk-swift-core)
[<img src="https://codecov.io/gh/swift-aws/aws-sdk-swift-core/branch/master/graph/badge.svg" alt="Codecov Result" />](https://codecov.io/gh/swift-aws/aws-sdk-swift-core)

A Core Framework for [AWSSDKSwift](https://github.com/swift-aws/aws-sdk-swift)

This is the underlying driver for executing requests to AWS, but you should likely use one of the libraries provided by the package above instead of this! Documentation can be found [here](http://htmlpreview.github.io/?https://github.com/swift-aws/aws-sdk-swift-core/gh-pages/docs/current/index.html).

## Swift NIO

This client utilizes [Swift NIO](https://github.com/apple/swift-nio#conceptual-overview) to power its interactions with AWS. It returns an [`EventLoopFuture`](https://apple.github.io/swift-nio/docs/current/NIO/Classes/EventLoopFuture.html) in order to allow non-blocking frameworks to use this code. Please see the Swift NIO documentation for more details, and please let us know via an Issue if you have questions!

## Compatibility

Versions 4.x of aws-sdk-swift-core are dependent on swift-nio 2, this means certain libraries/frameworks that are dependent on an earlier version of swift-nio will not work with version 4 of aws-sdk-swift-core. Version 3.x of the aws-sdk-swift-core can be used if you need to use an earlier version of swift-nio. For instance Vapor 3 uses swift-nio 1.13 so you can only use versions 3.x of aws-sdk-swift-core with Vapor 3. Below is a compatibility table for versions 3 and 4 of aws-sdk-swift-core.

|      | Swift   | MacOS | Linux              | Vapor |
|------|---------|-------|--------------------|-------|
| v3.x | 4.2-5.1 | ✓     | Ubuntu 14.04-18.04 | v3    |
| v4.x | 5.0-5.1 | ✓     | Ubuntu 14.04-18.04 | v4    |

## Example Package.swift

```swift
// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "MyAWSTool",
    dependencies: [
        .package(url: "https://github.com/swift-aws/aws-sdk-swift", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "MyAWSTool",
            dependencies: ["CloudFront", "ELB", "ELBV2",  "IAM"]),
        .testTarget(
            name: "MyAWSToolTests",
            dependencies: ["MyAWSTool"]),
    ]
)
```

## License

`aws-sdk-swift-core` is released under the MIT license. See LICENSE for details.
