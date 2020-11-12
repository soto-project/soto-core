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

import Foundation
import SotoCore // soto-project/soto-core ~> 5.0.0-beta.3.0
import SotoSSM // soto-project/soto ~> 5.0.0-beta.3.0
import Stencil // soto-project/Stencil

let REGION_PATH = "/aws/service/global-infrastructure/regions"

print("Loading Region List")
struct RegionDesc {
    let `enum`: String
    let name: String
}

var regionDescs: [RegionDesc] = []

let client = AWSClient(
    httpClientProvider: .createNew
)
let ssm = SSM(client: client, region: Region.euwest1)
let request = SSM.GetParametersByPathRequest(
    path: REGION_PATH
)
do {
    var result = try ssm.getParametersByPath(request).wait()
    while result.nextToken != nil {
        for p in result.parameters! {
            regionDescs.append(
                RegionDesc(enum: p.value!.filter { return $0.isLetter || $0.isNumber }, name: p.value!)
            )
        }
        let request = SSM.GetParametersByPathRequest(
            nextToken: result.nextToken,
            path: REGION_PATH
        )
        result = try ssm.getParametersByPath(request).wait()
    }
} catch (let error) {
    print("Failed with \(error)")
}

print("Loading templates")
let fsLoader = FileSystemLoader(paths: ["./scripts/templates/generate-region"])
let environment = Environment(loader: fsLoader)

print("Creating RegionTests.swift")

let context: [String: Any] = [
    "regions": regionDescs.sorted { $0.name < $1.name },
]

let regionsFile = try environment.renderTemplate(name: "Region-Tests.stencil", context: context)
try Data(regionsFile.utf8).write(to: URL(fileURLWithPath: "Tests/SotoCoreTests/Doc/RegionTests.swift"))

print("Done")
