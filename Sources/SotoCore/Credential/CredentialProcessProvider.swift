//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if os(macOS) || os(Linux)

import Foundation
import Logging
import SotoSignerV4

/// Obtains AWS credentials by executing an external process specified via `credential_process`.
///
/// The command is executed via `/bin/sh -c` and must output JSON to stdout matching the
/// AWS credential_process specification:
/// https://docs.aws.amazon.com/cli/v1/userguide/cli-configure-sourcing-external.html
public struct CredentialProcessProvider: CredentialProvider {
    let command: String

    public init(command: String) {
        self.command = command
    }

    public var description: String { "CredentialProcessProvider" }

    public func getCredential(logger: Logger) async throws -> Credential {
        guard !command.isEmpty else {
            throw CredentialProcessError.commandEmpty
        }

        logger.debug("Executing credential_process", metadata: ["command": .string(command)])

        let output = try await self.executeProcess()

        guard !output.isEmpty else {
            throw CredentialProcessError.failedToDecodeOutput
        }

        let decoded: CredentialProcessOutput
        do {
            decoded = try JSONDecoder().decode(CredentialProcessOutput.self, from: output)
        } catch {
            throw CredentialProcessError.failedToDecodeOutput
        }

        guard decoded.version == 1 else {
            throw CredentialProcessError.invalidVersion(decoded.version)
        }

        if let expirationString = decoded.expiration {
            guard let date = parseISO8601Date(expirationString) else {
                throw CredentialProcessError.invalidExpiration
            }
            return RotatingCredential(
                accessKeyId: decoded.accessKeyId,
                secretAccessKey: decoded.secretAccessKey,
                sessionToken: decoded.sessionToken,
                expiration: date
            )
        } else {
            return StaticCredential(
                accessKeyId: decoded.accessKeyId,
                secretAccessKey: decoded.secretAccessKey,
                sessionToken: decoded.sessionToken
            )
        }
    }

    private func executeProcess() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = nil

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: CredentialProcessError.failedToDecodeOutput)
                return
            }

            process.waitUntilExit()

            let status = process.terminationStatus
            guard status == 0 else {
                continuation.resume(throwing: CredentialProcessError.processExitedWithError(status))
                return
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            continuation.resume(returning: data)
        }
    }

}

// MARK: - Supporting Types

private struct CredentialProcessOutput: Decodable, Sendable {
    let version: Int
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String?
    let expiration: String?

    enum CodingKeys: String, CodingKey {
        case version = "Version"
        case accessKeyId = "AccessKeyId"
        case secretAccessKey = "SecretAccessKey"
        case sessionToken = "SessionToken"
        case expiration = "Expiration"
    }
}

public struct CredentialProcessError: Error, Equatable, CustomStringConvertible {
    enum Internal: Equatable {
        case commandEmpty
        case processExitedWithError(Int32)
        case invalidVersion(Int)
        case failedToDecodeOutput
        case invalidExpiration
    }

    let value: Internal

    public static var commandEmpty: Self { .init(value: .commandEmpty) }
    public static func processExitedWithError(_ code: Int32) -> Self { .init(value: .processExitedWithError(code)) }
    public static func invalidVersion(_ version: Int) -> Self { .init(value: .invalidVersion(version)) }
    public static var failedToDecodeOutput: Self { .init(value: .failedToDecodeOutput) }
    public static var invalidExpiration: Self { .init(value: .invalidExpiration) }

    public var description: String {
        switch value {
        case .commandEmpty:
            "credential_process command is empty"
        case .processExitedWithError(let code):
            "credential_process exited with code \(code)"
        case .invalidVersion(let v):
            "credential_process returned unsupported Version \(v) (expected 1)"
        case .failedToDecodeOutput:
            "credential_process output could not be decoded as JSON"
        case .invalidExpiration:
            "credential_process returned an invalid Expiration timestamp"
        }
    }
}

#endif
