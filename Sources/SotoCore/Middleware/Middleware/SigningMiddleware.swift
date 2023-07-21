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

import Logging
import NIOHTTP1
import SotoSignerV4

/// Middleware that outputs the contents of requests being sent to AWS and the contents of the responses received.
struct AWSSigningMiddleware: AWSMiddlewareProtocol {
    let credentialProvider: any CredentialProvider

    func handle(_ request: AWSHTTPRequest, context: AWSMiddlewareContext, next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse) async throws -> AWSHTTPResponse {
        var request = request
        // get credentials
        let credential = try await self.credentialProvider.getCredential(logger: context.logger)
        // construct signer
        let signer = AWSSigner(credentials: credential, name: context.serviceConfig.signingName, region: context.serviceConfig.region.rawValue)
        request.signHeaders(signer: signer, serviceConfig: context.serviceConfig)
        return try await next(request, context)
    }
}
