//
//  AWSShape.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/04/12.
//
//

import Foundation

public protocol AWSShape: Codable {
    static var payloadPath: String? { get }
    static var members: [AWSShapeMember] { get }
}

extension AWSShape {
    public static var payloadPath: String? {
        return nil
    }
    
    public static var members: [AWSShapeMember] {
        return []
    }
    
    public static var pathParams: [String: String] {
        var params: [String: String] = [:]
        for member in members {
            guard let location = member.location else { continue }
            if case .uri(let name) = location {
                params[name] = member.label
            }
        }
        return params
    }
    
    public static var headerParams: [String: String] {
        var params: [String: String] = [:]
        for member in members {
            guard let location = member.location else { continue }
            if case .header(let name) = location {
                params[name] = member.label
            }
        }
        return params
    }
    
    public static var queryParams: [String: String] {
        var params: [String: String] = [:]
        for member in members {
            guard let location = member.location else { continue }
            if case .querystring(let name) = location {
                params[name] = member.label
            }
        }
        return params
    }
}
