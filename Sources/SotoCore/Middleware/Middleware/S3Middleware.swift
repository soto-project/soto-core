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

import Crypto
// TODO: Need to replace percent encode
import Foundation
@_spi(SotoInternal) import SotoSignerV4
internal import SotoXML

extension S3Middleware {
    @TaskLocal public static var executionContext: ExecutionContext?

    /// Task local execution context for operation
    public struct ExecutionContext: Sendable {
        public init(useS3ExpressControlEndpoint: Bool) {
            self.useS3ExpressControlEndpoint = useS3ExpressControlEndpoint
        }
        public let useS3ExpressControlEndpoint: Bool
    }
}

/// Middleware applied to S3 service
///
/// This middleware does a number of request and response fixups for the S3 service.
///
/// For requests it
/// - outputs URL's in virtual address form with bucket name prefixed to host
/// - adds support for accelerate and dual stack addresses
/// - fixes up CreateBucket to include region as the location constraint
/// - Adds expect: 100-continue header
///
/// For responses it
/// - Fixes up the GetBucketLocation response, so it can be decoded correctly
/// - Creates error body for notFound responses to HEAD requests
public struct S3Middleware: AWSMiddlewareProtocol {
    public func handle(_ request: AWSHTTPRequest, context: AWSMiddlewareContext, next: AWSMiddlewareNextHandler) async throws -> AWSHTTPResponse {

        try await self.handleVirtualAddressFixup(request, context: context) { request, context in
            var request = request
            self.createBucketFixup(request: &request, context: context)
            if !context.serviceConfig.options.contains(.s3Disable100Continue) {
                self.expect100Continue(request: &request)
            }

            do {
                var response = try await next(request, context)
                if context.operation == "GetBucketLocation" {
                    self.getBucketLocationResponseFixup(response: &response)
                }
                return response
            } catch let error as AWSRawError {
                let newError = self.fixupRawError(error: error, context: context)
                throw newError
            }
        }
    }

    public init() {}

    func handleVirtualAddressFixup(
        _ request: AWSHTTPRequest,
        context: AWSMiddlewareContext,
        next: AWSMiddlewareNextHandler
    ) async throws -> AWSHTTPResponse {
        if request.url.path.hasPrefix("/arn:") {
            return try await handleARNBucket(request, context: context, next: next)
        }
        /// split path into components. Drop first as it is an empty string
        let paths = request.url.path.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false).dropFirst()
        guard let bucket = paths.first, bucket != "", var host = request.url.host else { return try await next(request, context) }
        let path = paths.dropFirst().first.flatMap { String($0) } ?? ""

        if let port = request.url.port {
            host = "\(host):\(port)"
        }
        var urlPath: String
        var urlHost: String
        let isAmazonUrl = host.hasSuffix(context.serviceConfig.region.partition.dnsSuffix)

