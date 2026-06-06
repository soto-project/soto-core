# Tasks: credential_process Support

## Task 1: Add `swift-subprocess` dependency to Package.swift
- [ ] Add `.package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "0.4.0")` to dependencies
- [ ] Add `.product(name: "Subprocess", package: "swift-subprocess")` to SotoCore target dependencies
- [ ] Add `.executableTarget(name: "credential-process-test-helper", path: "Sources/credential-process-test-helper")` target
- [ ] Verify the package resolves with `swift package resolve`

## Task 2: Implement `CredentialProcessProvider`
- [ ] Create `Sources/SotoCore/Credential/CredentialProcessProvider.swift`
- [ ] Add conditional Foundation import (`#if canImport(FoundationEssentials)` / `import Foundation`)
- [ ] Import `Subprocess`, `Logging`, `SotoSignerV4`
- [ ] Define `CredentialProcessError` public struct (cases: `commandEmpty`, `processExitedWithError(Int32)`, `invalidVersion(Int)`, `failedToDecodeOutput`, `invalidExpiration`)
- [ ] Define private `CredentialProcessOutput` Decodable struct with CodingKeys mapping PascalCase JSON fields
- [ ] Implement `CredentialProcessProvider` struct conforming to `CredentialProvider`
- [ ] Implement `getCredential(logger:)`: execute via `/bin/sh -c`, check exit code, decode JSON, validate Version, parse Expiration, return `RotatingCredential` or `StaticCredential`
- [ ] Implement ISO 8601 date parsing helper (handle both with and without fractional seconds)
- [ ] Ensure full `Sendable` conformance

## Task 3: Integrate into ConfigFileLoader
- [ ] Add `credentialProcess: String?` field to `ProfileCredentials` struct
- [ ] Add `credentialProcess: String?` field to `ProfileConfig` struct
- [ ] Add `.credentialProcess(command: String)` case to `SharedCredentials` enum
- [ ] In `parseCredentials(from:for:sourceProfile:)`: read `settings["credential_process"]`
- [ ] In `parseProfileConfig(from:for:)`: read `settings["credential_process"]`
- [ ] In `parseSharedCredentials(from:configINIParser:for:)`: add credential_process resolution (after role_arn logic, before static credentials)
- [ ] In the role_arn block: add branch for credential_process as source credential when no source_profile/credential_source

## Task 4: Integrate into ConfigFileCredentialProvider and CredentialProviderFactory
- [ ] In `ConfigFileCredentialProvider.credentialProvider(from:context:endpoint:)`: add `case .credentialProcess(let command): return CredentialProcessProvider(command: command)`
- [ ] Add `public static func credentialProcess(command: String) -> CredentialProviderFactory` to `CredentialProviderFactory` extension

## Task 5: Create test helper binary
- [ ] Create `Sources/credential-process-test-helper/main.swift`
- [ ] Add conditional Foundation import
- [ ] Implement hard-coded credential output (AKID-CREDENTIAL-PROCESS, SECRET-CREDENTIAL-PROCESS, TOKEN-CREDENTIAL-PROCESS)
- [ ] Support `--expiring` flag (adds Expiration 1 hour from now in ISO 8601)
- [ ] Support `--no-session-token` flag (omits SessionToken)
- [ ] Support `--invalid-version` flag (outputs Version: 2)
- [ ] Support `--invalid-json` flag (outputs malformed JSON)
- [ ] Support `--exit-code N` flag (exits with specified code)
- [ ] Verify binary runs: `swift run credential-process-test-helper`

## Task 6: Add unit tests for config parsing
- [ ] Create `Tests/SotoCoreTests/Credential/CredentialProcessProviderTests.swift`
- [ ] Test: `credential_process` in credentials file → returns `.credentialProcess` case
- [ ] Test: `credential_process` in config file only → returns `.credentialProcess` case
- [ ] Test: `credential_process` in both files → credentials file value wins
- [ ] Test: `credential_process` + `role_arn` (no source_profile) → returns `.assumeRole` with credentialProcess source
- [ ] Test: `credential_process` + `source_profile` → source_profile takes precedence
- [ ] Test: profile with static keys and credential_process → static keys take precedence

## Task 7: Add unit tests for process execution
- [ ] Test: successful execution returns StaticCredential (no Expiration)
- [ ] Test: successful execution with `--expiring` returns ExpiringCredential with valid date
- [ ] Test: `--no-session-token` → credential.sessionToken is nil
- [ ] Test: `--exit-code 1` → throws `CredentialProcessError.processExitedWithError(1)`
- [ ] Test: `--invalid-version` → throws `CredentialProcessError.invalidVersion(2)`
- [ ] Test: `--invalid-json` → throws `CredentialProcessError.failedToDecodeOutput`
- [ ] Test: empty command → throws `CredentialProcessError.commandEmpty`

## Task 8: Add end-to-end integration test
- [ ] Test: write temp credentials file with `credential_process = /path/to/helper`, load via `ConfigFileLoader.loadSharedCredentials`, verify `.credentialProcess` case, create provider, call `getCredential`, verify returned access key / secret / token values
- [ ] Test: same flow with `--expiring` flag, verify returned credential conforms to `ExpiringCredential`
- [ ] Run full test suite: `swift test` — verify no regressions
- [ ] Verify `swift build` succeeds (compilation check)
