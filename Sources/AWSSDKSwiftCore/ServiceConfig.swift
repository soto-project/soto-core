//
//  ServiceConfig.swift
//  AWSSDKSwiftCore
//
//  Created by Fabian Fett on 11.02.20.
//

import class Foundation.ProcessInfo

public struct ServiceConfig {
    public let region            : Region
    public let amzTarget         : String?
    public let service           : String
    public let signingName       : String
    public let serviceProtocol   : ServiceProtocol
    public let apiVersion        : String
    public let endpoint          : String
    public let serviceEndpoints  : [String: String]
    public let partitionEndpoint : String?
    public let possibleErrorTypes: [AWSErrorType.Type]
    
    init(region givenRegion: Region?,
         amzTarget         : String? = nil,
         service           : String,
         signingName       : String? = nil,
         serviceProtocol   : ServiceProtocol,
         apiVersion        : String,
         endpoint          : String? = nil,
         serviceEndpoints  : [String: String] = [:],
         partitionEndpoint : String? = nil,
         possibleErrorTypes: [AWSErrorType.Type]? = nil)
    {
        if let _region = givenRegion {
            region = _region
        } else if let partitionEndpoint = partitionEndpoint, let reg = Region(rawValue: partitionEndpoint) {
            region = reg
        } else if let defaultRegion = ProcessInfo.processInfo.environment["AWS_DEFAULT_REGION"], let reg = Region(rawValue: defaultRegion) {
            region = reg
        } else {
            region = .useast1
        }

        self.apiVersion         = apiVersion
        self.service            = service
        self.signingName        = signingName ?? service
        self.amzTarget          = amzTarget
        self.serviceProtocol    = serviceProtocol
        self.serviceEndpoints   = serviceEndpoints
        self.partitionEndpoint  = partitionEndpoint
        self.possibleErrorTypes = possibleErrorTypes ?? []

        // work out endpoint, if provided use that otherwise
        if let endpoint = endpoint {
            self.endpoint = endpoint
        } else {
            let serviceHost: String
            if let serviceEndpoint = serviceEndpoints[region.rawValue] {
                serviceHost = serviceEndpoint
            } else if let partitionEndpoint = partitionEndpoint, let globalEndpoint = serviceEndpoints[partitionEndpoint] {
                serviceHost = globalEndpoint
            } else {
                serviceHost = "\(service).\(region.rawValue).amazonaws.com"
            }
            self.endpoint = "https://\(serviceHost)"
        }
    }
}
