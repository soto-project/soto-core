# ``SotoSignerCloudFront``

Generate signed URLs and cookies for Amazon CloudFront private content distribution.

## Overview

CloudFront uses RSA-based signatures (distinct from AWS SigV4) to control access to private content served through CloudFront distributions. `SotoSignerCloudFront` provides a simple API to generate signed URLs and signed cookies using either canned or custom policies.

### Initialisation

Create a `CloudFrontSigner` with your CloudFront key pair ID and PEM-encoded RSA private key:

```swift
import SotoSignerCloudFront

let privateKeyPEM = try String(contentsOfFile: "/path/to/private-key.pem")

let signer = try CloudFrontSigner(
    keyPairId: "K2JCJMDEHXQW5F",
    privateKeyPEM: privateKeyPEM
)
```

You can also pass the key as DER-encoded `Data`:

```swift
let keyData = try Data(contentsOf: URL(fileURLWithPath: "/path/to/private-key.der"))
let signer = try CloudFrontSigner(keyPairId: "K2JCJMDEHXQW5F", privateKeyDER: keyData)
```

By default SHA-1 is used (for backward compatibility with existing CloudFront distributions). For new deployments, use SHA-256:

```swift
let signer = try CloudFrontSigner(
    keyPairId: "K2JCJMDEHXQW5F",
    privateKeyPEM: privateKeyPEM,
    hashAlgorithm: .sha256
)
```

### Signed URLs (Canned Policy)

A canned policy restricts access to a single resource with an expiration time:

```swift
let signedURL = try signer.signedURL(
    url: "https://d111111abcdef8.cloudfront.net/videos/movie.mp4",
    policy: .canned(expires: .hours(1))
)
// Result: https://d111111abcdef8.cloudfront.net/videos/movie.mp4?Expires=...&Signature=...&Key-Pair-Id=...
```

### Signed URLs (Custom Policy)

A custom policy supports wildcard resource paths, IP restrictions, and optional start times:

```swift
let customPolicy = CloudFrontSigner.CustomPolicy(
    resource: "https://d111111abcdef8.cloudfront.net/videos/*",
    expires: .hours(24),
    activeFrom: .minutes(5),
    ipAddress: "192.0.2.0/24"
)

let signedURL = try signer.signedURL(
    url: "https://d111111abcdef8.cloudfront.net/videos/movie.mp4",
    policy: .custom(customPolicy)
)
```

Note that `customPolicy.resource` (the pattern in the signed policy statement) can differ from the `url` parameter. This is useful when the policy grants access to a wildcard path but the URL targets a specific file.

### Signed Cookies (Canned Policy)

Signed cookies allow access to multiple restricted files without modifying each URL:

```swift
let cookies = try signer.signedCookies(
    url: "https://d111111abcdef8.cloudfront.net/premium/*",
    policy: .canned(expires: .hours(2))
)

// Use headerValues for convenience:
for header in cookies.headerValues {
    response.headers.add(name: "Set-Cookie", value: header)
}
```

### Signed Cookies (Custom Policy)

```swift
let customPolicy = CloudFrontSigner.CustomPolicy(
    resource: "https://d111111abcdef8.cloudfront.net/premium/*",
    expires: .hours(8),
    ipAddress: "10.0.0.0/8"
)

let cookies = try signer.signedCookies(
    url: "https://d111111abcdef8.cloudfront.net/premium/video.mp4",
    policy: .custom(customPolicy)
)

// Set these as response headers:
// Set-Cookie: CloudFront-Policy=\(cookies.policy!)
// Set-Cookie: CloudFront-Signature=\(cookies.signature)
// Set-Cookie: CloudFront-Key-Pair-Id=\(cookies.keyPairId)
```

### Error Handling

The initializer throws `CloudFrontSignerError.invalidPrivateKey` if the PEM data cannot be parsed. Signing methods throw `CloudFrontSignerError.signingFailed` if the RSA operation fails.

```swift
do {
    let signer = try CloudFrontSigner(keyPairId: "KXXX", privateKeyPEM: "bad data")
} catch CloudFrontSignerError.invalidPrivateKey {
    // Handle invalid key
}
```

## Topics

### Articles

- <doc:EndToEndTesting>

### Signer

- ``CloudFrontSigner``

### Errors

- ``CloudFrontSignerError``

## See Also

- ``SotoCore``
- ``SotoSignerV4``
