//
//  TimeStamp.swift
//  AWSSDKCore
//
//  Created by Yuki Takei on 2017/10/09.
//

import Foundation

/**
 A TimeStamp Type that can be initialized from various formated value that express timestamp such as EPOC Time, Datetime String, Swift.Date instance.
*/
public struct TimeStamp {
    public let intValue: Int?
    
    public let doubleValue: Double?
    
    public let stringValue: String?
    
    public let dateValue: Date?
    
    /// Initialize from Epoc Time
    public init(_ value: Int) {
        intValue = value
        doubleValue = nil
        stringValue = nil
        dateValue = nil
    }
    
    /// Initialize from Epoc Time with millisec
    public init(_ value: Double) {
        intValue = nil
        doubleValue = value
        stringValue = nil
        dateValue = nil
    }
    
    /// Initialize from every Datetime Strings without validation.
    /// Ex. yyyy-MM-dd HH:mm:ss
    public init(_ value: String) {
        intValue = nil
        doubleValue = nil
        stringValue = value
        dateValue = nil
    }
    
    /// Initialize from Swift.Date instance
    public init(_ value: Date) {
        intValue = nil
        doubleValue = nil
        stringValue = nil
        dateValue = value
    }
}

extension TimeStamp: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let value = try? container.decode(String.self) {
            self.init(value)
        }
        else if let value = try? container.decode(Int.self) {
            self.init(value)
        }
        else if let value = try? container.decode(Double.self) {
            self.init(value)
        }
        else if let value = try? container.decode(Date.self) {
            self.init(value)
        }
        else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intValue = self.intValue {
            try container.encode(intValue)
        }
        else if let doubleValue = self.doubleValue {
            try container.encode(doubleValue)
        }
        else if let stringValue = self.stringValue {
            try container.encode(stringValue)
        }
        else if let dateValue = self.dateValue {
            try container.encode(dateValue.description)
        }
    }
}


extension TimeStamp: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }
    
    public init(unicodeScalarLiteral value: String) {
        self.init(stringLiteral: value)
    }
    
    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(stringLiteral: value)
    }
}

extension TimeStamp: ExpressibleByFloatLiteral {
    public typealias FloatLiteralType = Double
    
    public init(floatLiteral value: FloatLiteralType) {
        self.init(value)
    }
}

extension TimeStamp: ExpressibleByIntegerLiteral {
    public typealias IntegerLiteralType = Int
    
    public init(integerLiteral value: IntegerLiteralType) {
        self.init(value)
    }
}

