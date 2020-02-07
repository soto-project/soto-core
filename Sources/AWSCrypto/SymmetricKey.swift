// SymmetricKey.swift
// Replicating the CryptoKit framework interface for < macOS 10.15
// written by AdamFowler 2020/01/30
#if (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))

import protocol Foundation.ContiguousBytes

/// Symmetric key object
public struct SymmetricKey: ContiguousBytes {
    let bytes: [UInt8]

    public var bitCount: Int {
        return self.bytes.count * 8
    }

    public init<D>(data: D) where D : ContiguousBytes {
        let bytes = data.withUnsafeBytes { buffer in
            return [UInt8](buffer)
        }
        self.bytes = bytes
    }
    
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        return try self.bytes.withUnsafeBytes(body)
    }
}

#endif
