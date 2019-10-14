//
//  AWSShapeProperty.swift
//  Hexaville
//
//  Created by Yuki Takei on 2017/05/18.
//
//

import Foundation

/// Structure defining how to serialize member of AWSShape.
public struct AWSShapeMember {
    /// Type of AWSShapeMember
    public indirect enum Shape {
        case structure
        case `enum`
        case map
        case list
        case string
        case integer
        case blob
        case long
        case double
        case float
        case boolean
        case timestamp
        case any
    }
    
    /// Location of AWSShapeMember.
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
    
    /// How the AWSShapeMember is serialized in XML and Query formats. Used for collection elements.
    public enum ShapeEncoding {
        /// default case, flat arrays and serializing dictionaries like all other codable structures
        case `default`
        /// encode array as multiple entries all with same name
        case flatList
        /// encode array as multiple entries all with same name, enclosed by element `member`
        case list(member: String)
        /// encode dictionary with multiple pairs of `key` and `value` entries
        case flatMap(key: String, value: String)
        /// encode dictionary with multiple pairs of `key` and `value` entries, enclosed by element `entry`
        case map(entry: String, key: String, value: String)
    }
    
    /// name of member
    public let label: String
    /// where to find or place member
    public let location: Location?
    /// Is this member required
    public let required: Bool
    /// Type of shape member is
    public let type: Shape
    /// How shape is serialized
    public let shapeEncoding: ShapeEncoding

    public init(label: String, location: Location? = nil, required: Bool, type: Shape, encoding: ShapeEncoding = .default) {
        self.label = label
        self.location = location
        self.required = required
        self.type = type
        self.shapeEncoding = encoding
    }
}
