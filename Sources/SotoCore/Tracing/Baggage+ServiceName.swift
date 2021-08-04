//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2021 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Baggage
import Tracing

public enum SotoServiceBaggageKey: Baggage.Key {
    public typealias Value = SotoServiceBaggage
}

public struct SotoServiceBaggage {
    public let serviceName: String
    public let databaseSystem: String?
    public let serviceAttributes: SpanAttributes

    public init(serviceName: String, serviceAttributes: SpanAttributes, databaseSystem: String?) {
        self.serviceName = serviceName
        self.serviceAttributes = serviceAttributes
        self.databaseSystem = databaseSystem
    }
}
