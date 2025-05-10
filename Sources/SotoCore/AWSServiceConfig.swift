//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2020-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

/// Configuration class defining an AWS service
public final class AWSServiceConfig {
    /// Region where service is running
    public let region: Region
    /// The destination service of the request. Added as a header value, along with the operation name
    public let amzTarget: String?
    /// Name of service
    public let serviceName: String
    /// Identifier of service. Used in ARN and as endpoint prefix
    public let serviceIdentifier: String
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
    /// XML namespace to be applied to all request objects
    public let xmlNamespace: String?
    /// Middleware code specific to the service used to edit requests before they sent and responses before they are decoded
    public let middleware: AWSMiddlewareProtocol?
    /// timeout value for HTTP requests
    public let timeout: TimeAmount
    /// ByteBuffer allocator used by service
    public let byteBufferAllocator: ByteBufferAllocator
    /// options
    public let options: Options
    /// values used to create endpoint
    private let providedEndpoint: String?
    private let serviceEndpoints: [String: String]
    private let partitionEndpoints: [AWSPartition: (endpoint: String, region: Region)]
    private let variantEndpoints: [EndpointVariantType: EndpointVariant]

    /// Create a ServiceConfig object
    ///
    /// - Parameters:
    ///   - region: Region of server you want to communicate with
    ///   - partition: Amazon endpoint partition. This is ignored if region is set. If no region is set then this is used along side partitionEndpoints to calculate endpoint
    ///   - amzTarget: "x-amz-target" header value
    ///   - serviceName: Name of service
    ///   - serviceIdentifier: Identifier of service. Used in ARN and endpoint
    ///   - signingName: Name that all AWS requests are signed with
    ///   - serviceProtocol: protocol of service (.json, .xml, .query etc)
    ///   - apiVersion: "Version" header value
    ///   - endpoint: Custom endpoint URL to use instead of standard AWS servers
    ///   - serviceEndpoints: Dictionary of endpoints to URLs
    ///   - partitionEndpoints: Default endpoint to use, if no region endpoint is supplied
    ///   - variantEndpoints: Variant endpoints (FIPS, dualstack)
    ///   - errorType: Error type that the client can throw
    ///   - xmlNamespace: XML Namespace to be applied to request objects
    ///   - middleware: Chain of middleware to apply to requests and responses
    ///   - timeout: Time out value for HTTP requests
    ///   - byteBufferAllocator: byte buffer allocator used throughout AWSClient
    ///   - options: options used by client when processing requests
    public init(
        region: Region?,
        partition: AWSPartition,
        amzTarget: String? = nil,
        serviceName: String,
        serviceIdentifier: String,
        signingName: String? = nil,
        serviceProtocol: ServiceProtocol,
        apiVersion: String,
        endpoint: String? = nil,
        serviceEndpoints: [String: String] = [:],
        partitionEndpoints: [AWSPartition: (endpoint: String, region: Region)] = [:],
        variantEndpoints: [EndpointVariantType: EndpointVariant] = [:],
        errorType: AWSErrorType.Type? = nil,
        xmlNamespace: String? = nil,
        middleware: AWSMiddlewareProtocol? = nil,
        timeout: TimeAmount? = nil,
        byteBufferAllocator: ByteBufferAllocator = ByteBufferAllocator(),
        options: Options = []
    ) {
        var partition = partition
        if let region {
            self.region = region
            partition = region.partition
        } else if let partitionEndpoint = partitionEndpoints[partition] {
            self.region = partitionEndpoint.region
        } else if let defaultRegion = Environment["AWS_DEFAULT_REGION"] {
            self.region = Region(rawValue: defaultRegion)
        } else {
            self.region = .useast1
        }

        self.serviceName = serviceName
        self.serviceIdentifier = serviceIdentifier
        self.apiVersion = apiVersion
        self.signingName = signingName ?? serviceIdentifier
        self.amzTarget = amzTarget
        self.serviceProtocol = serviceProtocol
        self.errorType = errorType
        self.xmlNamespace = xmlNamespace
        self.middleware = middleware
        self.timeout = timeout ?? .seconds(20)
        self.byteBufferAllocator = byteBufferAllocator
        self.options = options

        self.providedEndpoint = endpoint
        self.serviceEndpoints = serviceEndpoints
        self.partitionEndpoints = partitionEndpoints
        self.variantEndpoints = variantEndpoints

        self.endpoint = Self.getEndpoint(
            endpoint: endpoint,
            region: self.region,
            serviceIdentifier: serviceIdentifier,
            options: options,
            serviceEndpoints: serviceEndpoints,
            partitionEndpoints: partitionEndpoints,
            variantEndpoints: variantEndpoints
        )
    }

