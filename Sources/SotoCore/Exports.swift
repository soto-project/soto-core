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

@_exported import protocol SotoSignerV4.Credential
@_exported import struct SotoSignerV4.StaticCredential

@_exported import protocol Baggage.LoggingContext
@_exported import struct Logging.Logger

@_exported import struct NIO.ByteBuffer
@_exported import struct NIO.ByteBufferAllocator
@_exported import protocol NIO.EventLoop
@_exported import class NIO.EventLoopFuture
@_exported import protocol NIO.EventLoopGroup
@_exported import struct NIO.TimeAmount

@_exported import struct NIOHTTP1.HTTPHeaders
@_exported import enum NIOHTTP1.HTTPMethod
