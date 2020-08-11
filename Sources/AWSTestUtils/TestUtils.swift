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

@testable import AWSSDKSwiftCore
import Foundation
import Logging

@propertyWrapper public struct EnvironmentVariable<Value: LosslessStringConvertible> {
    var defaultValue: Value
    var variableName: String

    public init(_ variableName: String, default: Value) {
        self.defaultValue = `default`
        self.variableName = variableName
    }

    public var wrappedValue: Value {
        guard let value = Environment[variableName] else { return self.defaultValue }
        return Value(value) ?? self.defaultValue
    }
}

public func createAWSClient(
    credentialProvider: CredentialProviderFactory = .default,
    retryPolicy: RetryPolicyFactory = .noRetry,
    middlewares: [AWSServiceMiddleware] = TestEnvironment.middlewares,
    httpClientProvider: AWSClient.HTTPClientProvider = .createNew,
    logger: Logger = TestEnvironment.logger
) -> AWSClient {
    return AWSClient(
        credentialProvider: credentialProvider,
        retryPolicy: retryPolicy,
        middlewares: middlewares,
        httpClientProvider: httpClientProvider,
        logger: logger
    )
}

public func createServiceConfig(
    region: Region? = nil,
    partition: AWSPartition = .aws,
    amzTarget: String? = nil,
    service: String = "test",
    signingName: String? = nil,
    serviceProtocol: ServiceProtocol = .restjson,
    apiVersion: String = "01-01-2001",
    endpoint: String? = nil,
    serviceEndpoints: [String: String] = [:],
    partitionEndpoints: [AWSPartition: (endpoint: String, region: Region)] = [:],
    possibleErrorTypes: [AWSErrorType.Type] = [],
    middlewares: [AWSServiceMiddleware] = [],
    timeout: TimeAmount? = nil
) -> AWSServiceConfig {
    AWSServiceConfig(
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
        middlewares: middlewares,
        timeout: timeout
    )
}

// create a buffer of random values. Will always create the same given you supply the same z and w values
// Random number generator from https://www.codeproject.com/Articles/25172/Simple-Random-Number-Generation
public func createRandomBuffer(_ w: UInt, _ z: UInt, size: Int) -> [UInt8] {
    var z = z
    var w = w
    func getUInt8() -> UInt8 {
        z = 36969 * (z & 65535) + (z >> 16)
        w = 18000 * (w & 65535) + (w >> 16)
        return UInt8(((z << 16) + w) & 0xFF)
    }
    var data = [UInt8](repeating: 0, count: size)
    for i in 0..<size {
        data[i] = getUInt8()
    }
    return data
}

/// Provide various test environment variables
public struct TestEnvironment {
    /// current list of middleware
    public static var middlewares: [AWSServiceMiddleware] {
        return (Environment["AWS_ENABLE_LOGGING"] == "true") ? [AWSLoggingMiddleware()] : []
    }

    public static var context: AWSServiceContext { .init(logger: logger) }
    
    public static var logger: Logger = {
        if let loggingLevel = Environment["AWS_LOG_LEVEL"] {
            if let logLevel = Logger.Level(rawValue: loggingLevel.lowercased()) {
                var logger = Logger(label: "aws-sdk-swift")
                logger.logLevel = logLevel
                return logger
            }
        }
        return AWSClient.loggingDisabled
    }()
}
