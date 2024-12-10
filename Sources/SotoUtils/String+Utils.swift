#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension String {

    package func addingPercentEncoding(utf8Buffer: some Collection<UInt8>, allowedCharacters: Set<UInt8>) -> String {
        let maxLength = utf8Buffer.count * 3
        let result = withUnsafeTemporaryAllocation(of: UInt8.self, capacity: maxLength + 1) { _buffer in
            var buffer = OutputBuffer(initializing: _buffer.baseAddress!, capacity: _buffer.count)
            for v in utf8Buffer {
                if allowedCharacters.contains(v) {
                    buffer.appendElement(v)
                } else {
                    buffer.appendElement(UInt8(ascii: "%"))
                    buffer.appendElement(hexToAscii(v >> 4))
                    buffer.appendElement(hexToAscii(v & 0xF))
                }
            }
            buffer.appendElement(0) // NULL-terminated
            let initialized = buffer.relinquishBorrowedMemory()
            return String(cString: initialized.baseAddress!)
        }
        return result
    }

    private func hexToAscii(_ hex: UInt8) -> UInt8 {
        switch hex {
        case 0x0:
            return UInt8(ascii: "0")
        case 0x1:
            return UInt8(ascii: "1")
        case 0x2:
            return UInt8(ascii: "2")
        case 0x3:
            return UInt8(ascii: "3")
        case 0x4:
            return UInt8(ascii: "4")
        case 0x5:
            return UInt8(ascii: "5")
        case 0x6:
            return UInt8(ascii: "6")
        case 0x7:
            return UInt8(ascii: "7")
        case 0x8:
            return UInt8(ascii: "8")
        case 0x9:
            return UInt8(ascii: "9")
        case 0xA:
            return UInt8(ascii: "A")
        case 0xB:
            return UInt8(ascii: "B")
        case 0xC:
            return UInt8(ascii: "C")
        case 0xD:
            return UInt8(ascii: "D")
        case 0xE:
            return UInt8(ascii: "E")
        case 0xF:
            return UInt8(ascii: "F")
        default:
            fatalError("Invalid hex digit: \(hex)")
        }
    }

    private func asciiToHex(_ ascii: UInt8) -> UInt8? {
        switch ascii {
        case UInt8(ascii: "0"):
            return 0x0
        case UInt8(ascii: "1"):
            return 0x1
        case UInt8(ascii: "2"):
            return 0x2
        case UInt8(ascii: "3"):
            return 0x3
        case UInt8(ascii: "4"):
            return 0x4
        case UInt8(ascii: "5"):
            return 0x5
        case UInt8(ascii: "6"):
            return 0x6
        case UInt8(ascii: "7"):
            return 0x7
        case UInt8(ascii: "8"):
            return 0x8
        case UInt8(ascii: "9"):
            return 0x9
        case UInt8(ascii: "A"), UInt8(ascii: "a"):
            return 0xA
        case UInt8(ascii: "B"), UInt8(ascii: "b"):
            return 0xB
        case UInt8(ascii: "C"), UInt8(ascii: "c"):
            return 0xC
        case UInt8(ascii: "D"), UInt8(ascii: "d"):
            return 0xD
        case UInt8(ascii: "E"), UInt8(ascii: "e"):
            return 0xE
        case UInt8(ascii: "F"), UInt8(ascii: "f"):
            return 0xF
        default:
            return nil
        }
    }

    package func addingPercentEncoding(allowedCharacters: Set<UInt8>) -> String {
        let maybeResult = self.utf8.withContiguousStorageIfAvailable { utf8Buffer in
            return self.addingPercentEncoding(utf8Buffer: utf8Buffer, allowedCharacters: allowedCharacters)
        }
        if let result = maybeResult {
            return result
        }
        return addingPercentEncoding(allowedCharacters: allowedCharacters)
    }

    package func queryEncode() -> String {
        let result =  addingPercentEncoding(allowedCharacters: String.queryAllowedCharacters)
        print("queryEncode: \(self) -> \(result)")
        return result
    }

    package func s3PathEncode() -> String {
        return addingPercentEncoding(allowedCharacters: String.s3PathAllowedCharacters)
    }

    package func uriEncode() -> String {
        return addingPercentEncoding(allowedCharacters: String.uriAllowedCharacters)
    }

    package func uriEncodeWithSlash() -> String {
        return addingPercentEncoding(allowedCharacters: String.uriAllowedWithSlashCharacters)
    }
    
    package static let s3PathAllowedCharacters : Set<UInt8> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/!*'()".utf8)
    package static let uriAllowedWithSlashCharacters :Set<UInt8> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/".utf8)
    package static let uriAllowedCharacters :Set<UInt8> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)
    package static let queryAllowedCharacters : Set<UInt8> = Set(0 ... .max).subtracting("/;+".utf8)
}

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

