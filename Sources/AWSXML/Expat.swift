//
//  Expat.swift
//  SwiftyExpat
//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

//
//  Created by Helge Heß on 7/15/14.
//  Copyright (c) 2014-2018 Always Right Institute. All rights reserved.
//

import Expat

/// Simple wrapper for the Expat parser. Though the block based Expat is
/// reasonably easy to use as-is.
///
/// Done as a class as this is no value object (and struct's have no deinit())
///
/// Sample:
///  let p = Expat()
///    .onStartElement   { name, attrs in println("<\(name) \(attrs)")       }
///    .onEndElement     { name        in println(">\(name)")                }
///    .onError          { error       in println("ERROR: \(error)")         }
///  p.write("<hello>world</hello>")
///  p.close()
public final class Expat {
    public let nsSeparator: Character

    var parser: XML_Parser
    var isClosed = false

    public init(encoding: String = "UTF-8", nsSeparator: Character = "<") throws {
        self.nsSeparator = nsSeparator
        let sepUTF8 = ("" + String(self.nsSeparator)).utf8
        let separator = sepUTF8[sepUTF8.startIndex]

        guard let parser = encoding.withCString( { cs in
            // if I use parser, swiftc crashes (if Expat is a class)
            // FIXME: use String for separator, and codepoints to get the Int?
            XML_ParserCreateNS(cs, XML_Char(separator))
        }) else {
            throw XML_ERROR_NO_MEMORY
        }
        self.parser = parser

        // TBD: what is the better way to do this?
        let ud = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)
        XML_SetUserData(parser, ud)

        registerCallbacks()
    }

    deinit {
        XML_ParserFree(parser)
    }

    /// feed the parser
    public func feedRaw(_ cs: UnsafePointer<CChar>, final: Bool = false) throws -> ExpatResult {
        // v4: for some reason this accepts a 'String', but for such it doesn't
        //     actually work
        let cslen = strlen(cs) // cs? checks for a NULL C string
        let isFinal: Int32 = final ? 1 : 0

        // dumpCharBuf(cs, Int(cslen))
        let status: XML_Status = XML_Parse(parser, cs, Int32(cslen), isFinal)

        switch status { // the Expat enum's don't work?
        case XML_STATUS_OK: return ExpatResult.OK
        case XML_STATUS_SUSPENDED: return ExpatResult.Suspended
        default:
            let error = XML_GetErrorCode(parser)
            if let cb = cbError {
                cb(error)
            }
            throw error
        }
    }

    public func feed(_ s: String, final: Bool = false) throws -> ExpatResult {
        return try s.withCString { cs -> ExpatResult in
            return try self.feedRaw(cs, final: final)
        }
    }

    public func close() throws -> ExpatResult {
        return try self.feed("", final: true)
    }

    func registerCallbacks() {
        XML_SetStartElementHandler(self.parser) { ud, name, attrs in
            let me = unsafeBitCast(ud, to: Expat.self)
            guard let cb = me.cbStartElement else { return }
            let sName = name != nil ? String(cString: name!) : ""

            // FIXME: we should not copy stuff, but have a wrapper which works on the
            //        attrs structure 'on demand'
            let sAttrs = makeAttributesDictionary(attrs)
            cb(sName, sAttrs)
        }

        XML_SetEndElementHandler(self.parser) { ud, name in
            let me = unsafeBitCast(ud, to: Expat.self)
            guard let cb = me.cbEndElement else { return }
            let sName = String(cString: name!) // force unwrap, must be set
            cb(sName)
        }

        XML_SetStartNamespaceDeclHandler(self.parser) { ud, prefix, uri in
            let me = unsafeBitCast(ud, to: Expat.self)
            guard let cb = me.cbStartNS else { return }
            let sPrefix = prefix != nil ? String(cString: prefix!) : nil
            let sURI = String(cString: uri!)
            cb(sPrefix, sURI)
        }
        XML_SetEndNamespaceDeclHandler(self.parser) { ud, prefix in
            let me = unsafeBitCast(ud, to: Expat.self)
            guard let cb = me.cbEndNS else { return }
            let sPrefix = prefix != nil ? String(cString: prefix!) : nil
            cb(sPrefix)
        }

        XML_SetCharacterDataHandler(self.parser) { ud, cs, cslen in
            assert(cslen > 0)
            assert(cs != nil)
            guard cslen > 0 else { return }

            let me = unsafeBitCast(ud, to: Expat.self)
            guard let cb = me.cbCharacterData else { return }

            let cs2 = UnsafeRawPointer(cs!).assumingMemoryBound(to: UInt8.self)
            let bp = UnsafeBufferPointer(start: cs2, count: Int(cslen))
            let s = String(decoding: bp, as: UTF8.self)
            cb(s)
        }

        XML_SetCommentHandler(self.parser) { ud, comment in
            let me = unsafeBitCast(ud, to: Expat.self)
            guard let cb = me.cbComment else { return }
            guard let comment = comment else { return }
            cb(String(cString: comment))
        }
    }

    /* callbacks */

    public typealias AttrDict = [String: String]
    public typealias StartElementHandler = (String, AttrDict) -> Void
    public typealias EndElementHandler = (String) -> Void
    public typealias StartNamespaceHandler = (String?, String) -> Void
    public typealias EndNamespaceHandler = (String?) -> Void
    public typealias CDataHandler = (String) -> Void
    public typealias ErrorHandler = (XML_Error) -> Void

    var cbStartElement: StartElementHandler?
    var cbEndElement: EndElementHandler?
    var cbStartNS: StartNamespaceHandler?
    var cbEndNS: EndNamespaceHandler?
    var cbCharacterData: CDataHandler?
    var cbComment: CDataHandler?
    var cbError: ErrorHandler?

    public func onStartElement(cb: @escaping StartElementHandler) -> Self {
        self.cbStartElement = cb
        return self
    }

    public func onEndElement(cb: @escaping EndElementHandler) -> Self {
        self.cbEndElement = cb
        return self
    }

    public func onStartNamespace(cb: @escaping StartNamespaceHandler) -> Self {
        self.cbStartNS = cb
        return self
    }

    public func onEndNamespace(cb: @escaping EndNamespaceHandler) -> Self {
        self.cbEndNS = cb
        return self
    }

    public func onCharacterData(cb: @escaping CDataHandler) -> Self {
        self.cbCharacterData = cb
        return self
    }

    public func onComment(cb: @escaping CDataHandler) -> Self {
        self.cbComment = cb
        return self
    }

    public func onError(cb: @escaping ErrorHandler) -> Self {
        self.cbError = cb
        return self
    }
}

