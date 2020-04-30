//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import class Foundation.ProcessInfo

/// Configuration class defining an AWS service
public struct ServiceConfig {
    /// Region where service is running
    public let region: Region
    /// The destination service of the request. Added as a header value, along with the operation name
    public let amzTarget: String?
    /// Name used to sign requests
    public let signingName: String
    /// Protocol used by service json/xml/query
    public let serviceProtocol: ServiceProtocol
    /// Version of the Service API, added as a header in query protocol based services
    public let apiVersion: String
    /// The url to use in requests
    public let endpoint: String
    /// An array of the possible error types returned by the service
    public let possibleErrorTypes: [AWSErrorType.Type]
    /// Middleware code specific to the service used to edit requests before they sent and responses before they are decoded
    public let middlewares: [AWSServiceMiddleware]
    
    public init(
        region givenRegion: Region?,
        amzTarget: String? = nil,
        service: String,
        signingName: String? = nil,
        serviceProtocol: ServiceProtocol,
        apiVersion: String,
        endpoint: String? = nil,
        serviceEndpoints: [String: String] = [:],
        partitionEndpoint: String? = nil,
        possibleErrorTypes: [AWSErrorType.Type] = [],
        middlewares: [AWSServiceMiddleware] = []
    )
    {
        if let _region = givenRegion {
            region = _region
        }
        else if let partitionEndpoint = partitionEndpoint {
            if partitionEndpoint == "aws-global" {
                region = .useast1
            } else {
                region = Region(rawValue: partitionEndpoint)
            }
        } else if let defaultRegion = ProcessInfo.processInfo.environment["AWS_DEFAULT_REGION"] {
            region = Region(rawValue: defaultRegion)
        } else {
            region = .useast1
        }

        self.apiVersion = apiVersion
        self.signingName = signingName ?? service
        self.amzTarget = amzTarget
        self.serviceProtocol = serviceProtocol
        self.possibleErrorTypes = possibleErrorTypes
        self.middlewares = middlewares

        // work out endpoint, if provided use that otherwise
        if let endpoint = endpoint {
            self.endpoint = endpoint
        } else {
            let serviceHost: String
            if let serviceEndpoint = serviceEndpoints[region.rawValue] {
                serviceHost = serviceEndpoint
            } else if let partitionEndpoint = partitionEndpoint, let globalEndpoint = serviceEndpoints[partitionEndpoint] {
                serviceHost = globalEndpoint
            } else {
                serviceHost = "\(service).\(region.rawValue).amazonaws.com"
            }
            self.endpoint = "https://\(serviceHost)"
        }
    }
}
