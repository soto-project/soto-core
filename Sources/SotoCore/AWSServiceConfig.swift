//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
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
    public let errorType: AWSErrorType.Type?
    /// Middleware code specific to the service used to edit requests before they sent and responses before they are decoded
    public let middlewares: [AWSServiceMiddleware]
    /// timeout value for HTTP requests
    public let timeout: TimeAmount
    /// ByteBuffer allocator used by service
    public let byteBufferAllocator: ByteBufferAllocator
    /// options
    public let options: Options

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
    ///   - timeout: Time out value for HTTP requests
    ///   - byteBufferAllocator: byte buffer allocator used throughout AWSClient
    ///   - options: options used by client when processing requests
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
        errorType: AWSErrorType.Type? = nil,
        middlewares: [AWSServiceMiddleware] = [],
        timeout: TimeAmount? = nil,
        byteBufferAllocator: ByteBufferAllocator = ByteBufferAllocator(),
        options: Options = []
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
        self.errorType = errorType
        self.middlewares = middlewares
        self.timeout = timeout ?? .seconds(20)
        self.byteBufferAllocator = byteBufferAllocator
        self.options = options

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

    /// Return new version of serviceConfig with a modified parameters
    /// - Parameters:
    ///   - patch: parameters to patch service config
    /// - Returns: New AWSServiceConfig
    public func with(patch: Patch) -> AWSServiceConfig {
        return AWSServiceConfig(
            region: self.region,
            amzTarget: self.amzTarget,
            service: self.service,
            signingName: self.signingName,
            serviceProtocol: self.serviceProtocol,
            apiVersion: self.apiVersion,
            endpoint: self.endpoint,
            errorType: self.errorType,
            middlewares: self.middlewares + patch.middlewares,
            timeout: patch.timeout ?? self.timeout,
            byteBufferAllocator: patch.byteBufferAllocator ?? self.byteBufferAllocator,
            options: patch.options ?? self.options
        )
    }

    /// Service config parameters you can patch
    public struct Patch {
        let middlewares: [AWSServiceMiddleware]
        let timeout: TimeAmount?
        let byteBufferAllocator: ByteBufferAllocator?
        let options: Options?

        init(
            middlewares: [AWSServiceMiddleware] = [],
            timeout: TimeAmount? = nil,
            byteBufferAllocator: ByteBufferAllocator? = nil,
            options: AWSServiceConfig.Options? = nil
        ) {
            self.middlewares = middlewares
            self.timeout = timeout
            self.byteBufferAllocator = byteBufferAllocator
            self.options = options
        }
    }

    /// Options used by client when processing requests
    public struct Options: OptionSet {
        public let rawValue: Int

        public init(rawValue: RawValue) {
            self.rawValue = rawValue
        }

        /// If you set a custom endpoint, s3 will choose path style addressing. With this paramteter you can force
        /// it to use virtual host style addressing
        public static let s3ForceVirtualHost = Options(rawValue: 1 << 0)
    }

    private init(
        region: Region,
        amzTarget: String?,
        service: String,
        signingName: String,
        serviceProtocol: ServiceProtocol,
        apiVersion: String,
        endpoint: String,
        errorType: AWSErrorType.Type?,
        middlewares: [AWSServiceMiddleware],
        timeout: TimeAmount,
        byteBufferAllocator: ByteBufferAllocator,
        options: Options
    ) {
        self.region = region
        self.amzTarget = amzTarget
        self.service = service
        self.signingName = signingName
        self.serviceProtocol = serviceProtocol
        self.apiVersion = apiVersion
        self.endpoint = endpoint
        self.errorType = errorType
        self.middlewares = middlewares
        self.timeout = timeout
        self.byteBufferAllocator = byteBufferAllocator
        self.options = options
    }
}
