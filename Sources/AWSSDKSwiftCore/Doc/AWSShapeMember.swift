//
//  AWSShapeProperty.swift
//  Hexaville
//
//  Created by Yuki Takei on 2017/05/18.
//
//

import Foundation

public enum CollectionEncoding {
    case `default`
    case flatList
    case list(member: String)
    case flatMap(key: String, value: String)
    case map(entry: String, key: String, value: String)
}

public struct AWSShapeMember {
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
    
    public let label: String
    public let location: Location?
    public let required: Bool
    public let type: Shape
    public let collectionEncoding: CollectionEncoding

    var pathForLocation: String {
        return location?.name ?? label
    }
    
    public init(label: String, location: Location? = nil, required: Bool, type: Shape, encoding: CollectionEncoding = .default) {
        self.label = label
        self.location = location
        self.required = required
        self.type = type
        self.collectionEncoding = encoding
    }
}
