//
//  INIParser.swift
//  Perfect-INIParser
//
//  Created by Rockford Wei on 2017-04-25.
//  Copyright © 2017 PerfectlySoft. All rights reserved.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2017 - 2018 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//

/// INI Configuration File Reader
public final class INIParser {
    internal var _sections: [String: [String: String]] = [:]
    internal var _anonymousSection: [String: String] = [:]

    public var sections: [String: [String: String]] { return self._sections }
    public var anonymousSection: [String: String] { return self._anonymousSection }

    public enum Error: Swift.Error {
        case invalidSyntax
    }

    enum State {
        case Title, Variable, Value, SingleQuotation, DoubleQuotation
    }

    enum ContentType {
        case Section(String)
        case Assignment(String, String)
    }

    internal func parse(line: String) throws -> ContentType? {
        var cache = ""
        var state = State.Variable
        var stack = [State]()

        var variable: String?
        for c in line {
            switch c {
            case " ", "\t":
                if state == .SingleQuotation || state == .DoubleQuotation || state == .Title {
                    cache.append(c)
                }
            case "[":
                if state == .Variable {
                    cache = ""
                    stack.append(state)
                    state = .Title
                }
            case "]":
                if state == .Title {
                    guard let last = stack.popLast() else { throw Error.invalidSyntax }
                    state = last
                    return ContentType.Section(cache)
                }
            case "=":
                if state == .Variable {
                    variable = cache
                    cache = ""
                    state = .Value
                } else {
                    cache.append(c)
                }
            case "#", ";":
                if state == .Value {
                    if let v = variable {
                        return ContentType.Assignment(v, cache)
                    } else {
                        throw Error.invalidSyntax
                    }
                } else {
                    return nil
                }
            case "\"":
                if state == .DoubleQuotation {
                    guard let last = stack.popLast() else {
                        throw Error.invalidSyntax
                    }
                    state = last
                } else {
                    stack.append(state)
                    state = .DoubleQuotation
                }
                cache.append(c)
            case "\'":
                if state == .SingleQuotation {
                    guard let last = stack.popLast() else {
                        throw Error.invalidSyntax
                    }
                    state = last
                } else {
                    stack.append(state)
                    state = .SingleQuotation
                }
                cache.append(c)
            default:
                cache.append(c)
            }
        }
        guard state == .Value, let v = variable else {
            throw Error.invalidSyntax
        }
        return ContentType.Assignment(v, cache)
    }

    /// Constructor
    /// - parameters:
    ///   - path: path of INI file to load
    /// - throws:
    ///   Exception
    public init(_ content: String) throws {
        let lines: [String] = content.split(separator: "\n").map { String($0) }
        var title: String?
        for line in lines {
            if let content = try parse(line: line) {
                switch content {
                case .Section(let newTitle):
                    title = newTitle
                case .Assignment(let variable, let value):
                    if let currentTitle = title {
                        if var sec = _sections[currentTitle] {
                            sec[variable] = value
                            self._sections[currentTitle] = sec
                        } else {
                            var sec: [String: String] = [:]
                            sec[variable] = value
                            self._sections[currentTitle] = sec
                        }
                    } else {
                        self._anonymousSection[variable] = value
                    }
                }
            }
        }
    }
}
