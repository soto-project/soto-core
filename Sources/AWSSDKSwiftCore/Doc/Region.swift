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

public enum Region {
    case useast1
    case useast2
    case uswest1
    case uswest2
    case apsouth1
    case apnortheast2
    case apsoutheast1
    case apsoutheast2
    case apnortheast1
    case apeast1
    case cacentral1
    case euwest1
    case euwest3
    case euwest2
    case eucentral1
    case eunorth1
    case saeast1
    case mesouth1
    case other(String)
}

extension Region {
    
    public init(rawValue: String) {
        switch rawValue {
        case "us-east-1":
            self = .useast1
        case "us-east-2":
            self = .useast2
        case "us-west-1":
            self = .uswest1
        case "us-west-2":
            self = .uswest2
        case "ap-south-1":
            self = .apsouth1
        case "ap-northeast-2":
            self = .apnortheast2
        case "ap-southeast-1":
            self = .apsoutheast1
        case "ap-southeast-2":
            self = .apsoutheast2
        case "ap-northeast-1":
            self = .apnortheast1
        case "ap-east-1":
            self = .apeast1
        case "ca-central-1":
            self = .cacentral1
        case "eu-west-1":
            self = .euwest1
        case "eu-west-3":
            self = .euwest3
        case "eu-west-2":
            self = .euwest2
        case "eu-central-1":
            self = .eucentral1
        case "eu-north-1":
            self = .eunorth1
        case "sa-east-1":
            self = .saeast1
        case "me-south-1":
            self = .mesouth1
        default:
            self = .other(rawValue)
        }

    }
    
    public var rawValue: String {
        switch self {
        case .useast1:
            return "us-east-1"
        case .useast2:
            return "us-east-2"
        case .uswest1:
            return "us-west-1"
        case .uswest2:
            return "us-west-2"
        case .apsouth1:
            return "ap-south-1"
        case .apnortheast2:
            return "ap-northeast-2"
        case .apsoutheast1:
            return "ap-southeast-1"
        case .apsoutheast2:
            return "ap-southeast-2"
        case .apnortheast1:
            return "ap-northeast-1"
        case .apeast1:
            return "ap-east-1"
        case .cacentral1:
            return "ca-central-1"
        case .euwest1:
            return "eu-west-1"
        case .euwest3:
            return "eu-west-3"
        case .euwest2:
            return "eu-west-2"
        case .eucentral1:
            return "eu-central-1"
        case .eunorth1:
            return "eu-north-1"
        case .saeast1:
            return "sa-east-1"
        case .mesouth1:
            return "me-south-1"
        case .other(let string):
            return string
        }
    }
}

extension Region: Equatable, Hashable {
    public static func == (lhs: Region, rhs: Region) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        self.rawValue.hash(into: &hasher)
    }
}