    /// Calculate endpoint
    private static func getEndpoint(
        endpoint: String?,
        region: Region,
        serviceIdentifier: String,
        options: Options,
        serviceEndpoints: [String: String],
        partitionEndpoints: [AWSPartition: (endpoint: String, region: Region)],
        variantEndpoints: [EndpointVariantType: EndpointVariant]
    ) -> String {
        // work out endpoint, if provided use that otherwise
        if let endpoint {
            return endpoint
        } else {
            let serviceHost: String
            if let variantEndpoints = variantEndpoints[options.endpointVariant] {
                if let endpoint = variantEndpoints.endpoints[region.rawValue] {
                    serviceHost = endpoint
                } else if let partitionEndpoint = partitionEndpoints[region.partition],
                    let endpoint = variantEndpoints.endpoints[partitionEndpoint.endpoint]
                {
                    serviceHost = endpoint
                } else if let host = variantEndpoints.defaultEndpoint?(region.rawValue) {
                    serviceHost = host
                } else {
                    preconditionFailure("\(options.endpointVariant) endpoint for \(serviceIdentifier) in \(region) does not exist")
                }
            } else if let serviceEndpoint = serviceEndpoints[region.rawValue] {
                serviceHost = serviceEndpoint
            } else if let partitionEndpoint = partitionEndpoints[region.partition],
                let globalEndpoint = serviceEndpoints[partitionEndpoint.endpoint]
            {
                serviceHost = globalEndpoint
            } else {
                serviceHost = region.partition.defaultEndpoint(region: region, service: serviceIdentifier)
            }
            return "https://\(serviceHost)"
        }
    }

    /// Return new version of serviceConfig with a modified parameters
    /// - Parameters:
    ///   - patch: parameters to patch service config
    /// - Returns: New AWSServiceConfig
    public func with(patch: Patch) -> AWSServiceConfig {
        AWSServiceConfig(service: self, with: patch)
    }

    /// Service config parameters you can patch
    public struct Patch {
        let region: Region?
        let endpoint: String?
        let middleware: AWSMiddlewareProtocol?
        let timeout: TimeAmount?
        let byteBufferAllocator: ByteBufferAllocator?
        let options: Options?

        init(
            region: Region? = nil,
            endpoint: String? = nil,
            middleware: AWSMiddlewareProtocol? = nil,
            timeout: TimeAmount? = nil,
            byteBufferAllocator: ByteBufferAllocator? = nil,
            options: AWSServiceConfig.Options? = nil
        ) {
            self.region = region
            self.endpoint = endpoint
            self.middleware = middleware
            self.timeout = timeout
            self.byteBufferAllocator = byteBufferAllocator
            self.options = options
        }
    }

    /// Return new version of Service with edited parameters
    /// - Parameters:
    ///   - region: Server region
    ///   - middleware: Additional middleware to add
    ///   - timeout: Time out value for HTTP requests
    ///   - byteBufferAllocator: byte buffer allocator used throughout AWSClient
    ///   - options: options used by client when processing requests
    /// - Returns: New version of the service
    public func with(
        region: Region? = nil,
        middleware: AWSMiddlewareProtocol? = nil,
        timeout: TimeAmount? = nil,
        byteBufferAllocator: ByteBufferAllocator? = nil,
        options: AWSServiceConfig.Options? = nil
    ) -> AWSServiceConfig {
        self.with(
            patch: .init(
                region: region,
                middleware: middleware,
                timeout: timeout,
                byteBufferAllocator: byteBufferAllocator,
                options: options
            )
        )
    }

    /// Options used by client when processing requests
    public struct Options: OptionSet {
        public typealias RawValue = Int
        public let rawValue: Int

        public init(rawValue: RawValue) {
            self.rawValue = rawValue
        }

        /// If you set a custom endpoint, s3 will choose path style addressing. With this paramteter you can force
        /// it to use virtual host style addressing
        public static let s3ForceVirtualHost = Options(rawValue: 1 << 0)

