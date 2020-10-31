//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Benchmark
import Foundation
import SotoCore
import SotoXML

protocol EncoderProtocol {
    associatedtype Output
    func encode<Input: Encodable>(_ type: Input) throws -> Output
}

extension XMLEncoder: EncoderProtocol {
    typealias Output = XML.Element
    func encode<Input: Encodable>(_ value: Input) throws -> Output {
        try self.encode(value, name: "BenchmarkTest")
    }
}

extension QueryEncoder: EncoderProtocol {
    typealias Output = String?
    func encode<Input: Encodable>(_ value: Input) throws -> Output {
        try self.encode(value, name: "BenchmarkTest")
    }
}

struct Numbers: Codable {
    let b: Bool
    let i: Int
    let f: Float
    let d: Double
}

struct Strings: Codable {
    let s: String
    let s2: String?
}

struct Arrays: Codable {
    let a1: [Int]
    let a2: [String]
}

struct Dictionaries: Codable {
    let d: [String: Int]
}

/// Generic suite of benchmark tests for an Encoder.
func encoderSuite<E: EncoderProtocol>(for encoder: E, suite: BenchmarkSuite) {
    let numbers = Numbers(b: true, i: 3478, f: 34.4633, d: 9585)
    suite.benchmark("numbers") {
        _ = try encoder.encode(numbers)
    }

    let strings = Strings(s: "Benchmark string", s2: "optional")
    suite.benchmark("strings") {
        _ = try encoder.encode(strings)
    }

    let arrays = Arrays(a1: [234, 23, 55, 1], a2: ["Benchmark", "string"])
    suite.benchmark("arrays") {
        _ = try encoder.encode(arrays)
    }

    let dictionaries = Dictionaries(d: ["benchmark": 1, "tests": 2, "again": 6])
    suite.benchmark("dictionaries") {
        _ = try encoder.encode(dictionaries)
    }
}

/// Suite of benchmark tests for XMLEncoder
let xmlEncoderSuite = BenchmarkSuite(name: "XMLEncoder", settings: Iterations(10000), WarmupIterations(10)) { suite in
    encoderSuite(for: XMLEncoder(), suite: suite)
}

/// Suite of benchmark tests to XMLDecoder
let xmlDecoderSuite = BenchmarkSuite(name: "XMLDecoder", settings: Iterations(10000), WarmupIterations(10)) { suite in
    let xml = #"<test><a>hello</a><b><c>good</c><d>bye</d></b><b><c>good</c><d>bye</d></b><b><c>good</c><d>bye</d></b></test>"#
    suite.benchmark("loadXML") {
        let result = try XML.Element(xmlString: xml)
    }

    if let numbers = try? XML.Element(xmlString: #"<numbers><b>true</b><i>362222</i><f>3.14</f><d>2.777776</d></numbers>"#) {
        suite.benchmark("numbers") {
            _ = try XMLDecoder().decode(Numbers.self, from: numbers)
        }
    }

    if let strings = try? XML.Element(xmlString: #"<strings><s>Benchmark testing Decoder</s><s2>String version 2</s2></strings>"#) {
        suite.benchmark("strings") {
            _ = try XMLDecoder().decode(Strings.self, from: strings)
        }
    }

    if let arrays = try? XML.Element(xmlString: #"<strings><a1>23</a1><a1>89</a1><a1>28768234</a1><a2>test</a2></strings>"#) {
        suite.benchmark("arrays") {
            _ = try XMLDecoder().decode(Arrays.self, from: arrays)
        }
    }
}

/// Suite of benchmark tests to XMLDecoder
let dictionaryDecoderSuite = BenchmarkSuite(name: "DictionaryDecoder", settings: Iterations(10000), WarmupIterations(10)) { suite in

    let json1 = #"{"b": true, "i": 362222, "f": 3.14, "d": 2.777776}"#
    if let numbers = try? JSONSerialization.jsonObject(with: Data(json1.utf8), options: []) {
        suite.benchmark("numbers") {
            _ = try DictionaryDecoder().decode(Numbers.self, from: numbers)
        }
    }

    let json2 = #"{"s": "Benchmark testing Decoder", "s2": "String version 2"}"#
    if let strings = try? JSONSerialization.jsonObject(with: Data(json2.utf8), options: []) {
        suite.benchmark("strings") {
            _ = try DictionaryDecoder().decode(Strings.self, from: strings)
        }
    }

    let json3 = #"{"a1": [23,89,28768234], "a2": ["test"]}"#
    if let arrays = try? JSONSerialization.jsonObject(with: Data(json3.utf8), options: []) {
        suite.benchmark("arrays") {
            _ = try DictionaryDecoder().decode(Arrays.self, from: arrays)
        }
    }
}

/// Suite of benchmark tests for XMLEncoder
let queryEncoderSuite = BenchmarkSuite(name: "QueryEncoder", settings: Iterations(10000), WarmupIterations(10)) { suite in
    encoderSuite(for: QueryEncoder(), suite: suite)
}
