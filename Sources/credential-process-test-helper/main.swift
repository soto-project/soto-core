//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

let arguments = CommandLine.arguments

if arguments.contains("--invalid-json") {
    print("this is not json{{{")
    exit(0)
}

if let exitCodeIndex = arguments.firstIndex(of: "--exit-code"),
    exitCodeIndex + 1 < arguments.count,
    let code = Int32(arguments[exitCodeIndex + 1])
{
    exit(code)
}

let invalidVersion = arguments.contains("--invalid-version")
let expiring = arguments.contains("--expiring")
let noSessionToken = arguments.contains("--no-session-token")

var json: [String: Any] = [
    "Version": invalidVersion ? 2 : 1,
    "AccessKeyId": "AKID-CREDENTIAL-PROCESS",
    "SecretAccessKey": "SECRET-CREDENTIAL-PROCESS",
]

if !noSessionToken {
    json["SessionToken"] = "TOKEN-CREDENTIAL-PROCESS"
}

if expiring {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    json["Expiration"] = formatter.string(from: Date().addingTimeInterval(3600))
}

let data = try JSONSerialization.data(withJSONObject: json, options: [])
print(String(data: data, encoding: .utf8)!)