public extension Expat { // Namespaces
    typealias StartElementNSHandler =
        (String, String, [String: String]) -> Void
    typealias EndElementNSHandler = (String, String) -> Void

    func onStartElementNS(cb: @escaping StartElementNSHandler) -> Self {
        let sep = self.nsSeparator // so that we don't capture 'self' (necessary?)
        return self.onStartElement {
            // split(separator:maxSplits:omittingEmptySubsequences:)
            let comps = $0.split(
                separator: sep,
                maxSplits: 1,
                omittingEmptySubsequences: true
            )
            cb(String(comps[0]), String(comps[1]), $1)
        }
    }

    func onEndElementNS(cb: @escaping EndElementNSHandler) -> Self {
        let sep = self.nsSeparator // so that we don't capture 'self' (necessary?)
        return self.onEndElement {
            let comps = $0.split(
                separator: sep,
                maxSplits: 1,
                omittingEmptySubsequences: true
            )
            cb(String(comps[0]), String(comps[1]))
        }
    }
}

extension XML_Error: Error {}

extension XML_Error: CustomStringConvertible {
    public var description: String {
        switch self {
        // doesn't work?: case .XML_ERROR_NONE: return "OK"
        case XML_ERROR_NONE: return "OK"
        case XML_ERROR_NO_MEMORY: return "XMLError::NoMemory"
        case XML_ERROR_SYNTAX: return "XMLError::Syntax"
        case XML_ERROR_NO_ELEMENTS: return "XMLError::NoElements"
        case XML_ERROR_INVALID_TOKEN: return "XMLError::InvalidToken"
        case XML_ERROR_UNCLOSED_TOKEN: return "XMLError::UnclosedToken"
        case XML_ERROR_PARTIAL_CHAR: return "XMLError::PartialChar"
        case XML_ERROR_TAG_MISMATCH: return "XMLError::TagMismatch"
        case XML_ERROR_DUPLICATE_ATTRIBUTE: return "XMLError::DupeAttr"
        // FIXME: complete me
        default:
            return "XMLError(\(self))"
        }
    }
}

public enum ExpatResult: CustomStringConvertible {
    case OK
    case Suspended

    public var description: String {
        switch self {
        case .OK: return "OK"
        case .Suspended: return "Suspended"
        }
    }

    public var boolValue: Bool {
        switch self {
        case .OK: return true
        default: return false
        }
    }
}

func makeAttributesDictionary
(_ attrs: UnsafeMutablePointer<UnsafePointer<XML_Char>?>?)
    -> [String: String]
{
    var sAttrs = [String: String]()
    guard let attrs = attrs else { return sAttrs }
    var i = 0
    while attrs[i] != nil {
        let name = String(cString: attrs[i]!)
        let value = attrs[i + 1] != nil ? String(cString: attrs[i + 1]!) : ""
        sAttrs[name] = value
        i += 2
    }
    return sAttrs
}
