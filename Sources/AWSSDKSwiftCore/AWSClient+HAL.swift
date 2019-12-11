import HypertextApplicationLanguage
import Foundation

extension AWSClient {
    /// process hal+json date. Extract properties from HAL
    func hypertextApplicationLanguageProcess(response: AWSResponse, members: [AWSShapeMember]) throws -> AWSResponse {
        switch response.body {
        case .json(let data):
            if (response.headers["Content-Type"] as? String)?.contains("hal+json") == true {
                let representation = try Representation.from(json: data)
                var dictionary = representation.properties
                for rel in representation.rels {
                    guard let representations = representation.representations(for: rel) else {
                        continue
                    }

                    // get member type hint
                    guard let hint = members.filter({ $0.location?.name == rel }).first else {
                        continue
                    }

                    switch hint.type {
                    case .list:
                        dictionary[rel] = representations.map({ $0.properties })

                    default:
                        dictionary[rel] = representations.map({ $0.properties }).first
                    }
                }
                var response = response
                response.body = .json(try JSONSerialization.data(withJSONObject: dictionary, options: []))
                return response
            }
        default:
            break
        }
        return response
    }
}
