//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2022 the Soto project authors
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
import SotoXML

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
public struct S3Middleware: AWSServiceMiddleware {
    public init() {}

    /// edit request before sending to S3
    public func chain(request: AWSRequest, context: AWSMiddlewareContext) throws -> AWSRequest {
        var request = request

        self.virtualAddressFixup(request: &request, context: context)
        self.createBucketFixup(request: &request)
        if !context.options.contains(.s3Disable100Continue) {
            self.expect100Continue(request: &request)
        }

        return request
    }

    /// Edit responses coming back from S3
    public func chain(response: AWSResponse, context: AWSMiddlewareContext) throws -> AWSResponse {
        var response = response

        // self.getLocationResponseFixup(response: &response)
        self.fixupHeadErrors(response: &response)

        return response
    }

    func virtualAddressFixup(request: inout AWSRequest, context: AWSMiddlewareContext) {
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
            if isAmazonUrl, context.options.contains(.s3UseTransferAcceleratedEndpoint) {
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
            if isAmazonUrl || context.options.contains(.s3ForceVirtualHost), !bucket.contains(".") {
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
            // add trailing "/" back if it was present
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

    func createBucketFixup(request: inout AWSRequest) {
        switch request.operation {
        // fixup CreateBucket to include location
        case "CreateBucket":
            var xml = ""
            if request.region != .useast1 {
                xml += "<CreateBucketConfiguration xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\">"
                xml += "<LocationConstraint>"
                xml += request.region.rawValue
                xml += "</LocationConstraint>"
                xml += "</CreateBucketConfiguration>"
            }
            request.body = .text(xml)

        default:
            break
        }
    }

    func expect100Continue(request: inout AWSRequest) {
        if request.httpMethod == .PUT,
           case .raw(let payload) = request.body,
           let size = payload.size
        {
            if size > 128 * 1024 {
                request.httpHeaders.replaceOrAdd(name: "Expect", value: "100-continue")
            }
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

    func fixupHeadErrors(response: inout AWSResponse) {
        if response.status == .notFound, response.body.length == 0 {
            let errorNode = XML.Element(name: "Error")
            let codeNode = XML.Element(name: "Code", stringValue: "NotFound")
            let messageNode = XML.Element(name: "Message", stringValue: "Not Found")
            errorNode.addChild(codeNode)
            errorNode.addChild(messageNode)
            let documentNode = XML.Document(rootElement: errorNode)
            let buffer = ByteBuffer(string: documentNode.xmlString)
            response.body = .init(buffer)
        }
    }
}
