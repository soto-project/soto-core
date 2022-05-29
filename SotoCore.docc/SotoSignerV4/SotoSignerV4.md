# ``SotoSignerV4``

Sign HTTP requests before sending them to AWS either by generating a signed URL or a set of signed headers.

## Overview

### Initialisation

To create a `AWSSigner` you need a set of credentials, a signing name and a AWS region.

```swift
let credentials: Credential = StaticCredential(
    accessKeyId: "_MYACCESSKEY_", 
    secretAccessKey: "_MYSECRETACCESSKEY_"
)
let signer = AWSSigner(credentials: credentials, name: "s3", region: "eu-west-1")
```

### Signed URLs

A signed URL includes the signature as query parameter `X-Amz-Signature`. The method `signURL` will create a signed URL.

```swift
let url = URL(string: "https://my-bucket.s3.eu-west-1.awsamazon.com/file")!
let signedURL = signer.signURL(url: url, method: .GET, expires: .minutes(60))
```

### Signed Headers

Instead of returning a signed URL you can add an additional `authorization` header which includes the signature. Use the method `signHeaders` to create a set of signed headers which you can use with the rest of your request.

```swift
let signedHeaders = signer.signHeaders(url: url, method: .GET, headers: headers, body: .byteBuffer(body))
```

### Processing requests

Some requests URLs need to be processed before signing. The signer expects query parameters to be alphabetically sorted and that paths have been percent encoded. You can use `processURL` to do this work for you.

```swift
let url = URL(string: "https://my-bucket.s3.eu-west-1.awsamazon.com/file")!
let processedURL = signer.processURL(url)!
let signedURL = signer.signURL(url: processedURL, method: .GET, expires: .minutes(60))
```

You can find out more about the AWS signing process [here](https://docs.aws.amazon.com/general/latest/gr/sigv4_signing.html).

## Topics

### Signer

- ``AWSSigner``

### Credentials

- ``Credential``
- ``StaticCredential``