        // if bucket has suffix "-x-s3" then it must be an s3 express directory bucket and the endpoint needs set up
        // to use s3express
        if bucket.hasSuffix("--x-s3"),
            let response = try await handleS3ExpressBucketEndpoint(
                request: request,
                bucket: bucket,
                path: path,
                context: context,
                next: next
            )
        {
            return response
        } else {

            // Should we use accelerated endpoint
            var hostComponents = host.split(separator: ".")
            if isAmazonUrl, context.serviceConfig.options.contains(.s3UseTransferAcceleratedEndpoint) {
                if let s3Index = hostComponents.firstIndex(where: { $0 == "s3" }) {
                    var s3 = "s3"
                    s3 += "-accelerate"
                    // assume next host component is region
                    let regionIndex = s3Index + 1
                    hostComponents.remove(at: regionIndex)
                    hostComponents[s3Index] = Substring(s3)
                    host = hostComponents.joined(separator: ".")
                }
            }

            if isAmazonUrl || context.serviceConfig.options.contains(.s3ForceVirtualHost), !bucket.contains(".") {
                urlPath = path
                if hostComponents.first == bucket {
                    // Bucket name is part of host. No need to append bucket
                    urlHost = host
                } else {
                    urlHost = "\(bucket).\(host)"
                }
            } else {
                urlPath = paths.joined(separator: "/")
                urlHost = host
            }
        }
        let request = try Self.updateRequestURL(request, host: urlHost, path: urlPath)
        return try await next(request, context)
    }

    ///  Handle bucket names in the form of an ARN
    /// - Parameters:
    ///   - request: request
    ///   - context: request context
    ///   - next: next handler
    /// - Returns: returns response from next handler
    func handleARNBucket(
        _ request: AWSHTTPRequest,
        context: AWSMiddlewareContext,
        next: AWSMiddlewareNextHandler
    ) async throws -> AWSHTTPResponse {
        guard let arn = ARN(string: request.url.path.dropFirst()),
            let resourceType = arn.resourceType,
            let accountId = arn.accountId
        else {
            throw AWSClient.ClientError.invalidARN
        }
        let region = arn.region ?? context.serviceConfig.region
        guard resourceType == "accesspoint", arn.service == "s3-object-lambda" || arn.service == "s3-outposts" || arn.service == "s3" else {
            throw AWSClient.ClientError.invalidARN
        }

        // extract bucket and path from ARN
        let resourceIDSplit = arn.resourceId.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard let bucket = resourceIDSplit.first else { throw AWSClient.ClientError.invalidARN }
        let path = String(resourceIDSplit.dropFirst().first ?? "")
        let service = String(arn.service)
        let serviceIdentifier = service != "s3" ? service : "s3-accesspoint"
        let urlHost = "\(bucket)-\(accountId).\(serviceIdentifier).\(region).\(context.serviceConfig.region.partition.dnsSuffix)"
        let request = try Self.updateRequestURL(request, host: urlHost, path: path)

        var context = context
        context.serviceConfig = AWSServiceConfig(
            region: region,
            partition: region.partition,
            serviceName: "S3",
            serviceIdentifier: serviceIdentifier,
            signingName: service,
            serviceProtocol: context.serviceConfig.serviceProtocol,
            apiVersion: context.serviceConfig.apiVersion,
            errorType: context.serviceConfig.errorType,
            xmlNamespace: context.serviceConfig.xmlNamespace,
            middleware: context.serviceConfig.middleware,
            timeout: context.serviceConfig.timeout,
            byteBufferAllocator: context.serviceConfig.byteBufferAllocator,
            options: context.serviceConfig.options
        )
        return try await next(request, context)
    }

    ///  Handle bucket names in the form of an ARN
    /// - Parameters:
    ///   - request: request
    ///   - context: request context
    ///   - next: next handler
    /// - Returns: returns response from next handler
    func handleS3ExpressBucketEndpoint(
        request: AWSHTTPRequest,
        bucket: Substring,
        path: String,
        context: AWSMiddlewareContext,
        next: AWSMiddlewareNextHandler
    ) async throws -> AWSHTTPResponse? {
        // Note this uses my own version of split (as the Swift one requires macOS 13)
        let split = bucket.split(separator: "--")
        guard split.count > 2, split.last == "x-s3" else { return nil }
        let zone = split[split.count - 2]
        let urlHost: String
        // should we use a control endpoint or a zone endpoint
        if let executionContext = Self.executionContext,
            executionContext.useS3ExpressControlEndpoint
        {
            urlHost = "s3express-control.\(context.serviceConfig.region).\(context.serviceConfig.region.partition.dnsSuffix)/\(bucket)"
        } else {
            urlHost = "\(bucket).s3express-\(zone).\(context.serviceConfig.region).\(context.serviceConfig.region.partition.dnsSuffix)"
        }
        let request = try Self.updateRequestURL(request, host: urlHost, path: path)
        var context = context
        context.serviceConfig = AWSServiceConfig(
            region: context.serviceConfig.region,
            partition: context.serviceConfig.region.partition,
            serviceName: "S3",
            serviceIdentifier: "s3",
            signingName: "s3express",
            serviceProtocol: context.serviceConfig.serviceProtocol,
            apiVersion: context.serviceConfig.apiVersion,
            errorType: context.serviceConfig.errorType,
            xmlNamespace: context.serviceConfig.xmlNamespace,
            middleware: context.serviceConfig.middleware,
            timeout: context.serviceConfig.timeout,
            byteBufferAllocator: context.serviceConfig.byteBufferAllocator,
            options: context.serviceConfig.options
        )
        return try await next(request, context)
    }

    ///  Update request with new host and path
    /// - Parameters:
    ///   - request: request
    ///   - host: new host name
    ///   - path: new path (without forward slash prefix)
    /// - Returns: new request
    static func updateRequestURL(_ request: AWSHTTPRequest, host: some StringProtocol, path: String) throws -> AWSHTTPRequest {
        var path = path
        // add trailing "/" back if it was present, no need to check for single slash path here
        if request.url.pathWithSlash.hasSuffix("/"), path.count > 0 {
            path += "/"
        }
        // add percent encoding back into path as converting from URL to String has removed it
        let percentEncodedUrlPath = Self.urlEncodePath(path)
        var urlString = "\(request.url.scheme ?? "https")://\(host)/\(percentEncodedUrlPath)"
        if let query = request.url.query {
            urlString += "?\(query)"
        }
        var request = request
        guard let url = URL(string: urlString) else {
            throw AWSClient.ClientError.invalidURL
        }
        request.url = url
        return request
    }

    static let s3PathAllowedCharacters = CharacterSet.urlPathAllowed.subtracting(.init(charactersIn: "+@()&$=:,'!*"))
    /// percent encode path value.
    private static func urlEncodePath(_ value: some StringProtocol) -> String {
        value.addingPercentEncoding(withAllowedCharacters: Self.s3PathAllowedCharacters) ?? String(value)
    }

    func createBucketFixup(request: inout AWSHTTPRequest, context: AWSMiddlewareContext) {
        switch context.operation {
        // fixup CreateBucket to include location
        case "CreateBucket":
            if request.body.isEmpty {
                var xml = ""
                if context.serviceConfig.region != .useast1 {
                    xml += "<CreateBucketConfiguration xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\">"
                    xml += "<LocationConstraint>"
                    xml += context.serviceConfig.region.rawValue
                    xml += "</LocationConstraint>"
                    xml += "</CreateBucketConfiguration>"
                }
                // TODO: pass service config down so we can use the ByteBufferAllocator
                request.body = .init(string: xml)
            }

        default:
            break
        }
    }

    func expect100Continue(request: inout AWSHTTPRequest) {
        if request.method == .PUT,
            let length = request.body.length,
            length > 128 * 1024
        {
            request.headers.replaceOrAdd(name: "Expect", value: "100-continue")
        }
    }

    func getBucketLocationResponseFixup(response: inout AWSHTTPResponse) {
        if case .byteBuffer(let buffer) = response.body.storage,
            let xmlDocument = try? XML.Document(buffer: buffer),
            let rootElement = xmlDocument.rootElement()
        {
            if rootElement.name == "LocationConstraint" {
                if rootElement.stringValue == "" {
                    rootElement.addChild(.text(stringValue: "us-east-1"))
                }
                let parentElement = XML.Element(name: "BucketLocation")
                parentElement.addChild(rootElement)
                xmlDocument.setRootElement(parentElement)
                response.body = .init(buffer: ByteBuffer(string: xmlDocument.xmlString))
            }
        }
    }

    func fixupRawError(error: AWSRawError, context: AWSMiddlewareContext) -> Error {
        if error.context.responseCode == .notFound {
            if let errorType = context.serviceConfig.errorType,
                let notFoundError = errorType.init(errorCode: "NotFound", context: error.context)
            {
                return notFoundError
            }
        }
        return error
    }
}

extension StringProtocol {
    func split(separator: some StringProtocol) -> [Self.SubSequence] {
        var split: [Self.SubSequence] = []
        var index: Self.Index = self.startIndex
        var startSplit: Self.Index = self.startIndex
        while index != self.endIndex {
            if let end = self[index...].prefixEnd(separator) {
                split.append(self[startSplit..<index])
                startSplit = end
                index = end
            } else {
                index = self.index(after: index)
            }
        }
        split.append(self[startSplit..<index])
        return split
    }

    func prefixEnd(_ prefix: some StringProtocol) -> Self.Index? {
        var prefixIndex = prefix.startIndex
        var index = self.startIndex
        while prefixIndex != prefix.endIndex {
            if self[index] != prefix[prefixIndex] {
                return nil
            }
            index = self.index(after: index)
            prefixIndex = prefix.index(after: prefixIndex)
        }
        return index
    }
}
