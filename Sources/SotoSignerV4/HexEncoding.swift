//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2025 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import protocol Foundation.ContiguousBytes
#endif

@usableFromInline
package struct HexEncoding<Base: Sequence> where Base.Element == UInt8 {
    @usableFromInline
    var base: Base

    @inlinable
    package init(_ base: Base) {
        self.base = base
    }
}

extension HexEncoding: Sequence {
    @usableFromInline
    package typealias Element = UInt8

    @usableFromInline
    package struct Iterator: IteratorProtocol {
        @usableFromInline
        package typealias Element = UInt8

        @usableFromInline
        var base: Base.Iterator
        @usableFromInline
        var _next: UInt8?

        @inlinable
        init(base: Base.Iterator) {
            self.base = base
            self._next = nil
        }

        @inlinable
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

    @inlinable
    package func makeIterator() -> Iterator {
        Iterator(base: self.base.makeIterator())
    }
}

extension HexEncoding: Collection where Base: Collection {
    @usableFromInline
    package struct Index: Comparable {
        @inlinable
        init(base: Base.Index, first: Bool) {
            self.base = base
            self.first = first
        }

        @inlinable
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

        @usableFromInline
        var base: Base.Index
        @usableFromInline
        var first: Bool
    }

    @inlinable
    package var startIndex: Index {
        Index(base: self.base.startIndex, first: true)
    }

    @inlinable
    package var endIndex: Index {
        Index(base: self.base.endIndex, first: true)
    }

    @inlinable
    package func index(after i: Index) -> Index {
        if i.first {
            return Index(base: i.base, first: false)
        } else {
            return Index(base: self.base.index(after: i.base), first: true)
        }
    }

    @inlinable
    package subscript(position: Index) -> UInt8 {
        let value = self.base[position.base]
        let base16 = position.first ? value >> 4 : value & 0x0F
        return base16.makeBase16Ascii()
    }
}

extension UInt8 {
    @inlinable
    func makeBase16Ascii() -> UInt8 {
        assert(self < 16)
        if self < 10 {
            return self + UInt8(ascii: "0")
        } else {
            return self - 10 + UInt8(ascii: "a")
        }
    }
}

extension ContiguousBytes {
    /// return a hexEncoded string buffer from an array of bytes
    @_disfavoredOverload
    @_spi(SotoInternal)
    public func hexDigest() -> String {
        self.withUnsafeBytes { ptr in
            ptr.hexDigest()
        }
    }
}

extension Collection<UInt8> {
    /// return a hexEncoded string buffer from an array of bytes
    @_spi(SotoInternal)
    public func hexDigest() -> String {
        String(decoding: HexEncoding(self), as: Unicode.UTF8.self)
    }
}
