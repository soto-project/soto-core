//
//  JSONSerializer.swift
//  AWSSDKSwiftCorePackageDescription
//
//  Created by Yuki Takei on 2017/10/08.
//

import Foundation

struct JSONSerializer {
    func serializeToDictionary(_ data: Data) throws -> [String: Any] {
        return try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] ?? [:]
    }
    
    func serializeToFlatDictionary(_ data: Data) throws -> [String: Any] {
        func flatten(dictionary: [String: Any]) -> [String: Any] {
            var flatted: [String: Any] = [:]
            
            func destructiveFlatten(dictionary: [String: Any]) {
                for (key, value) in dictionary {
                    switch value {
                    case let value as [String: Any]:
                        for (key2, value2) in flatten(dictionary: value) {
                            switch value2 {
                            case let value2 as [String: Any]:
                                destructiveFlatten(dictionary: value2)
                                
                            case let values as [Any]: // TODO: values<Element> might be dictionary...
                                for iterator in values.enumerated() {
                                    flatted["\(key).member.\(iterator.offset+1)"] = iterator.element
                                }
                                
                            default:
                                flatted["\(key).\(key2)"] = value2
                            }
                        }
                        
                    case let values as [Any]: // TODO: values<Element> might be dictionary...
                        for iterator in values.enumerated() {
                            flatted["\(key).member.\(iterator.offset+1)"] = iterator.element
                        }
                        
                    default:
                        flatted[key] = value
                    }
                }
            }
            
            destructiveFlatten(dictionary: dictionary)
            
            return flatted
        }
        
        return flatten(dictionary: try serializeToDictionary(data))
    }
}