struct OutputBuffer<T>: ~Copyable // ~Escapable
{
    let start: UnsafeMutablePointer<T>
    let capacity: Int
    var initialized: Int = 0

    deinit {
        // `self` always borrows memory, and it shouldn't have gotten here.
        // Failing to use `relinquishBorrowedMemory()` is an error.
        if initialized > 0 {
            fatalError()
        }
    }

    // precondition: pointer points to uninitialized memory for count elements
    init(initializing: UnsafeMutablePointer<T>, capacity: Int) {
        start = initializing
        self.capacity = capacity
    }
}

extension OutputBuffer {
   mutating func appendElement(_ value: T) {
        precondition(initialized < capacity, "Output buffer overflow")
        start.advanced(by: initialized).initialize(to: value)
        initialized &+= 1
    }

    mutating func deinitializeLastElement() -> T? {
        guard initialized > 0 else { return nil }
        initialized &-= 1
        return start.advanced(by: initialized).move()
    }
}

extension OutputBuffer {
    mutating func deinitialize() {
        let b = UnsafeMutableBufferPointer(start: start, count: initialized)
        b.deinitialize()
        initialized = 0
    }
}

extension OutputBuffer {
    mutating func append<S>(
        from elements: S
    ) -> S.Iterator where S: Sequence, S.Element == T {
        var iterator = elements.makeIterator()
        append(from: &iterator)
        return iterator
    }

    mutating func append(
        from elements: inout some IteratorProtocol<T>
    ) {
        while initialized < capacity {
            guard let element = elements.next() else { break }
            start.advanced(by: initialized).initialize(to: element)
            initialized &+= 1
        }
    }

    mutating func append(
        fromContentsOf source: some Collection<T>
    ) {
        let count = source.withContiguousStorageIfAvailable {
            guard let sourceAddress = $0.baseAddress, !$0.isEmpty else {
                return 0
            }
            let available = capacity &- initialized
            precondition(
                $0.count <= available,
                "buffer cannot contain every element from source."
            )
            let tail = start.advanced(by: initialized)
            tail.initialize(from: sourceAddress, count: $0.count)
            return $0.count
        }
        if let count {
            initialized &+= count
            return
        }

        let available = capacity &- initialized
        let tail = start.advanced(by: initialized)
        let suffix = UnsafeMutableBufferPointer(start: tail, count: available)
        var (iterator, copied) = source._copyContents(initializing: suffix)
        precondition(
            iterator.next() == nil,
            "buffer cannot contain every element from source."
        )
        assert(initialized + copied <= capacity)
        initialized &+= copied
    }

    mutating func moveAppend(
        fromContentsOf source: UnsafeMutableBufferPointer<T>
    ) {
        guard let sourceAddress = source.baseAddress, !source.isEmpty else {
            return
        }
        let available = capacity &- initialized
        precondition(
            source.count <= available,
            "buffer cannot contain every element from source."
        )
        let tail = start.advanced(by: initialized)
        tail.moveInitialize(from: sourceAddress, count: source.count)
        initialized &+= source.count
    }

