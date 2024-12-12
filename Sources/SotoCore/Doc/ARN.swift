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

/// Amazon Resource Name (ARN). A unique identifier assigned to AWS resource
///
/// Comes in one of the following forms
/// - arn:partition:service:region:account-id:resource-id
/// - arn:partition:service:region:account-id:resource-type/resource-id
/// - arn:partition:service:region:account-id:resource-type:resource-id
public struct ARN {
    public init?<S: StringProtocol>(string: S) where S.SubSequence == Substring {
        let split = string.split(separator: ":", omittingEmptySubsequences: false)
        guard split.count >= 6 else { return nil }
        guard split[0] == "arn" else { return nil }
        guard let partition = AWSPartition(rawValue: String(split[1])) else { return nil }
        self.partition = partition
        self.service = split[2]
        self.region = split[3].count > 0 ? Region(rawValue: String(split[3])) : nil
        if let region {
            guard region.partition == self.partition else { return nil }
        }
        self.accountId = split[4].count > 0 ? split[4] : nil
        guard self.accountId?.first(where: { !$0.isNumber }) == nil else { return nil }
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

    public let partition: AWSPartition
    public let service: Substring
    public let region: Region?
    public let accountId: Substring?
    public let resourceId: Substring
    public let resourceType: Substring?
}
