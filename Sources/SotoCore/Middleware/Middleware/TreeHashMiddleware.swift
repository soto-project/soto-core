//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Crypto

let MEGA_BYTE = 1024 * 1024

/// Middleware to add tree hash of body to request
///
/// Calculates a tree hash calculated from the SHA256 of each 1MB section of the request body
/// and adds it to the request as a header value
public struct TreeHashMiddleware: AWSMiddlewareProtocol {
    public func handle(_ request: AWSHTTPRequest, context: AWSMiddlewareContext, next: AWSMiddlewareNextHandler) async throws -> AWSHTTPResponse {
        var request = request
        if request.headers[self.treeHashHeader].first == nil {
            if case .byteBuffer(let buffer) = request.body.storage {
                let treeHash = try computeTreeHash(buffer).hexDigest()
                request.headers.replaceOrAdd(name: self.treeHashHeader, value: treeHash)
            }
        }
        return try await next(request, context)
    }

    let treeHashHeader: String

    /// - Parameter header: name of header to place tree hash in
    public init(header: String) {
        self.treeHashHeader = header
    }

    // ComputeTreeHash builds a tree hash root node given a Data Object
    // Glacier tree hash to be derived from SHA256 hashes of 1MB
    // chucks of the data.
    //
    // See http://docs.aws.amazon.com/amazonglacier/latest/dev/checksum-calculations.html for more information.
    //
    internal func computeTreeHash(_ byteBuffer: ByteBuffer) throws -> [UInt8] {
        var shas: [SHA256.Digest] = []

        if byteBuffer.readableBytes < MEGA_BYTE {
            let byteBufferView = byteBuffer.readableBytesView
            guard
                let _ = byteBufferView.withContiguousStorageIfAvailable({ bytes in shas.append(SHA256.hash(data: bytes)) })
            else {
                throw AWSClient.ClientError.failedToAccessPayload
            }
        } else {
            var numParts = byteBuffer.readableBytes / MEGA_BYTE
            if byteBuffer.readableBytes % MEGA_BYTE > 0 {
                numParts += 1
            }

            var start: Int
            var length = MEGA_BYTE

            for partNum in 0..<numParts {
                start = partNum * MEGA_BYTE
                if partNum == numParts - 1 {
                    length = byteBuffer.readableBytes - start
                }
                guard let byteBufferView = byteBuffer.viewBytes(at: byteBuffer.readerIndex + start, length: length) else {
                    throw AWSClient.ClientError.failedToAccessPayload
                }
                guard
                    let _ = byteBufferView.withContiguousStorageIfAvailable({ bytes in
                        shas.append(SHA256.hash(data: bytes))
                    })
                else {
                    throw AWSClient.ClientError.failedToAccessPayload
                }
            }
        }

        while shas.count > 1 {
            var tmpShas: [SHA256.Digest] = []
            shas.forEachSlice(
                2,
                {
                    let pair = $0
                    guard let bytes1 = pair.first else { return }

                    if pair.count > 1, let bytes2 = pair.last {
                        var sha256 = SHA256()
                        sha256.update(data: [UInt8](bytes1))
                        sha256.update(data: [UInt8](bytes2))
                        tmpShas.append(sha256.finalize())
                    } else {
                        tmpShas.append(bytes1)
                    }
                }
            )
            shas = tmpShas
        }

        return [UInt8](shas[0])
    }
}

extension Array {
    /*
      [1,2,3,4,5].forEachSlice(2, { print($0) })
      => [1, 2]
      => [3, 4]
      => [5]
     */
    func forEachSlice(_ n: Int, _ body: (ArraySlice<Element>) throws -> Void) rethrows {
        assert(n > 0, "n require to be greater than 0")

        for from in stride(from: self.startIndex, to: self.endIndex, by: n) {
            let to = Swift.min(from + n, self.endIndex)
            try body(self[from..<to])
        }
    }
}
