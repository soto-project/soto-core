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
}
