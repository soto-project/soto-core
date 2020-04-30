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

import AWSSDKSwiftCore
import Foundation

@propertyWrapper struct EnvironmentVariable<Value: LosslessStringConvertible> {
    var defaultValue: Value
    var variableName: String

    public init(_ variableName: String, default: Value) {
        self.defaultValue = `default`
        self.variableName = variableName
    }
    
    public var wrappedValue: Value {
        get {
            guard let value = ProcessInfo.processInfo.environment[variableName] else { return defaultValue }
            return Value(value) ?? defaultValue
        }
    }
}

func createAWSClient(
    accessKeyId: String? = nil,
    secretAccessKey: String? = nil,
    sessionToken: String? = nil,
    region: Region = .useast1,
    amzTarget: String? = nil,
    service: String = "testService",
    signingName: String? = nil,
    serviceProtocol: ServiceProtocol = .restjson,
    apiVersion: String = "01-01-2001",
    endpoint: String? = nil,
    serviceEndpoints: [String: String] = [:],
    partitionEndpoint: String? = nil,
    retryController: RetryController = NoRetry(),
    middlewares: [AWSServiceMiddleware] = [],
    possibleErrorTypes: [AWSErrorType.Type] = [],
    httpClientProvider: AWSClient.HTTPClientProvider = .createNew
) -> AWSClient {
    return AWSClient(
        accessKeyId: accessKeyId,
        secretAccessKey: secretAccessKey,
        sessionToken: sessionToken,
        region: region,
        amzTarget: amzTarget,
        service: service,
        signingName: signingName,
        serviceProtocol: serviceProtocol,
        apiVersion: apiVersion,
        endpoint: endpoint,
        serviceEndpoints: serviceEndpoints,
        partitionEndpoint: partitionEndpoint,
        retryController: retryController,
        middlewares: middlewares,
        possibleErrorTypes: possibleErrorTypes,
        httpClientProvider: httpClientProvider
    )
}
