//
//  AWSMemberEncoding.swift
//
//  Created by Yuki Takei on 2017/05/18.
//
//

/// Structure defining how to serialize member of AWSShape.
/// Below is the list of possible encodings and how they are setup
/// - Encode in header (label set to member name in json model, location set to .header(header name))
/// - Encode as part of uri (label set to member name in json model, location set to .uri(uri part to replace))
/// - Encode as uri query (label set to member name in json model, location set to .querystring(query string name))
/// - While encoding a Collection as XML or query string define additional element names (label set to member name in json model,
///     shapeEncoding set to one of collection encoding types, if codingkey is different to label then set it to .body(codingkey))
/// - When encoding payload data blob (label set to member name in json model, shapeEncoding set to .blob)
public struct AWSMemberEncoding {
    
    /// Location of AWSMemberEncoding.
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
    
    /// How the AWSMemberEncoding is serialized in XML and Query formats. Used for collection elements.
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
        /// shape is stored as data blob in body
        case blob
    }
    
    /// name of member
    public let label: String
    /// where to find or place member
    public let location: Location?
    /// How shape is serialized
    public let shapeEncoding: ShapeEncoding

    public init(label: String, location: Location? = nil, encoding: ShapeEncoding = .default) {
        self.label = label
        self.location = location
        self.shapeEncoding = encoding
    }
}
