# ``SotoSignerV4/AWSSigner``

## Topics

### Initializers

- ``init(credentials:name:region:)``

### Instance Properties

- ``credentials``
- ``name``
- ``region``

### Signing

- ``signURL(url:method:headers:body:expires:omitSecurityToken:date:)``
- ``signHeaders(url:method:headers:body:omitSecurityToken:date:)``
- ``processURL(url:)``
- ``BodyData``

### Signing streamed data

- ``startSigningChunks(url:method:headers:date:)``
- ``signChunk(body:signingData:)``
- ``ChunkedSigningData``
