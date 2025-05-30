# ``SotoCore/AWSClient``

@Metadata {
    @DocumentationExtension(mergeBehavior: override)
}

Client managing communication with AWS services

## Overview

The `AWSClient` is the core of Soto. This is the object that manages your communication with AWS. It manages credential acquisition, takes your request, encodes it, signs it, sends it to AWS and then decodes the response for you. In most situations your application should only require one `AWSClient`. Create this at startup and use it throughout.

When creating an `AWSClient` you need to provide how you are going to acquire AWS credentials, what your policy is on retrying failed requests, a list of middleware you would apply to requests to AWS and responses from AWS, client options, where you get your `HTTPClient` and a `Logger` to log any output not directly linked to a request.

```swift
let awsClient = AWSClient(
    credentialProvider: .default,
    retryPolicy: .default,
    middlewares: [],
    options: .init(),
    httpClient: HTTPClient.shared,
    logger: AWSClient.loggingDisabled
)
```

### Credential Provider

The `credentialProvider` defines how the client acquires its AWS credentials. You provide `AWSClient.init` with a factory function that will create the credential provider once the `AWSClient` has been initialised. This allows for the credential provider to use the `EventLoopGroup`, `Logger` and `HTTPClient` that the `AWSClient` uses. You can find factory functions for all the standard credential providers in ``CredentialProviderFactory``.

```swift
let awsClient = AWSClient(
    credentialProvider: .environment, 
    ...
)
```

If no credential provider is provided the default is to try environment variables, ECS container credentials, EC2 instance metadata and then the `~/.aws/credentials` file in this order. The first method that is successful will be used.

An alternative is to provide credentials in code. You can do this as follows

```swift
let client = AWSClient(
    credentialProvider: .static(
        accessKeyId: "MY_AWS_ACCESS_KEY_ID",
        secretAccessKey: "MY_AWS_SECRET_ACCESS_KEY"
    ),
    ...
)
```
The article <doc:CredentialProviders> gives more information on credential providers.

### Retry policy

The `retryPolicy` defines how the client reacts to a failed request. There are three retry policies supplied. `.noRetry` doesn't retry the request if it fails. The other two will retry if the response is a 5xx (server error) or a connection error. They differ in how long they wait before performing the retry. `.exponential` doubles the wait time after each retry and `.jitter` is the same as exponential except it adds a random element to the wait time. `.jitter` is the recommended method from AWS so it is the default.

### Middleware

Middleware allows you to insert your own code just as a request has been constructed or a response has been received. You can use this to edit the request/response or just to view it. SotoCore supplies one middleware — ``AWSLoggingMiddleware`` — which outputs your request to the console once constructed and the response is received from AWS.

### HTTP Client

This is the HTTP client that the AWS client uses to communicate with AWS services. This is defined by protocol, as Soto is agnostic about what HTTP client is used. Currently Soto only provides an implementation for [AsyncHTTPClient](https://github.com/swift-server/async-http-client). By default AWSClient uses the `shared` instance of `HTTPClient`. 

## AWSClient Shutdown

The AWSClient requires you shut it down manually before it is deinitialized. The manual shutdown is required to ensure any internal processes are finished before the `AWSClient` is freed and Soto's event loops and client are shutdown properly. You can either do this asynchronously with `AWSClient.shutdown()` or do this synchronously with `AWSClient.syncShutdown()`.

## Topics

### Initializers

- ``init(credentialProvider:retryPolicy:middleware:options:httpClient:logger:)``
- ``init(credentialProvider:retryPolicy:options:httpClient:logger:)``
- ``Options``
- ``loggingDisabled``

### Shutdown

- ``shutdown()``
- ``syncShutdown()``

### Instance Properties

- ``credentialProvider``
- ``middleware``
- ``httpClient``

### Credentials

- ``getCredential(logger:)``
- ``signHeaders(url:httpMethod:headers:body:serviceConfig:logger:)``
- ``signURL(url:httpMethod:headers:expires:serviceConfig:logger:)``

### Errors

- ``ClientError``

### Request Execution

- ``execute(operation:path:httpMethod:serviceConfig:logger:)-7ft6q``
- ``execute(operation:path:httpMethod:serviceConfig:logger:)-7kvc8``
- ``execute(operation:path:httpMethod:serviceConfig:input:hostPrefix:logger:)-7w1r1``
- ``execute(operation:path:httpMethod:serviceConfig:input:hostPrefix:logger:)-42qyk``

### Pagination

- ``PaginatorSequence``

### Waiters

- ``waitUntil(_:waiter:maxWaitTime:logger:)``
- ``Waiter``
- ``WaiterState``
