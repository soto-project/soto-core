//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import INIParser
import struct Foundation.Date
import class  Foundation.NSString

extension Credential {
    func isEmpty() -> Bool {
        return self.accessKeyId.isEmpty || self.secretAccessKey.isEmpty
    }
}
