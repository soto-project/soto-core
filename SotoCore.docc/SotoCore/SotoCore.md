# ``SotoCore``

The core framework for Soto, a Swift SDK for AWS

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
- ``AWSServiceErrorType``
- ``ServiceProtocol``
- ``Region``
- ``AWSPartition``
- ``EndpointVariantType``

### Middleware

- ``AWSMiddlewareProtocol``
- ``AWSMiddleware``
- ``AWSMiddlewareBuilder``
- ``AWSMiddlewareStack(_:)``
- ``AWSMiddlewareContext``
- ``AWSMiddlewareNextHandler``
- ``AWSEditHeadersMiddleware``
- ``AWSLoggingMiddleware``
- ``AWSTracingMiddleware``
- ``EndpointDiscoveryMiddleware``
- ``S3Middleware``
- ``TreeHashMiddleware``

### Credentials

- ``CredentialProvider``
- ``NullCredentialProvider``
- ``ExpiringCredential``
- ``CredentialProviderFactory``
- ``DeferredCredentialProvider``
- ``RotatingCredentialProvider``
- ``RotatingCredential``
- ``CredentialProviderError``
- ``EmptyCredential``

### Retry

- ``RetryPolicy``
- ``RetryPolicyFactory``
- ``RetryStatus``

### Endpoints

- ``AWSEndpoints``
- ``AWSEndpointStorage``

### Errors

- ``AWSErrorType``
- ``AWSErrorContext``
- ``AWSClientError``
- ``AWSServerError``
- ``AWSResponseError``
- ``AWSRawError``
- ``HeaderDecodingError``

### API Input/Outputs

- ``AWSShape``
- ``AWSEncodableShape``
- ``AWSDecodableShape``
- ``AWSErrorShape``
- ``AWSShapeOptions``
- ``AWSBase64Data``
- ``AWSDocument``
- ``AWSPaginateToken``

### Waiters

- ``AWSWaiterMatcher``
- ``AWSErrorCodeMatcher``
- ``AWSErrorStatusMatcher``
- ``AWSSuccessMatcher``
- ``JMESPathMatcher``
- ``JMESAllPathMatcher``
- ``JMESAnyPathMatcher``

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
- ``EC2ArrayCoder``
- ``EC2StandardArrayCoder``
- ``DateFormatCoder``
- ``ISO8601DateCoder``
- ``HTTPHeaderDateCoder``
- ``UnixEpochDateCoder``

### CRC32

- ``soto_crc32(_:bytes:)``
- ``soto_crc32c(_:bytes:)``
- ``CRC32``

### HTTP Client

- ``AWSHTTPClient``
- ``AWSHTTPRequest``
- ``AWSHTTPResponse``
- ``AWSHTTPBody``

### Event streams

- ``AWSEventStream``
- ``AWSEventPayload``
- ``AWSEventStreamError``

## See Also

- ``SotoSignerV4``
