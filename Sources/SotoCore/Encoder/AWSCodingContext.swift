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
    /// Container the event of an event stream is read from
    @TaskLocal public static var event: EventDecodingContainer?
}

extension Encoder {
    /// The request container of the request that is being encoded.
    ///
    /// Encoding a shape outside of ``AWSCodingContext/request`` is a programmer error and stops the program.
    @inlinable
    public var awsRequestContainer: RequestEncodingContainer {
        guard let container = AWSCodingContext.request else {
            fatalError("Encoding an AWS shape requires AWSCodingContext.request to be set")
        }
        return container
    }
}

extension Decoder {
    /// The response container of the response that is being decoded.
    ///
    /// Decoding a shape outside of ``AWSCodingContext/response`` is a programmer error and stops the program.
    @inlinable
    public var awsResponseContainer: ResponseDecodingContainer {
        guard let container = AWSCodingContext.response else {
            fatalError("Decoding an AWS shape requires AWSCodingContext.response to be set")
        }
        return container
    }

    /// The event container of the event that is being decoded.
    ///
    /// Decoding an event outside of ``AWSCodingContext/event`` is a programmer error and stops the program.
    @inlinable
    public var awsEventContainer: EventDecodingContainer {
        guard let container = AWSCodingContext.event else {
            fatalError("Decoding an AWS event requires AWSCodingContext.event to be set")
        }
        return container
    }
}
