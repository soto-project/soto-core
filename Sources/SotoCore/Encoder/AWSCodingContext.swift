//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// The context a shape reads while it is encoded or decoded.
///
/// Soto sets these values around each call that encodes a request or decodes a response, error or event.
/// Shapes read them through `Encoder.awsRequestContainer` and the matching `Decoder` properties.
///
/// The values belong to the task that runs the coding call, so they reach nested shapes and no
/// coder needs to carry them. Code that encodes or decodes a shape outside Soto's own calls must
/// set them itself with `AWSCodingContext.$request.withValue(container) { ... }`, and must stay in the same
/// task: a `Task.detached` or an unstructured `Task` started inside the scope does not see them.
public enum AWSCodingContext {
    /// Container the request shape writes headers, query items, path and body into
    @TaskLocal public static var request: RequestEncodingContainer?
    /// Container the response shape reads headers, status code and body from
    @TaskLocal public static var response: ResponseDecodingContainer?
    /// Protocol of the service that is being coded
    @TaskLocal public static var serviceProtocol: ServiceProtocol?
    /// Error type of the service that is being decoded
    @TaskLocal public static var errorMap: (any (AWSErrorType & Decodable).Type)?
    /// Container the event of an event stream is read from
    @TaskLocal public static var event: EventDecodingContainer?
}

extension Encoder {
    /// The request container of the request that is being encoded.
    ///
    /// It is read from ``AWSCodingContext/request``. The encoder's `userInfo` is only consulted when that is not set.
    public var awsRequestContainer: RequestEncodingContainer? {
        AWSCodingContext.request ?? self.userInfo[.awsRequest] as? RequestEncodingContainer
    }

    /// The request container, or ``AWSClient/ClientError/missingCodingContext`` when there is none.
    public func requireAWSRequestContainer() throws -> RequestEncodingContainer {
        guard let container = self.awsRequestContainer else {
            throw AWSClient.ClientError.missingCodingContext
        }
        return container
    }
}

extension Decoder {
    /// The response container of the response that is being decoded.
    ///
    /// It is read from ``AWSCodingContext/response``. The decoder's `userInfo` is only consulted when that is not set.
    public var awsResponseContainer: ResponseDecodingContainer? {
        AWSCodingContext.response ?? self.userInfo[.awsResponse] as? ResponseDecodingContainer
    }

    /// The protocol of the service that is being decoded.
    public var awsServiceProtocol: ServiceProtocol? {
        AWSCodingContext.serviceProtocol ?? self.userInfo[.awsProtocol] as? ServiceProtocol
    }

    /// The error type of the service that is being decoded.
    public var awsErrorMap: (any (AWSErrorType & Decodable).Type)? {
        AWSCodingContext.errorMap ?? self.userInfo[.awsErrorMap] as? (any (AWSErrorType & Decodable).Type)
    }

    /// The event container of the event that is being decoded.
    public var awsEventContainer: EventDecodingContainer? {
        AWSCodingContext.event ?? self.userInfo[.awsEvent] as? EventDecodingContainer
    }

    /// The response container, or ``AWSClient/ClientError/missingCodingContext`` when there is none.
    public func requireAWSResponseContainer() throws -> ResponseDecodingContainer {
        guard let container = self.awsResponseContainer else {
            throw AWSClient.ClientError.missingCodingContext
        }
        return container
    }

    /// The event container, or ``AWSClient/ClientError/missingCodingContext`` when there is none.
    public func requireAWSEventContainer() throws -> EventDecodingContainer {
        guard let container = self.awsEventContainer else {
            throw AWSClient.ClientError.missingCodingContext
        }
        return container
    }
}
