// Digest.swift
// Replicating the CryptoKit framework interface for < macOS 10.15
// written by AdamFowler 2020/01/30
#if !canImport(Crypto)

import protocol Foundation.ContiguousBytes

/// Protocol for Digest object returned from HashFunction
public protocol Digest: Sequence, ContiguousBytes, Hashable where Element == UInt8 {
    static var byteCount: Int {get}
}

/// Protocol for Digest object consisting of a byte array
protocol ByteDigest: Digest, ByteArray { }

#endif
