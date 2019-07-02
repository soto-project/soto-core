//
//  Body.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/04/11.
//
//

import Foundation

public enum Body {
    case text(String)
    case buffer(Data)
    case stream(InputStream) // currenty unsupported
    case multipart(Data) // currenty unsupported
    case json(Data)
    case xml(XMLNode)
    case empty
}

extension Body {
    init(anyValue: Any) {
        switch anyValue {
        case let v as Data:
            self = .buffer(v)
        default:
            self = .text("\(anyValue)")
        }
    }
    
    
    public func isJSON() -> Bool {
        switch self {
        case .json(_):
            return true
        default:
            return false
        }
    }
    
    public func isXML() -> Bool {
        switch self {
        case .xml(_):
            return true
        default:
            return false
        }
    }
    
    public func isBuffer() -> Bool {
        switch self {
        case .buffer(_):
            return true
        default:
            return false
        }
    }
    
    public func asDictionary() throws -> [String: Any]? {
        switch self {
            
        case .json(let data):
            return try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            
        default:
            return nil
        }
    }
    
    public func asData() throws -> Data? {
        switch self {
        case .text(let text):
            return text.data(using: .utf8)
            
        case .buffer(let data):
            return data
            
        case .json(let data):
            if data.isEmpty {
                return nil
            } else {
                return data
            }
            
        case .xml(let node):
            if let document = node as? XMLDocument {
                return document.xmlData
            } else if let element = node as? XMLElement {
                let xmlDocument = XMLDocument(rootElement: element)
                xmlDocument.version = "1.0"
                xmlDocument.characterEncoding = "UTF-8"
                return xmlDocument.xmlData
            }
            return nil
            
        case .multipart(_):
            return nil
            
        case .stream(_):
            return nil
            
        case .empty:
            return nil
        }
    }
}

