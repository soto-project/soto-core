//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2025 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if ServiceLifecycleSupport

import ServiceLifecycle

extension AWSClient: Service {
    public func run() async throws {
        // Ignore cancellation error
        try? await gracefulShutdown()
        try await self.shutdown()
    }
}

#endif  // ServiceLifecycleSupport
