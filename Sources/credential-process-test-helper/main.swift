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

// This binary has zero dependencies (no Foundation, no SotoCore) so it builds
// fast and doesn't pull in the rest of the package graph. We construct JSON
// manually and use libc gmtime_r for ISO8601 dates instead of Codable/JSONEncoder
// and ISO8601DateFormatter which would require Foundation.

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin.C
#elseif canImport(Android)
import Android
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

var fields: [String] = []
fields.append("\"Version\":\(invalidVersion ? 2 : 1)")
fields.append("\"AccessKeyId\":\"AKID-CREDENTIAL-PROCESS\"")
fields.append("\"SecretAccessKey\":\"SECRET-CREDENTIAL-PROCESS\"")

if !noSessionToken {
    fields.append("\"SessionToken\":\"TOKEN-CREDENTIAL-PROCESS\"")
}

if expiring {
    var now = time(nil)
    now += 3600
    var tm = tm()
    gmtime_r(&now, &tm)

    func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
    func pad4(_ n: Int) -> String {
        if n < 10 { return "000\(n)" }
        if n < 100 { return "00\(n)" }
        if n < 1000 { return "0\(n)" }
        return "\(n)"
    }

    let year = pad4(Int(tm.tm_year) + 1900)
    let month = pad2(Int(tm.tm_mon) + 1)
    let day = pad2(Int(tm.tm_mday))
    let hour = pad2(Int(tm.tm_hour))
    let min = pad2(Int(tm.tm_min))
    let sec = pad2(Int(tm.tm_sec))
    let expiration = "\(year)-\(month)-\(day)T\(hour):\(min):\(sec)Z"
    fields.append("\"Expiration\":\"\(expiration)\"")
}

print("{\(fields.joined(separator: ","))}")
