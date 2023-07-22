//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Crypto
import Foundation
@_implementationOnly import SotoXML

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
    public func handle(_ request: AWSHTTPRequest, context: AWSMiddlewareContext, next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse) async throws -> AWSHTTPResponse {
        var request = request

        self.virtualAddressFixup(request: &request, context: context)
        self.createBucketFixup(request: &request, context: context)
        if !context.serviceConfig.options.contains(.s3Disable100Continue) {
            self.expect100Continue(request: &request)
        }

        do {
            let response = try await next(request, context)
            return response
        } catch let error as AWSRawError {
            let newError = self.fixupRawError(error: error, context: context)
            throw newError
        }
    }

    public init() {}

    func virtualAddressFixup(request: inout AWSHTTPRequest, context: AWSMiddlewareContext) {
        /// process URL into form ${bucket}.s3.amazon.com
        let paths = request.url.path.split(separator: "/", omittingEmptySubsequences: true)
        if paths.count > 0 {
            guard var host = request.url.host else { return }
            if let port = request.url.port {
                host = "\(host):\(port)"
            }
            let bucket = paths[0]
            var urlPath: String
            var urlHost: String
            let isAmazonUrl = host.hasSuffix("amazonaws.com")

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

            // if host name contains amazonaws.com and bucket name doesn't contain a period do virtual address look up
            if isAmazonUrl || context.serviceConfig.options.contains(.s3ForceVirtualHost), !bucket.contains(".") {
                let pathsWithoutBucket = paths.dropFirst() // bucket
                urlPath = pathsWithoutBucket.joined(separator: "/")

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
            // add trailing "/" back if it was present, no need to check for single slash path here
            if request.url.pathWithSlash.hasSuffix("/") {
                urlPath += "/"
            }
            // add percent encoding back into path as converting from URL to String has removed it
            let percentEncodedUrlPath = Self.urlEncodePath(urlPath)
            var urlString = "\(request.url.scheme ?? "https")://\(urlHost)/\(percentEncodedUrlPath)"
            if let query = request.url.query {
                urlString += "?\(query)"
            }
            request.url = URL(string: urlString)!
        }
    }

    static let s3PathAllowedCharacters = CharacterSet.urlPathAllowed.subtracting(.init(charactersIn: "+@()&$=:,'!*"))
    /// percent encode path value.
    private static func urlEncodePath(_ value: String) -> String {
        return value.addingPercentEncoding(withAllowedCharacters: Self.s3PathAllowedCharacters) ?? value
    }

    func createBucketFixup(request: inout AWSHTTPRequest, context: AWSMiddlewareContext) {
        switch context.operation {
        // fixup CreateBucket to include location
        case "CreateBucket":
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

    // TODO: Find way to do getLocationResponseFixup
    /* func getLocationResponseFixup(response: inout AWSResponse) {
         if case .xml(let element) = response.body {
             // GetBucketLocation comes back without a containing xml element
             if element.name == "LocationConstraint" {
                 if element.stringValue == "" {
                     element.addChild(.text(stringValue: "us-east-1"))
                 }
                 let parentElement = XML.Element(name: "BucketLocation")
                 parentElement.addChild(element)
                 response.body = .xml(parentElement)
             }
         }
     } */

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
