//
//  Mirror.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/04/12.
//
//

func unwrap(any: Any) -> Any? {
    let mi = Mirror(reflecting: any)
    if mi.displayStyle != .optional {
        return any
    }
    if mi.children.count == 0 { return nil }
    let (_, some) = mi.children.first!
    return some
}

extension Mirror {
    func getAttribute(forKey key: String) -> Any? {
        guard let matched = children.filter({ $0.label == key }).first else {
            return nil
        }
        guard let value = unwrap(any: matched.value) else {
            return nil
        }
        
        return value
    }
}
