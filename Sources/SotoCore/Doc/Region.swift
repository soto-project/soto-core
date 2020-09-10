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

// THIS FILE IS AUTOMATICALLY GENERATED by https://github.com/soto-project/soto-core/scripts/generate-region.swift. DO NOT EDIT.

public struct Region: RawRepresentable, Equatable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    // Africa (Cape Town)
    public static var afsouth1: Region { .init(rawValue: "af-south-1") }
    // Asia Pacific (Hong Kong)
    public static var apeast1: Region { .init(rawValue: "ap-east-1") }
    // Asia Pacific (Tokyo)
    public static var apnortheast1: Region { .init(rawValue: "ap-northeast-1") }
    // Asia Pacific (Seoul)
    public static var apnortheast2: Region { .init(rawValue: "ap-northeast-2") }
    // Asia Pacific (Osaka Local)
    public static var apnortheast3: Region { .init(rawValue: "ap-northeast-3") }
    // Asia Pacific (Mumbai)
    public static var apsouth1: Region { .init(rawValue: "ap-south-1") }
    // Asia Pacific (Singapore)
    public static var apsoutheast1: Region { .init(rawValue: "ap-southeast-1") }
    // Asia Pacific (Sydney)
    public static var apsoutheast2: Region { .init(rawValue: "ap-southeast-2") }
    // Canada (Central)
    public static var cacentral1: Region { .init(rawValue: "ca-central-1") }
    // China (Beijing)
    public static var cnnorth1: Region { .init(rawValue: "cn-north-1") }
    // China (Ningxia)
    public static var cnnorthwest1: Region { .init(rawValue: "cn-northwest-1") }
    // Europe (Frankfurt)
    public static var eucentral1: Region { .init(rawValue: "eu-central-1") }
    // Europe (Stockholm)
    public static var eunorth1: Region { .init(rawValue: "eu-north-1") }
    // Europe (Milan)
    public static var eusouth1: Region { .init(rawValue: "eu-south-1") }
    // Europe (Ireland)
    public static var euwest1: Region { .init(rawValue: "eu-west-1") }
    // Europe (London)
    public static var euwest2: Region { .init(rawValue: "eu-west-2") }
    // Europe (Paris)
    public static var euwest3: Region { .init(rawValue: "eu-west-3") }
    // Middle East (Bahrain)
    public static var mesouth1: Region { .init(rawValue: "me-south-1") }
    // South America (Sao Paulo)
    public static var saeast1: Region { .init(rawValue: "sa-east-1") }
    // US East (N. Virginia)
    public static var useast1: Region { .init(rawValue: "us-east-1") }
    // US East (Ohio)
    public static var useast2: Region { .init(rawValue: "us-east-2") }
    // AWS GovCloud (US-East)
    public static var usgoveast1: Region { .init(rawValue: "us-gov-east-1") }
    // AWS GovCloud (US-West)
    public static var usgovwest1: Region { .init(rawValue: "us-gov-west-1") }
    // US ISO East
    public static var usisoeast1: Region { .init(rawValue: "us-iso-east-1") }
    // US ISOB East (Ohio)
    public static var usisobeast1: Region { .init(rawValue: "us-isob-east-1") }
    // US West (N. California)
    public static var uswest1: Region { .init(rawValue: "us-west-1") }
    // US West (Oregon)
    public static var uswest2: Region { .init(rawValue: "us-west-2") }
    // other region
    public static func other(_ name: String) -> Region { .init(rawValue: name) }
}

extension Region {
    public var partition: AWSPartition {
        switch self {
        case .afsouth1: return .aws
        case .apeast1: return .aws
        case .apnortheast1: return .aws
        case .apnortheast2: return .aws
        case .apnortheast3: return .aws
        case .apsouth1: return .aws
        case .apsoutheast1: return .aws
        case .apsoutheast2: return .aws
        case .cacentral1: return .aws
        case .cnnorth1: return .awscn
        case .cnnorthwest1: return .awscn
        case .eucentral1: return .aws
        case .eunorth1: return .aws
        case .eusouth1: return .aws
        case .euwest1: return .aws
        case .euwest2: return .aws
        case .euwest3: return .aws
        case .mesouth1: return .aws
        case .saeast1: return .aws
        case .useast1: return .aws
        case .useast2: return .aws
        case .usgoveast1: return .awsusgov
        case .usgovwest1: return .awsusgov
        case .usisoeast1: return .awsiso
        case .usisobeast1: return .awsisob
        case .uswest1: return .aws
        case .uswest2: return .aws
        default: return .aws
        }
    }
}

public struct AWSPartition: RawRepresentable, Equatable, Hashable {
    enum InternalPartition: String {
        case aws
        case awscn
        case awsusgov
        case awsiso
        case awsisob
    }

    private var partition: InternalPartition

    public var rawValue: String { return self.partition.rawValue }

    public init?(rawValue: String) {
        guard let partition = InternalPartition(rawValue: rawValue) else { return nil }
        self.partition = partition
    }

    private init(partition: InternalPartition) {
        self.partition = partition
    }

    // AWS Standard
    public static var aws: AWSPartition { .init(partition: .aws) }
    // AWS China
    public static var awscn: AWSPartition { .init(partition: .awscn) }
    // AWS GovCloud (US)
    public static var awsusgov: AWSPartition { .init(partition: .awsusgov) }
    // AWS ISO (US)
    public static var awsiso: AWSPartition { .init(partition: .awsiso) }
    // AWS ISOB (US)
    public static var awsisob: AWSPartition { .init(partition: .awsisob) }
}

extension AWSPartition {
    public var dnsSuffix: String {
        switch self.partition {
        case .aws: return "amazonaws.com"
        case .awscn: return "amazonaws.com.cn"
        case .awsusgov: return "amazonaws.com"
        case .awsiso: return "c2s.ic.gov"
        case .awsisob: return "sc2s.sgov.gov"
        }
    }
}
