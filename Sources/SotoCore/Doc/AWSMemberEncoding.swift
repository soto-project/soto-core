//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// Structure defining where to serialize member of AWSShape.
public struct AWSMemberEncoding {
    /// Location of AWSMemberEncoding.
    public enum Location {
        case uri(locationName: String)
        case querystring(locationName: String)
        case header(locationName: String)
        case headerPrefix(prefix: String)
        case statusCode
        case body(locationName: String)
    }

    /// name of member
    public let label: String
    /// where to find or place member
    public let location: Location?

    public init(label: String, location: Location? = nil) {
        self.label = label
        self.location = location
    }
}
