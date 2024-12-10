//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2024 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

struct ARN {
    init?<S: StringProtocol>(string: S) where S.SubSequence == Substring {
        let split = string.split(separator: ":")
        guard split.count >= 6 else { return nil }
        guard split[0] == "arn" else { return nil }
        self.partition = split[1]
        self.service = split[2]
        self.region = split[3].count > 0 ? Region(rawValue: String(split[3])) : nil
        self.accountId = split[4].count > 0 ? split[4] : nil
        if split.count == 6 {
            let resourceSplit = split[5].split(separator: "/", maxSplits: 1)
            if resourceSplit.count == 1 {
                self.resourceType = nil
                self.resourceId = resourceSplit[0]
            } else {
                self.resourceType = resourceSplit[0]
                self.resourceId = resourceSplit[1]
            }
        } else if split.count == 7 {
            self.resourceType = split[5]
            self.resourceId = split[6]
        } else {
            return nil
        }
    }

    let partition: Substring
    let service: Substring
    let region: Region?
    let accountId: Substring?
    let resourceId: Substring
    let resourceType: Substring?
}
