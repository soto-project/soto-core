//
//  JSONSerializable.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/03/23.
//
//

import Foundation

private func dquote(_ str: String) -> String {
    return "\"\(str)\""
}

private func _serialize(value: Any) throws -> String {
    var s = ""
    switch value {
    case let dict as [String: Any]:
        s += try "{" + _serialize(dictionary: dict) + "}"
        
    case let elements as [Any]:
        s += try _serialize(array: elements)
        
    case let v as Int:
        s += "\(v)"
        
    case let v as Int8:
        s += "\(v)"
        
    case let v as Int16:
        s += "\(v)"
        
    case let v as Int32:
        s += "\(v)"
        
    case let v as Int64:
        s += "\(v)"
        
    case let v as UInt:
        s += "\(v)"
        
    case let v as UInt8:
        s += "\(v)"
        
    case let v as UInt16:
        s += "\(v)"
        
    case let v as UInt32:
        s += "\(v)"
        
    case let v as UInt64:
        s += "\(v)"
        
    case let v as Float:
        s += "\(v)"
        
    case let v as Float64:
        s += "\(v)"
        
    case let v as Float80:
        s += "\(v)"
        
    case let v as Double:
        s += "\(v)"
        
    case let v as Bool:
        s += "\(v)".lowercased()
        
    case let v as Data:
        s += dquote(v.base64EncodedString())
        
    default:
        s += dquote("\(value)")
    }
    
    return s
}

private func _serialize(array: [Any]) throws -> String {
    var s = ""
    for (index, item) in array.enumerated() {
        s += try _serialize(value: item)
        if array.count - index > 1 { s += ", " }
    }
    return "[" + s + "]"
}

private func _serialize(dictionary: [String: Any]) throws -> String {
    var s = ""
    for (offset: index, element: (key: key, value: value)) in dictionary.enumerated() {
        s += dquote(key)+": "
        s += try _serialize(value: value)
        if dictionary.count - index > 1 { s += ", " }
    }
    return s
}

public struct JSONSerializer {
    public static func serialize(_ dictionary: [String: Any]) throws -> Data {
        let jsonString = try "{" + _serialize(dictionary: dictionary) + "}"
        return jsonString.data(using: .utf8) ?? Data()
    }
}
