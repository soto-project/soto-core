# ``SotoCore``

The core framework for Soto a Swift SDK for AWS

## Overview

SotoCore is the underlying driver for executing requests for the Soto Swift SDK for AWS. You will most likely be using this via one of libraries in [Soto](https://github.com/soto-project/soto). Much of the public APIs here you will never need to know as they are used internally by the Soto service libraries. But there are a few objects that are used.

## Topics

### Articles

- <doc:CredentialProviders>
- <doc:ServiceObjects>

### Client

- ``AWSClient``

### Services

- ``AWSService``
- ``AWSServiceConfig``
- ``ServiceProtocol``
- ``Region``
- ``AWSPartition``

### Middleware

- ``AWSServiceMiddleware``
- ``AWSLoggingMiddleware``
- ``AWSMiddlewareContext``

### Request/Response

- ``AWSRequest``
- ``AWSResponse``
- ``Body``

### Credentials

- ``CredentialProvider``
- ``AsyncCredentialProvider``
- ``NullCredentialProvider``
- ``ExpiringCredential``
- ``CredentialProviderFactory``
- ``DeferredCredentialProvider``
- ``RotatingCredentialProvider``
- ``RotatingCredential``
- ``CredentialProviderError``

### Retry

- ``RetryPolicy``
- ``RetryPolicyFactory``
- ``RetryStatus``

### Endpoints

- ``AWSEndpoints``
- ``AWSEndpointStorage``
- ``AWSEndpointDiscovery``

### Errors

- ``AWSErrorType``
- ``AWSErrorContext``
- ``AWSClientError``
- ``AWSServerError``
- ``AWSResponseError``
- ``AWSRawError``

### API Input/Outputs

- ``AWSShape``
- ``AWSEncodableShape``
- ``AWSDecodableShape``
- ``AWSShapeWithPayload``
- ``AWSShapeOptions``
- ``AWSPayload``
- ``AWSBase64Data``
- ``AWSMemberEncoding``
- ``AWSPaginateToken``

### Waiters

- ``AWSWaiterMatcher``
- ``AWSErrorCodeMatcher``
- ``AWSErrorStatusMatcher``
- ``AWSSuccessMatcher``
- ``JMESPathMatcher``
- ``JMESAllPathMatcher``
- ``JMESAnyPathMatcher``

### Streaming

- ``StreamReadFunction``
- ``StreamReaderResult``
- ``AWSResponseStream``

### Encoding/Decoding

- ``QueryEncoder``
- ``CustomCoding``
- ``OptionalCustomCoding``
- ``CustomCoder``
- ``CustomDecoder``
- ``CustomEncoder``
- ``OptionalCustomCodingWrapper``
- ``ArrayCoder``
- ``DictionaryCoder``
- ``ArrayCoderProperties``
- ``DictionaryCoderProperties``
- ``StandardArrayCoder``
- ``StandardDictionaryCoder``
- ``StandardArrayCoderProperties``
- ``StandardDictionaryCoderProperties``
- ``ISO8601DateCoder``
- ``HTTPHeaderDateCoder``
- ``UnixEpochDateCoder``

### CRC32

- ``soto_crc32(_:bytes:)``
- ``soto_crc32c(_:bytes:)``
- ``CRC32``

## See Also

- ``SotoSignerV4``