        /// Use a dual stack S3 endpoint. WHen you make a request to a dual-stack endpoint the bucket URL resolves
        /// to an IPv6 or an IPv4 address
        @available(*, deprecated, message: "This case is deprecated, use .useDualStackEndpoint instead.")
        public static let s3UseDualStackEndpoint = Options(rawValue: 1 << 1)

        /// Use S3 transfer accelerated endpoint. You need to enable transfer acceleration on the bucket for this to work
        public static let s3UseTransferAcceleratedEndpoint = Options(rawValue: 1 << 2)

        /// Enable endpoint discovery for services where it isn't required
        public static let enableEndpointDiscovery = Options(rawValue: 1 << 3)

        /// Disable S3 signed chunked uploads
        public static let s3DisableChunkedUploads = Options(rawValue: 1 << 4)

        /// calculate MD5 for requests with content-md5 header
        public static let calculateMD5 = Options(rawValue: 1 << 5)

        /// disable `Expect: 100-Continue`` header. Some S3 like services don't like it
        public static let s3Disable100Continue = Options(rawValue: 1 << 6)

        /// use endpoint that conforms to FIPS 140-2 standard. FIPS endpoints are not always available.
        public static let useFipsEndpoint = Options(rawValue: 1 << 7)

        /// use dual stack endpoint. When you make a request to a dual-stack endpoint the bucket URL resolves
        /// to an IPv6 or an IPv4 address. DualStack endpoints are not always available.
        public static let useDualStackEndpoint = Options(rawValue: 1 << 1)
    }

    /// Details about endpoint variants eg fips, dualstack
    public struct EndpointVariant {
        public typealias EndpointCallback = @Sendable (String) -> String

        let defaultEndpoint: EndpointCallback?
        let endpoints: [String: String]

        public init(defaultEndpoint: EndpointCallback? = nil, endpoints: [String: String] = [:]) {
            self.defaultEndpoint = defaultEndpoint
            self.endpoints = endpoints
        }

        func getEndpoint(region: String) -> String? {
            if let endpoint = self.endpoints[region] {
                return endpoint
            } else if let endpointCallback = self.defaultEndpoint {
                return endpointCallback(region)
            }
            return nil
        }
    }

    private init(
        service: AWSServiceConfig,
        with patch: Patch
    ) {
        self.region = patch.region ?? service.region
        self.options = patch.options ?? service.options
        self.serviceIdentifier = service.serviceIdentifier
        self.signingName = service.signingName

        if let endpoint = patch.endpoint {
            self.endpoint = endpoint
        } else if patch.options != nil || patch.region != nil {
            self.endpoint =
                patch.endpoint
                ?? Self.getEndpoint(
                    endpoint: service.providedEndpoint,
                    region: self.region,
                    serviceIdentifier: self.serviceIdentifier,
                    options: self.options,
                    serviceEndpoints: service.serviceEndpoints,
                    partitionEndpoints: service.partitionEndpoints,
                    variantEndpoints: service.variantEndpoints
                )
        } else {
            self.endpoint = service.endpoint
        }

        self.amzTarget = service.amzTarget
        self.serviceName = service.serviceName
        self.serviceProtocol = service.serviceProtocol
        self.apiVersion = service.apiVersion
        self.providedEndpoint = service.providedEndpoint
        self.serviceEndpoints = service.serviceEndpoints
        self.partitionEndpoints = service.partitionEndpoints
        self.variantEndpoints = service.variantEndpoints
        self.errorType = service.errorType
        self.xmlNamespace = service.xmlNamespace
        self.timeout = patch.timeout ?? service.timeout
        self.byteBufferAllocator = patch.byteBufferAllocator ?? service.byteBufferAllocator

        if let serviceMiddleware = service.middleware {
            if let patchMiddleware = patch.middleware {
                self.middleware = AWSDynamicMiddlewareStack(serviceMiddleware, patchMiddleware)
            } else {
                self.middleware = serviceMiddleware
            }
        } else {
            self.middleware = patch.middleware
        }
    }
}

extension AWSServiceConfig: Sendable {}
extension AWSServiceConfig.Options: Sendable {}
extension AWSServiceConfig.EndpointVariant: Sendable {}
