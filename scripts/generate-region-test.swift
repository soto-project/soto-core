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
import Foundation
import NIO // apple/swift-nio
import NIOFoundationCompat
import Stencil // soto-project/Stencil

struct Endpoints: Decodable {
    struct CredentialScope: Decodable {
        var region: String?
        var service: String?
    }

    struct Defaults: Decodable {
        var credentialScope: CredentialScope?
        var hostname: String?
        var protocols: [String]?
        var signatureVersions: [String]?
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

struct RegionDesc {
    let `enum`: String
    let name: String
    let description: String?
    let partition: String
}

struct Partition {
    let name: String
    let description: String
    let dnsSuffix: String
}

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
guard let endpoints = try loadEndpoints(url: "https://raw.githubusercontent.com/aws/aws-sdk-go/master/models/endpoints/endpoints.json") else { exit(-1) }

var regionDescs: [RegionDesc] = []
var partitions: [Partition] = endpoints.partitions.map {
    return Partition(
        name: $0.partition.filter { return $0.isLetter || $0.isNumber },
        description: $0.partitionName,
        dnsSuffix: $0.dnsSuffix
    )
}

for partition in endpoints.partitions {
    let partitionRegionDescs = partition.regions.keys.map { region in
        return RegionDesc(
            enum: region.filter { return $0.isLetter || $0.isNumber },
            name: region,
            description: partition.regions[region]?.description,
            partition: partition.partition.filter { return $0.isLetter || $0.isNumber }
        )
    }
    regionDescs += partitionRegionDescs
}

// Add ap-northeast-3 as it isn't in the endpoints.json. It is intentionally excluded from endpoints as it requires access request.
regionDescs.append(.init(enum: "apnortheast3", name: "ap-northeast-3", description: "Asia Pacific (Osaka Local)", partition: "aws"))

print("Loading templates")
let fsLoader = FileSystemLoader(paths: ["./scripts/templates/generate-region"])
let environment = Environment(loader: fsLoader)

print("Creating RegionTests.swift")

let context: [String: Any] = [
    "regions": regionDescs.sorted { $0.name < $1.name },
    "partitions": partitions,
]

let regionsFile = try environment.renderTemplate(name: "Region-Tests.stencil", context: context)
try Data(regionsFile.utf8).write(to: URL(fileURLWithPath: "Tests/SotoCoreTests/Doc/RegionTests.swift"))
