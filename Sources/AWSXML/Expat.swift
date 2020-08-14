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
        let cslen = strlen(cs) // cs? checks for a NULL C string
        let isFinal: Int32 = final ? 1 : 0

        let status: XML_Status = XML_Parse(parser, cs, Int32(cslen), isFinal)

        switch status { // the Expat enum's don't work?
        case XML_STATUS_OK: return .ok
        case XML_STATUS_SUSPENDED: return .suspended
        default:
            let error = XML_GetErrorCode(parser)
            if let callback = cbError {
                callback(error)
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
            guard let callback = me.cbStartElement else { return }
            let sName = name != nil ? String(cString: name!) : ""

            // FIXME: we should not copy stuff, but have a wrapper which works on the
            //        attrs structure 'on demand'
            let sAttrs = Expat.makeAttributesDictionary(attrs)
            callback(sName, sAttrs)
        }

        XML_SetEndElementHandler(self.parser) { ud, name in
            let me = unsafeBitCast(ud, to: Expat.self)
            guard let callback = me.cbEndElement else { return }
            let sName = String(cString: name!) // force unwrap, must be set
            callback(sName)
        }

        XML_SetStartNamespaceDeclHandler(self.parser) { ud, prefix, uri in
            let me = unsafeBitCast(ud, to: Expat.self)
            guard let callback = me.cbStartNS else { return }
            let sPrefix = prefix != nil ? String(cString: prefix!) : nil
            let sURI = String(cString: uri!)
            callback(sPrefix, sURI)
        }
        XML_SetEndNamespaceDeclHandler(self.parser) { ud, prefix in
            let me = unsafeBitCast(ud, to: Expat.self)
            guard let callback = me.cbEndNS else { return }
            let sPrefix = prefix != nil ? String(cString: prefix!) : nil
            callback(sPrefix)
        }

        XML_SetCharacterDataHandler(self.parser) { ud, cs, cslen in
            assert(cslen > 0)
            assert(cs != nil)
            guard cslen > 0 else { return }

            let me = unsafeBitCast(ud, to: Expat.self)
            guard let callback = me.cbCharacterData else { return }

            let cs2 = UnsafeRawPointer(cs!).assumingMemoryBound(to: UInt8.self)
            let bp = UnsafeBufferPointer(start: cs2, count: Int(cslen))
            let s = String(decoding: bp, as: UTF8.self)
            callback(s)
        }

        XML_SetCommentHandler(self.parser) { ud, comment in
            let me = unsafeBitCast(ud, to: Expat.self)
            guard let callback = me.cbComment else { return }
            guard let comment = comment else { return }
            callback(String(cString: comment))
        }
    }

    /* callbacks */

    public typealias AttributeDictionary = [String: String]
    public typealias StartElementHandler = (String, AttributeDictionary) -> Void
    public typealias EndElementHandler = (String) -> Void
    public typealias StartNamespaceHandler = (String?, String) -> Void
    public typealias EndNamespaceHandler = (String?) -> Void
    public typealias CDataHandler = (String) -> Void
    public typealias CommentHandler = (String) -> Void
    public typealias ErrorHandler = (XML_Error) -> Void

    var cbStartElement: StartElementHandler?
    var cbEndElement: EndElementHandler?
    var cbStartNS: StartNamespaceHandler?
    var cbEndNS: EndNamespaceHandler?
    var cbCharacterData: CDataHandler?
    var cbComment: CommentHandler?
    var cbError: ErrorHandler?

    public func onStartElement(_ callback: @escaping StartElementHandler) -> Self {
        self.cbStartElement = callback
        return self
    }

    public func onEndElement(_ callback: @escaping EndElementHandler) -> Self {
        self.cbEndElement = callback
        return self
    }

    public func onStartNamespace(_ callback: @escaping StartNamespaceHandler) -> Self {
        self.cbStartNS = callback
        return self
    }

    public func onEndNamespace(_ callback: @escaping EndNamespaceHandler) -> Self {
        self.cbEndNS = callback
        return self
    }

    public func onCharacterData(_ callback: @escaping CDataHandler) -> Self {
        self.cbCharacterData = callback
        return self
    }

    public func onComment(_ callback: @escaping CommentHandler) -> Self {
        self.cbComment = callback
        return self
    }

    public func onError(_ callback: @escaping ErrorHandler) -> Self {
        self.cbError = callback
        return self
    }

    /// Make a dictionary from the attribute list returned by Expat
    /// List is array of char pointers arranaged as follows: name, value, name, value...
    /// - Parameter attrs: array of string pointers
    /// - Returns: attributes in dictionary form
    static func makeAttributesDictionary(_ attrs: UnsafeMutablePointer<UnsafePointer<XML_Char>?>?) -> [String: String]
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
    case ok
    case suspended

    public var description: String {
        switch self {
        case .ok: return "OK"
        case .suspended: return "Suspended"
        }
    }

    public var boolValue: Bool {
        switch self {
        case .ok: return true
        default: return false
        }
    }
}
