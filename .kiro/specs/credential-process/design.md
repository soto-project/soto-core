# Design: credential_process Support

## Architecture

### Integration Point

The `credential_process` provider integrates into the existing credential resolution chain at the `ConfigFileLoader` level. When a profile contains a `credential_process` key (and no static credentials or higher-priority settings), the loader returns a new `SharedCredentials` case that `ConfigFileCredentialProvider` dispatches to the new `CredentialProcessProvider`.

The provider is wrapped by `RotatingCredentialProvider` (via the `.configFile()` factory), which handles:
- Caching credentials that have an `Expiration` and re-fetching before expiry
- Treating credentials without `Expiration` as never-expiring (`Date.distantFuture`)

### New File: `CredentialProcessProvider.swift`

```swift
// Sources/SotoCore/Credential/CredentialProcessProvider.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import Logging
import SotoSignerV4
import Subprocess

/// Obtains AWS credentials by executing an external process specified via `credential_process`.
public struct CredentialProcessProvider: CredentialProvider {
    let command: String

    public init(command: String) {
        self.command = command
    }

    public func getCredential(logger: Logger) async throws -> Credential {
        guard !command.isEmpty else {
            throw CredentialProcessError.commandEmpty
        }

        logger.debug("Executing credential_process", metadata: ["command": .string(command)])

        let result = try await Subprocess.run(
            .path("/bin/sh"),
            arguments: ["-c", command],
            output: .collect
        )

        guard result.terminationStatus.isSuccess else {
            let code: Int32 = // extract from terminationStatus
            throw CredentialProcessError.processExitedWithError(code)
        }

        let output = result.standardOutput
        guard !output.isEmpty else {
            throw CredentialProcessError.failedToDecodeOutput
        }

        let decoded: CredentialProcessOutput
        do {
            decoded = try JSONDecoder().decode(CredentialProcessOutput.self, from: Data(output))
        } catch {
            throw CredentialProcessError.failedToDecodeOutput
        }

        guard decoded.version == 1 else {
            throw CredentialProcessError.invalidVersion(decoded.version)
        }

        if let expirationString = decoded.expiration {
            guard let date = Self.parseISO8601(expirationString) else {
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
}
```

### Error Type

```swift
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
        case .commandEmpty: "credential_process command is empty"
        case .processExitedWithError(let code): "credential_process exited with code \(code)"
        case .invalidVersion(let v): "credential_process returned unsupported Version \(v) (expected 1)"
        case .failedToDecodeOutput: "credential_process output could not be decoded as JSON"
        case .invalidExpiration: "credential_process returned an invalid Expiration timestamp"
        }
    }
}
```

### JSON Decode Model

```swift
private struct CredentialProcessOutput: Decodable {
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
```

### ISO 8601 Date Parsing

Use `ISO8601DateFormatter` (available in both Foundation and FoundationEssentials):
```swift
private static func parseISO8601(_ string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: string) ?? {
        // Retry without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }()
}
```

## ConfigFileLoader Changes

### ProfileCredentials (add field)
```swift
struct ProfileCredentials: Equatable {
    // ... existing fields ...
    let credentialProcess: String?  // NEW
}
```

### ProfileConfig (add field)
```swift
struct ProfileConfig: Equatable {
    // ... existing fields ...
    let credentialProcess: String?  // NEW
}
```

### SharedCredentials (add case)
```swift
enum SharedCredentials {
    case staticCredential(credential: StaticCredential)
    case assumeRole(roleArn: String, sessionName: String, region: Region?, sourceCredentialProvider: CredentialProviderFactory)
    case credentialProcess(command: String)  // NEW
}
```

### Resolution Logic in `parseSharedCredentials`

Insert into the existing resolution flow:

1. **role_arn present** (existing logic): Check source_profile, credential_source. Add new branch: if neither source_profile nor credential_source but `credential_process` exists → use as source credential for assume-role.
2. **credential_process present** (new): If no role_arn and `credential_process` is set → return `.credentialProcess(command:)`. Credentials file value takes precedence over config file.
3. **Static credentials** (existing): Fall through to existing static credential logic.

## ConfigFileCredentialProvider Changes

Add to the switch in `credentialProvider(from:context:endpoint:)`:
```swift
case .credentialProcess(let command):
    return CredentialProcessProvider(command: command)
```

## CredentialProviderFactory Addition

```swift
extension CredentialProviderFactory {
    public static func credentialProcess(command: String) -> CredentialProviderFactory {
        Self { context in
            let provider = CredentialProcessProvider(command: command)
            return RotatingCredentialProvider(context: context, provider: provider)
        }
    }
}
```

## Package.swift Changes

```swift
// Add to dependencies array:
.package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "0.4.0"),

// Add to SotoCore target dependencies:
.product(name: "Subprocess", package: "swift-subprocess"),

// Add new executable target for test helper:
.executableTarget(
    name: "credential-process-test-helper",
    path: "Sources/credential-process-test-helper"
),
```

## Test Helper Binary

```swift
// Sources/credential-process-test-helper/main.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// Supports flags:
// (no flags)          → static credentials, no Expiration
// --expiring          → adds Expiration 1 hour from now
// --no-session-token  → omits SessionToken
// --invalid-version   → Version: 2
// --invalid-json      → malformed output
// --exit-code N       → exit with code N
```

Hard-coded values:
- `AccessKeyId`: `"AKID-CREDENTIAL-PROCESS"`
- `SecretAccessKey`: `"SECRET-CREDENTIAL-PROCESS"`
- `SessionToken`: `"TOKEN-CREDENTIAL-PROCESS"`

## Design Decisions

1. **Shell execution via `/bin/sh -c`**: Matches all official AWS SDKs. Handles quoting, pipes, environment variables, and path resolution without reimplementing a shell parser.

2. **`struct` for provider**: Only stores a `String`, naturally `Sendable`. Matches `SSOCredentialProvider` pattern.

3. **`RotatingCredentialProvider` wrapping**: The existing infrastructure handles credential caching and rotation. No custom caching logic needed in `CredentialProcessProvider`.

4. **Error as struct with internal enum**: Follows the established `ConfigFileError` pattern for consistency and `Equatable` conformance in tests.

5. **Precedence**: Credentials file `credential_process` takes priority over config file, matching AWS specification for all credential settings.

6. **credential_process + role_arn**: When both are present, credential_process provides the source credentials for STS AssumeRole. This matches AWS CLI behavior.

7. **swift-subprocess over Foundation.Process**: Cross-platform, async/await native, maintained by the Swift project. Avoids the `FoundationEssentials` incompatibility (Process is not in FoundationEssentials).

8. **No timeout in v1**: Matches official AWS SDKs which also don't impose a timeout on credential_process commands. Can be added later as a non-breaking change.
