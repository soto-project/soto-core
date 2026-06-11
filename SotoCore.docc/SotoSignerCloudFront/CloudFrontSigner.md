# ``SotoSignerCloudFront/CloudFrontSigner``

## Topics

### Initializers

- ``init(keyPairId:privateKeyPEM:hashAlgorithm:)``
- ``init(keyPairId:privateKeyDER:hashAlgorithm:)``

### Nested Types

- ``HashAlgorithm``
- ``CustomPolicy``
- ``SignedCookies``

### Signed URLs

- ``signedURL(url:expires:date:)``
- ``signedURL(url:policy:date:)``

### Signed Cookies

- ``signedCookies(url:expires:date:)``
- ``signedCookies(policy:date:)``
