# Requirements Document

## Introduction

This document specifies the requirements for adding `credential_process` support to soto-core. The `credential_process` configuration key allows AWS profiles to specify an external command that outputs temporary or long-term credentials as JSON to stdout. This is the standard mechanism for integrating custom credential helpers (corporate vaults, MFA tools, 1Password CLI, etc.) with AWS SDKs.

Reference: https://github.com/soto-project/soto-core/issues/641
AWS Documentation: https://docs.aws.amazon.com/cli/v1/userguide/cli-configure-sourcing-external.html

## Glossary

| Term | Definition |
|------|-----------|
| credential_process | An AWS config/credentials file key whose value is a shell command that outputs JSON credentials to stdout |
| Canned credentials | Long-term credentials without an `Expiration` field — never refreshed automatically |
| Temporary credentials | Credentials with an `Expiration` field — the SDK re-runs the command before expiry |
| Profile | A named section in `~/.aws/credentials` or `~/.aws/config` that groups configuration settings |

## Requirements

### Functional Requirements

#### FR-1: Execute External Credential Process
The library must execute the command specified by the `credential_process` key in an AWS profile. The command is executed via `/bin/sh -c` (matching the behavior of official AWS SDKs: boto3, JS SDK, Go SDK). The library reads JSON from the command's stdout.

#### FR-2: Parse Credential Process JSON Output
The library must parse the JSON output from the credential process command according to the AWS specification:

```json
{
  "Version": 1,
  "AccessKeyId": "an AWS access key",
  "SecretAccessKey": "your AWS secret access key",
  "SessionToken": "the AWS session token for temporary credentials",
  "Expiration": "ISO8601 timestamp when the credentials expire"
}
```

- `Version` (required): Must be integer `1`. Any other value is an error.
- `AccessKeyId` (required): The AWS access key ID.
- `SecretAccessKey` (required): The AWS secret access key.
- `SessionToken` (optional): Session token for temporary credentials.
- `Expiration` (optional): ISO 8601 formatted timestamp.

#### FR-3: Handle Credential Expiration
- If `Expiration` is absent: credentials are treated as long-term and never automatically refreshed.
- If `Expiration` is present: credentials are temporary. The `RotatingCredentialProvider` infrastructure must re-run the command before the credentials expire.

#### FR-4: Handle Process Errors
- Non-zero exit code from the credential process must result in an error surfaced to the caller.
- Malformed JSON output must result in a decode error.
- Empty stdout must result in an error.

#### FR-5: Config File Integration
The `credential_process` key must be recognized in both `~/.aws/credentials` and `~/.aws/config` files. When present in both, the credentials file value takes precedence (matching AWS precedence rules for all credential settings).

#### FR-6: Interaction with role_arn
When a profile specifies both `credential_process` and `role_arn` (without `source_profile` or `credential_source`), the credential_process is used as the source credential provider for the STS AssumeRole operation.

#### FR-7: Public Factory Method
A public `CredentialProviderFactory.credentialProcess(command:)` factory method must be provided so users can explicitly create a credential_process provider without going through config file resolution.

#### FR-8: Test Helper Binary
A sample executable target must be provided that outputs hard-coded credential JSON. This binary is used in end-to-end tests and serves as a reference implementation for users building custom credential helpers.

### Non-Functional Requirements

#### NFR-1: Linux Compilation
Must compile and run correctly on Linux. Must not use any Darwin-only APIs.

#### NFR-2: Conditional Foundation Import
Must use `FoundationEssentials` when available and fall back to `Foundation`:
```swift
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
```

#### NFR-3: Comprehensive Test Coverage
Must have extensive unit tests covering: JSON parsing (all field combinations), error cases (bad version, bad JSON, non-zero exit, invalid expiration), config file parsing (credential_process in credentials file, config file, both, with role_arn), and end-to-end execution using the test helper binary.

#### NFR-4: Minimal Dependencies
The only new external dependency is `swift-subprocess` (https://github.com/swiftlang/swift-subprocess, `>= 0.4.0`). This is a cross-platform, async/await-native subprocess library from the Swift project itself.

#### NFR-5: Sendable and Concurrency Safe
The `CredentialProcessProvider` type must conform to `Sendable` and work correctly with Swift 6 strict concurrency.

#### NFR-6: Swift 6 Compatibility
Must compile cleanly under Swift 6 strict concurrency with `StrictConcurrency=complete`.

#### NFR-7: Consistent Error Handling
Error types must follow the pattern established by `ConfigFileLoader.ConfigFileError` — a public struct conforming to `Error` and `Equatable` with an internal enum for cases.

### Out of Scope

- **Windows support**: The `/bin/sh -c` execution model is Unix-only. Windows support is deferred.
- **Credential caching within the provider**: Caching is handled by `RotatingCredentialProvider` which already wraps this provider. The credential process itself should implement caching if needed (per AWS specification).
- **Environment variable expansion in command**: The command is passed to `/bin/sh -c` which handles expansion natively.
- **Timeout configuration**: No configurable timeout for the credential process command in v1.
