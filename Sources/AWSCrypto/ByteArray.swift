// ByteArray.swift
// Replicating the CryptoKit framework interface for < macOS 10.15
// written by AdamFowler 2020/01/30
#if (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))

import protocol Foundation.ContiguousBytes

/// Protocol for object encapsulating an array of bytes
protocol ByteArray: Sequence, ContiguousBytes, Hashable where Element == UInt8 {
    init(bytes: [UInt8])
    var bytes: [UInt8] { get set }
}

extension ByteArray {
    public func makeIterator() -> Array<UInt8>.Iterator {
        return self.bytes.makeIterator()
    }

    public init?(bufferPointer: UnsafeRawBufferPointer) {
        self.init(bytes: [UInt8](bufferPointer))
    }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        return try bytes.withUnsafeBytes(body)
    }
}

#endif
