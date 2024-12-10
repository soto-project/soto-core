#!/usr/bin/env swift sh
//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient // swift-server/async-http-client
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import NIOCore // apple/swift-nio
import NIOFoundationCompat
import Stencil // soto-project/Stencil

struct Endpoints: Decodable {
    struct CredentialScope: Decodable {
        var region: String?
        var service: String?
    }

    struct EndpointVariant: Decodable {
        var dnsSuffix: String?
        var hostname: String?
        var tags: Set<String>
    }

    struct Defaults: Decodable {
        var credentialScope: CredentialScope?
        var hostname: String
        var protocols: [String]?
        var signatureVersions: [String]?
        var variants: [EndpointVariant]
    }

    struct RegionDesc: Decodable {
        var description: String
    }

    struct Partition: Decodable {
        var defaults: Defaults
        var dnsSuffix: String
        var partition: String
        var partitionName: String
        var regionRegex: String
        var regions: [String: RegionDesc]
    }

    var partitions: [Partition]
}

struct OutputRegionDesc {
    let `enum`: String
    let name: String
    let description: String?
    let partition: String
}

struct OutputPartition {
    let name: String
    let description: String
    let hostname: String
    let dnsSuffix: String
}

struct OutputEndpointVariant {
    let variant: String
    let hostname: String
}

/// Load Endpoints from URL
/// - Parameter url: url of endpoints file
/// - Returns: Endpoints
func loadEndpoints(url: String) throws -> Endpoints? {
    let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
    defer {
        try? httpClient.syncShutdown()
    }
    let response = try httpClient.get(url: url, deadline: .now() + .seconds(10)).wait()
    if let body = response.body {
        let endpoints = try JSONDecoder().decode(Endpoints.self, from: body)
        return endpoints
    }
    return nil
}

print("Loading Endpoints")
guard let endpoints = try loadEndpoints(url: "https://raw.githubusercontent.com/aws/aws-sdk-go-v2/master/codegen/smithy-aws-go-codegen/src/main/resources/software/amazon/smithy/aws/go/codegen/endpoints.json") else { exit(-1) }

var regionDescs: [OutputRegionDesc] = []
var partitions: [OutputPartition] = endpoints.partitions.map {
    let hostname = $0.defaults.hostname
        .replacingOccurrences(of: "{service}", with: "\\(service)")
        .replacingOccurrences(of: "{region}", with: "\\(region)")
        .replacingOccurrences(of: "{dnsSuffix}", with: $0.dnsSuffix)
    return OutputPartition(
        name: $0.partition.filter { return $0.isLetter || $0.isNumber },
        description: $0.partitionName,
        hostname: hostname,
        dnsSuffix: $0.dnsSuffix
    )
}

for partition in endpoints.partitions {
    let partitionRegionDescs = partition.regions.keys.map { region in
        return OutputRegionDesc(
            enum: region.filter { return $0.isLetter || $0.isNumber },
            name: region,
            description: partition.regions[region]?.description,
            partition: partition.partition.filter { return $0.isLetter || $0.isNumber }
        )
    }
    regionDescs += partitionRegionDescs
}

print("Loading templates")
let fsLoader = FileSystemLoader(paths: ["./scripts/templates/generate-region"])
let environment = Environment(loader: fsLoader)

print("Creating Region.swift")

let context: [String: Any] = [
    "regions": regionDescs.sorted { $0.name < $1.name },
    "partitions": partitions,
]

let regionsFile = try environment.renderTemplate(name: "Region.stencil", context: context)
try Data(regionsFile.utf8).write(to: URL(fileURLWithPath: "Sources/SotoCore/Doc/Region.swift"))
