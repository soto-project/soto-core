//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
@testable import AWSSDKSwiftCore

@propertyWrapper public struct EnvironmentVariable<Value: LosslessStringConvertible> {
    var defaultValue: Value
    var variableName: String

    public init(_ variableName: String, default: Value) {
        self.defaultValue = `default`
        self.variableName = variableName
    }

    public var wrappedValue: Value {
        get {
            guard let value = Environment[variableName] else { return defaultValue }
            return Value(value) ?? defaultValue
        }
    }
}

public func createServiceConfig(
    region: Region? = nil,
    partition: Partition = .aws,
    amzTarget: String? = nil,
    service: String = "test",
    signingName: String? = nil,
    serviceProtocol: ServiceProtocol = .restjson,
    apiVersion: String = "01-01-2001",
    endpoint: String? = nil,
    serviceEndpoints: [String: String] = [:],
    partitionEndpoints: [Partition: (endpoint: String, region: Region)] = [:],
    possibleErrorTypes: [AWSErrorType.Type] = [],
    middlewares: [AWSServiceMiddleware] = []) -> ServiceConfig
{
    ServiceConfig(
        region: region,
        partition: partition,
        amzTarget: amzTarget,
        service: service,
        signingName: signingName,
        serviceProtocol: serviceProtocol,
        apiVersion: apiVersion,
        endpoint: endpoint,
        serviceEndpoints: serviceEndpoints,
        partitionEndpoints: partitionEndpoints,
        possibleErrorTypes: possibleErrorTypes,
        middlewares: middlewares)
}

// create a buffer of random values. Will always create the same given you supply the same z and w values
// Random number generator from https://www.codeproject.com/Articles/25172/Simple-Random-Number-Generation
public func createRandomBuffer(_ w: UInt, _ z: UInt, size: Int) -> [UInt8] {
    var z = z
    var w = w
    func getUInt8() -> UInt8
    {
        z = 36969 * (z & 65535) + (z >> 16);
        w = 18000 * (w & 65535) + (w >> 16);
        return UInt8(((z << 16) + w) & 0xff);
    }
    var data = Array<UInt8>(repeating: 0, count: size)
    for i in 0..<size {
        data[i] = getUInt8()
    }
    return data
}
