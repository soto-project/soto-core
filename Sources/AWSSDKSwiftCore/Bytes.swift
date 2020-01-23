//
//  Bytes.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/03/13.
//
//

extension UInt8 {
    public func hexdigest() -> String {
        return String(format: "%02x", self)
    }
}

extension Collection where Self.Iterator.Element == UInt8 {
    /// generate a hexdigest of the array of bytes
    public func hexdigest() -> String {
        return self.map({ $0.hexdigest() }).joined()
    }
}
