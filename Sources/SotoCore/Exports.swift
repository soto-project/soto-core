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

#if swift(>=5.8)
@_exported @_documentation(visibility: internal) import protocol SotoSignerV4.Credential
@_exported @_documentation(visibility: internal) import struct SotoSignerV4.StaticCredential

@_exported @_documentation(visibility: internal) import struct Logging.Logger

@_exported @_documentation(visibility: internal) import struct NIOCore.ByteBuffer
@_exported @_documentation(visibility: internal) import struct NIOCore.ByteBufferAllocator
@_exported @_documentation(visibility: internal) import struct NIOCore.TimeAmount

@_exported @_documentation(visibility: internal) import struct NIOHTTP1.HTTPHeaders
@_exported @_documentation(visibility: internal) import enum NIOHTTP1.HTTPMethod
#else
@_exported import protocol SotoSignerV4.Credential
@_exported import struct SotoSignerV4.StaticCredential

@_exported import struct Logging.Logger

@_exported import struct NIOCore.ByteBuffer
@_exported import struct NIOCore.ByteBufferAllocator
@_exported import struct NIOCore.TimeAmount

@_exported import struct NIOHTTP1.HTTPHeaders
@_exported import enum NIOHTTP1.HTTPMethod
#endif
