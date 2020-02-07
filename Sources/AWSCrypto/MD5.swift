// MD5.swift
// Replicating the CryptoKit framework interface for < macOS 10.15
// written by AdamFowler 2020/01/30
#if (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))

import CommonCrypto

public extension Insecure {
    
    struct MD5Digest : ByteDigest {
        public static var byteCount: Int { return Int(CC_MD5_DIGEST_LENGTH) }
        public var bytes: [UInt8]
    }

    struct MD5: CCHashFunction {
        public typealias Digest = MD5Digest
        public static var algorithm: CCHmacAlgorithm { return CCHmacAlgorithm(kCCHmacAlgMD5) }
        var context: CC_MD5_CTX

        public static func hash(bufferPointer: UnsafeRawBufferPointer) -> Self.Digest {
            var digest: [UInt8] = .init(repeating: 0, count: Digest.byteCount)
            CC_MD5(bufferPointer.baseAddress, CC_LONG(bufferPointer.count), &digest)
            return .init(bytes: digest)
        }

        public init() {
            context = CC_MD5_CTX()
            CC_MD5_Init(&context)
        }
        
        public mutating func update(bufferPointer: UnsafeRawBufferPointer) {
            CC_MD5_Update(&context, bufferPointer.baseAddress, CC_LONG(bufferPointer.count))
        }
        
        public mutating func finalize() -> Self.Digest {
            var digest: [UInt8] = .init(repeating: 0, count: Digest.byteCount)
            CC_MD5_Final(&digest, &context)
            return .init(bytes: digest)
        }
    }
}

#endif