    mutating func moveAppend(
        fromContentsOf source: Slice<UnsafeMutableBufferPointer<T>>
    ) {
        moveAppend(fromContentsOf: UnsafeMutableBufferPointer(rebasing: source))
    }
}

extension OutputBuffer<UInt8> /* where T: BitwiseCopyable */ {

    mutating func appendBytes<Value /*: BitwiseCopyable */>(
        of value: borrowing Value, as: Value.Type
    ) {
        precondition(_isPOD(Value.self))
        let (q,r) = MemoryLayout<Value>.stride.quotientAndRemainder(
            dividingBy: MemoryLayout<T>.stride
        )
        precondition(
            r == 0, "Stride of Value must be divisible by stride of Element"
        )
        precondition(
            (capacity &- initialized) >= q,
            "buffer cannot contain every byte of value."
        )
        let p = UnsafeMutableRawPointer(start.advanced(by: initialized))
        p.storeBytes(of: value, as: Value.self)
        initialized &+= q
    }
}

extension OutputBuffer {

    consuming func relinquishBorrowedMemory() -> UnsafeMutableBufferPointer<T> {
        let start = self.start
        let initialized = self.initialized
        discard self
        return .init(start: start, count: initialized)
    }
}

extension String {

    // also see https://github.com/apple/swift/pull/23050
    // and `final class __SharedStringStorage`

    init(
        utf8Capacity capacity: Int,
        initializingWith initializer: (inout OutputBuffer<UInt8>) throws -> Void
    ) rethrows {
        try self.init(
            unsafeUninitializedCapacity: capacity,
            initializingUTF8With: { buffer in
                var output = OutputBuffer(
                    initializing: buffer.baseAddress.unsafelyUnwrapped,
                    capacity: capacity
                )
                do {
                    try initializer(&output)
                    let initialized = output.relinquishBorrowedMemory()
                    assert(initialized.baseAddress == buffer.baseAddress)
                    return initialized.count
                } catch {
                    // Do this regardless of outcome
                    _ = output.relinquishBorrowedMemory()
                    throw error
                }
            }
        )
    }
}

extension Data {

    init(
        capacity: Int,
        initializingWith initializer: (inout OutputBuffer<UInt8>) throws -> Void
    ) rethrows {
        self = Data(count: capacity) // initialized with zeroed buffer
        let count = try self.withUnsafeMutableBytes { rawBuffer in
            try rawBuffer.withMemoryRebound(to: UInt8.self) { buffer in
                buffer.deinitialize()
                var output = OutputBuffer(
                    initializing: buffer.baseAddress.unsafelyUnwrapped,
                    capacity: capacity
                )
                do {
                    try initializer(&output)
                    let initialized = output.relinquishBorrowedMemory()
                    assert(initialized.baseAddress == buffer.baseAddress)
                    buffer[initialized.count..<buffer.count].initialize(repeating: 0)
                    return initialized.count
                } catch {
                    // Do this regardless of outcome
                    _ = output.relinquishBorrowedMemory()
                    throw error
                }
            }
        }
        assert(count <= self.count)
        self.replaceSubrange(count..<self.count, with: EmptyCollection())
    }
}





extension RangeReplaceableCollection {
    package func trimming(while predicate: (Element) -> Bool) -> SubSequence {
        var idx = startIndex
        while idx < endIndex && predicate(self[idx]) {
            formIndex(after: &idx)
        }

        let startOfNonTrimmedRange = idx // Points at the first char not in the set
        guard startOfNonTrimmedRange != endIndex else {
            return self[endIndex...]
        }

        let beforeEnd = index(endIndex, offsetBy: -1)
        guard startOfNonTrimmedRange < beforeEnd else {
            return self[startOfNonTrimmedRange ..< endIndex]
        }

        var backIdx = beforeEnd
        // No need to bound-check because we've already trimmed from the beginning, so we'd definitely break off of this loop before `backIdx` rewinds before `startIndex`
        while predicate(self[backIdx]) {
            formIndex(&backIdx, offsetBy: -1)
        }
        return self[startOfNonTrimmedRange ... backIdx]
    }
}