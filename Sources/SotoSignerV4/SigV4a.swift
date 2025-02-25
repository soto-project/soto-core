import Crypto
import Foundation

package struct SigV4aKeyPair {

    package let key: P256.Signing.PrivateKey

    package init(credential: some Credential) {
        let secretBuffer = Self.makeSecretBuffer(credential: credential)
        let secretKey = SymmetricKey(data: secretBuffer)

        var inputBuffer = Self.makeFixedInputBuffer(credential: credential, counter: 1)

        for counter in Self.KEY_DERIVATION_COUNTER_RANGE {

            // We reuse the once created buffer here over and over by just changing the counter
            // value.
            inputBuffer[inputBuffer.index(inputBuffer.endIndex, offsetBy: -5)] = counter

            let digest = HMAC<SHA256>.authenticationCode(for: inputBuffer, using: secretKey)

            let digestAsArray = [UInt8](digest)

            switch try! Self.makeDerivedKey(bytes: digestAsArray) {
            case .nextCounter:
                continue

            case .success(let key):
                self.key = key
                return
            }
        }

        fatalError("Throw error here")
    }

    package func sign(_ string: String) throws -> String {
        let signature = try self.key.signature(for: Data(string.utf8))
        return signature.withUnsafeBytes {
            String(decoding: HexEncoding($0), as: Unicode.UTF8.self)
        }
    }

    private static var KEY_DERIVATION_COUNTER_RANGE: ClosedRange<UInt8> { 1...254 }

    static func makeFixedInputBuffer(credential: some Credential, counter: UInt8) -> [UInt8] {
        guard Self.KEY_DERIVATION_COUNTER_RANGE.contains(counter) else {
            fatalError("counter must be in range: \(Self.KEY_DERIVATION_COUNTER_RANGE)")
        }

        var result = [UInt8]()
        result.reserveCapacity(32 + credential.accessKeyId.utf8.count)
        result.append(contentsOf: [0, 0, 0, 1])
        result.append(contentsOf: "AWS4-ECDSA-P256-SHA256".utf8)
        result.append(0)
        result.append(contentsOf: credential.accessKeyId.utf8)
        result.append(counter)
        result.append(contentsOf: [0, 0, 1, 0])

        return result
    }

    private static let SECRET_BUFFER_PREFIX = "AWS4A"

    static func makeSecretBuffer(credential: some Credential) -> [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity(credential.secretAccessKey.utf8.count + self.SECRET_BUFFER_PREFIX.utf8.count)
        result.append(contentsOf: self.SECRET_BUFFER_PREFIX.utf8)
        result.append(contentsOf: credential.secretAccessKey.utf8)
        return result
    }

    package static func compareConstantTime(lhs: [UInt8], rhs: [UInt8]) -> Int8 {
        guard lhs.count == rhs.count else {
            fatalError("Input arrays must be of same size")
        }

        var gt: UInt8 = 0
        var eq: UInt8 = 1
        let length = lhs.count

        for i in 0..<length {
            let lhsDigit: Int32 = Int32(lhs[i])
            let rhsDigit: Int32 = Int32(rhs[i])

            gt |= UInt8(bitPattern: Int8((rhsDigit - lhsDigit) >> 31)) & eq
            eq &= UInt8(bitPattern: Int8((((lhsDigit ^ rhsDigit) - 1) >> 31) & 0x01))
        }

        return Int8(gt) + Int8(gt) + Int8(eq) - 1
    }

    package enum DerivedKeyResult {
        case success(P256.Signing.PrivateKey)
        case nextCounter
    }

    private static let s_n_minus_2: [UInt8] = [
        0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xBC, 0xE6, 0xFA, 0xAD, 0xA7, 0x17, 0x9E, 0x84,
        0xF3, 0xB9, 0xCA, 0xC2, 0xFC, 0x63, 0x25, 0x4F,
    ]

    package static func makeDerivedKey(bytes: [UInt8]) throws -> DerivedKeyResult {
        assert(bytes.count == 32)

        let comparisonResult = Self.compareConstantTime(lhs: bytes, rhs: Self.s_n_minus_2)
        if comparisonResult > 0 {
            return .nextCounter
        }

        return try .success(P256.Signing.PrivateKey(rawRepresentation: bytes.addingOne()))
    }
}

extension Array<UInt8> {

    package mutating func addOne() {
        var carry: UInt32 = 1
        for index in self.indices.reversed() {
            var digit = UInt32(self[index])
            digit += carry
            carry = (digit >> 8) & 0x01
            self[index] = UInt8(digit & 0xFF)
        }
    }

    package consuming func addingOne() -> [UInt8] {
        var new = consume self
        new.addOne()
        return new
    }
}

package struct HexEncoding<Base: Sequence> where Base.Element == UInt8 {
    var base: Base

    package init(_ base: Base) {
        self.base = base
    }
}

extension HexEncoding: Sequence {
    package typealias Element = UInt8

    package struct Iterator: IteratorProtocol {
        package typealias Element = UInt8

        var base: Base.Iterator
        var _next: UInt8?

        init(base: Base.Iterator) {
            self.base = base
            self._next = nil
        }

        package mutating func next() -> UInt8? {
            switch self._next {
            case .none:
                guard let underlying = self.base.next() else {
                    return nil
                }
                let first = underlying >> 4
                let second = underlying & 0x0F
                self._next = second.makeBase16Ascii()
                return first.makeBase16Ascii()

            case .some(let next):
                self._next = nil
                return next
            }
        }
    }

    package func makeIterator() -> Iterator {
        Iterator(base: self.base.makeIterator())
    }
}

extension HexEncoding: Collection where Base: Collection {
    package struct Index: Comparable {
        package static func < (lhs: HexEncoding<Base>.Index, rhs: HexEncoding<Base>.Index) -> Bool {
            if lhs.base < rhs.base {
                return true
            } else if lhs.base > rhs.base {
                return false
            } else if lhs.first && !rhs.first {
                return true
            } else {
                return false
            }
        }
        
        var base: Base.Index
        var first: Bool
    }

    package var startIndex: Index {
        Index(base: self.base.startIndex, first: true)
    }

    package var endIndex: Index {
        Index(base: self.base.endIndex, first: true)
    }

    package func index(after i: Index) -> Index {
        if i.first {
            return Index(base: i.base, first: false)
        } else {
            return Index(base: self.base.index(after: i.base), first: true)
        }
    }

    package subscript(position: Index) -> UInt8 {
        let value = self.base[position.base]
        let base16 = position.first ? value >> 4 : value & 0x0F
        return base16.makeBase16Ascii()
    }
}

extension UInt8 {
    func makeBase16Ascii() -> UInt8 {
        assert(self < 16)
        if self < 10 {
            return self + UInt8(ascii: "0")
        } else {
            return self - 10 + UInt8(ascii: "a")
        }
    }
}
