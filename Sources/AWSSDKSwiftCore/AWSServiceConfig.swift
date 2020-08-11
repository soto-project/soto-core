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

import NIO

/// Configuration class defining an AWS service
public final class AWSServiceConfig {
    /// Region where service is running
    public let region: Region
    /// The destination service of the request. Added as a header value, along with the operation name
    public let amzTarget: String?
    /// Name of service
    public let service: String
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

    /// Create a ServiceConfig object
    ///
    /// - Parameters:
    ///   - region: Region of server you want to communicate with
    ///   - partition: Amazon endpoint partition. This is ignored if region is set. If no region is set then this is used along side partitionEndpoints to calculate endpoint
    ///   - amzTarget: "x-amz-target" header value
    ///   - service: Name of service endpoint
    ///   - signingName: Name that all AWS requests are signed with
    ///   - serviceProtocol: protocol of service (.json, .xml, .query etc)
    ///   - apiVersion: "Version" header value
    ///   - endpoint: Custom endpoint URL to use instead of standard AWS servers
    ///   - serviceEndpoints: Dictionary of endpoints to URLs
    ///   - partitionEndpoints: Default endpoint to use, if no region endpoint is supplied
    ///   - possibleErrorTypes: Array of possible error types that the client can throw
    ///   - middlewares: Array of middlewares to apply to requests and responses
    public init(
        region: Region?,
        partition: AWSPartition,
        amzTarget: String? = nil,
        service: String,
        signingName: String? = nil,
        serviceProtocol: ServiceProtocol,
        apiVersion: String,
        endpoint: String? = nil,
        serviceEndpoints: [String: String] = [:],
        partitionEndpoints: [AWSPartition: (endpoint: String, region: Region)] = [:],
        possibleErrorTypes: [AWSErrorType.Type] = [],
        middlewares: [AWSServiceMiddleware] = []
    ) {
        var partition = partition
        if let region = region {
            self.region = region
            partition = region.partition
        } else if let partitionEndpoint = partitionEndpoints[partition] {
            self.region = partitionEndpoint.region
        } else if let defaultRegion = Environment["AWS_DEFAULT_REGION"] {
            self.region = Region(rawValue: defaultRegion)
        } else {
            self.region = .useast1
        }

        self.service = service
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
            if let serviceEndpoint = serviceEndpoints[self.region.rawValue] {
                serviceHost = serviceEndpoint
            } else if let partitionEndpoint = partitionEndpoints[partition],
                let globalEndpoint = serviceEndpoints[partitionEndpoint.endpoint]
            {
                serviceHost = globalEndpoint
            } else {
                serviceHost = "\(service).\(self.region.rawValue).\(partition.dnsSuffix)"
            }
            self.endpoint = "https://\(serviceHost)"
        }
    }
}
