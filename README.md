# aws-sdk-swift-core

A Core Framework for [AWSSDKSwift](https://github.com/swift-aws/aws-sdk-swift)

This is the underlying driver for executing requests to AWS, but you should likely use one of the libraries provided by the package above instead of this!

## Example Package.swift

```swift
// swift-tools-version:4.1
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription

let package = Package(
    name: "MyAWSTool",
    dependencies: [
        .package(url: "https://github.com/swift-aws/aws-sdk-swift", .upToNextMajor(from: "2.0.0")),
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
