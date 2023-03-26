//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2021-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if compiler(>=5.6)
public typealias _SotoSendable = Sendable
public protocol _SotoSendableProtocol: Sendable {}
#else
public typealias _SotoSendable = Any
public protocol _SotoSendableProtocol {}
#endif
