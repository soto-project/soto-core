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

/// Endpoint variant types
public struct EndpointVariantType: OptionSet {
    public typealias RawValue = Int
    public let rawValue: Int

    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }

    public static let fips: Self = .init(rawValue: AWSServiceConfig.Options.useFipsEndpoint.rawValue)
    public static let dualstack: Self = .init(rawValue: AWSServiceConfig.Options.useDualStackEndpoint.rawValue)

    public static let all: Self = [.fips, .dualstack]
}

/// extend AWSServiceConfig options to generate endpoint variant options
extension AWSServiceConfig.Options {
    var endpointVariant: EndpointVariantType {
        .init(rawValue: self.rawValue).intersection(EndpointVariantType.all)
    }
}
