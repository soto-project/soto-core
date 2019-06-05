//
//  Location.swift
//  AWSSDKSwift
//
//  Created by Adam Fowler on 2019/05/18
//
public enum Location {
    case uri(locationName: String)
    case querystring(locationName: String)
    case header(locationName: String)
    case body(locationName: String)
    
    public var name: String {
        switch self {
        case .uri(locationName: let name):
            return name
        case .querystring(locationName: let name):
            return name
        case .header(locationName: let name):
            return name
        case .body(locationName: let name):
            return name
        }
    }
}

