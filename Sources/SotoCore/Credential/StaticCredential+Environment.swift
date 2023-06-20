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

import SotoSignerV4

public extension StaticCredential {
    /// construct static credentaisl from environment variables `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
    /// and `AWS_SESSION_TOKEN` if it exists
    static func fromEnvironment() -> StaticCredential? {
        guard let accessKeyId = Environment["AWS_ACCESS_KEY_ID"] else {
            return nil
        }
        guard let secretAccessKey = Environment["AWS_SECRET_ACCESS_KEY"] else {
            return nil
        }

        return .init(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            sessionToken: Environment["AWS_SESSION_TOKEN"]
        )
    }
}
