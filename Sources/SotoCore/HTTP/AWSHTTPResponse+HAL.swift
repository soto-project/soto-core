//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import struct Foundation.Data
import class Foundation.JSONSerialization
import NIOCore

// AWS HAL services I know of are APIGateway, Pinpoint, Greengrass
extension AWSHTTPResponse {
    /// return if body is hypertext application language
    var isHypertextApplicationLanguage: Bool {
        guard let contentType = self.headers["content-type"].first,
              contentType.contains("hal+json")
        else {
            return false
        }
        return true
    }

    /// process hal+json data. Extract properties from HAL
    func getHypertextApplicationLanguageDictionary() throws -> Data {
        guard case .byteBuffer(let buffer) = self.body.storage else { return Data("{}".utf8) }
        // extract embedded resources from HAL
        let jsonObject = try JSONSerialization.jsonObject(with: buffer, options: [])
        guard var dictionary = jsonObject as? [String: Any] else { return Data("{}".utf8) }
        guard let embedded = dictionary["_embedded"],
              let embeddedDictionary = embedded as? [String: Any]
        else {
            return try JSONSerialization.data(withJSONObject: dictionary)
        }

        // remove _links and _embedded elements of dictionary to reduce the size of the new dictionary
        dictionary["_links"] = nil
        dictionary["_embedded"] = nil
        // merge embedded resources into original dictionary
        dictionary.merge(embeddedDictionary) { first, _ in return first }
        return try JSONSerialization.data(withJSONObject: dictionary)
    }
}
