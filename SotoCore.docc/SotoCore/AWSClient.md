# ``SotoCore/AWSClient``

@Metadata {
    @DocumentationExtension(mergeBehavior: override)
}

Client managing communication with AWS services

## Overview

The `AWSClient` is the core of Soto. This is the object that manages your communication with AWS. It manages credential acquisition, takes your request, encodes it, signs it, sends it to AWS and then decodes the response for you. In most situations your application should only require one `AWSClient`. Create this at startup and use it throughout.

When creating an `AWSClient` you need to provide how you are going to acquire AWS credentials, what is your policy is on retrying failed requests, a list of middleware you would apply to requests to AWS and responses from AWS, client options, where you get your HTTPClient and a Logger to log any output not directly linked to a request. There are defaults for most of these parameters. The only one required is the `httpClientProvider`.

```swift
let awsClient = AWSClient(
    credentialProvider: .default,
    retryPolicy: .default,
    middlewares: [],
    options: .init(),
    httpClientProvider: .createNew,
    logger: AWSClient.loggingDisabled
)
```

### Credential Provider

The `credentialProvider` defines how the client acquires its AWS credentials. Its default is to try the following four different methods in the order indicated. The first method that is successful will be used: 

- Environment variables
- ECS container credentials
- EC2 instance metadata 
- The shared credential file `~/.aws/credential` 

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

Middleware allows you to insert your own code just as a request has been constructed or a response has been received. You can use this to edit the request/response or just to view it. SotoCore supplies one middleware — `AWSLoggingMiddleware` — which outputs your request to the console once constructed and the response received from AWS.

### HTTP Client provider

The `HTTPClientProvider` defines where you get your HTTP client from. You have three options:

- Pass `.createNew` which indicates the `AWSClient` should create its own HTTP client. This creates an instance of `HTTPClient` using [`AsyncHTTPClient`](https://github.com/swift-server/async-http.client).
- Supply your own `EventLoopGroup` with `.createNewWithEventLoopGroup(EventLoopGroup`). This creates a new `HTTPClient` but has it use the supplied `EventLoopGroup`.
- Supply your own HTTP client with `.shared(AWSHTTPClient)` as long as it conforms to the protocol `AWSHTTPClient`. `AsyncHTTPClient.HTTPClient` already conforms to this protocol.

There are a number of reasons you might want to provide your own client, such as:

- You have one HTTP client you want to use across all your systems.
- You want to change the configuration for the HTTP client used, perhaps you are running behind a proxy or want to enable response decompression.

## AWSClient Shutdown

The AWSClient requires you shut it down manually before it is deinitialized. The manual shutdown is required to ensure any internal processes are finished before the `AWSClient` is freed and Soto's event loops and client are shutdown properly. You can either do this asynchronously with `AWSClient.shutdown()` or do this synchronously with `AWSClient.syncShutdown()`.

## Topics

### Initializers

- ``init(credentialProvider:retryPolicy:middlewares:options:httpClientProvider:logger:)``
- ``HTTPClientProvider``
- ``Options``
- ``loggingDisabled``

### Instance Properties

- ``credentialProvider``
- ``middlewares``
- ``retryPolicy``
- ``httpClient``
- ``eventLoopGroup``

### Shutdown

- ``shutdown()``
- ``shutdown(queue:_:)``
- ``syncShutdown()``

### Credentials

- ``getCredential(on:logger:)-96cyr``
- ``getCredential(on:logger:)-5dlty``
- ``signHeaders(url:httpMethod:headers:body:serviceConfig:logger:)-2uyw9``
- ``signHeaders(url:httpMethod:headers:body:serviceConfig:logger:)-8h5yq``
- ``signURL(url:httpMethod:headers:expires:serviceConfig:logger:)-8d5k0``
- ``signURL(url:httpMethod:headers:expires:serviceConfig:logger:)-49aa3``

### Errors

- ``ClientError``

### Request Execution

- ``execute(operation:path:httpMethod:serviceConfig:logger:on:)-6jc01``
- ``execute(operation:path:httpMethod:serviceConfig:logger:on:)-3mu6q``
- ``execute(operation:path:httpMethod:serviceConfig:logger:on:)-6hhlh``
- ``execute(operation:path:httpMethod:serviceConfig:logger:on:)-6klm4``
- ``execute(operation:path:httpMethod:serviceConfig:input:hostPrefix:logger:on:)-4iuwj``
- ``execute(operation:path:httpMethod:serviceConfig:input:hostPrefix:logger:on:)-1upt6``
- ``execute(operation:path:httpMethod:serviceConfig:input:hostPrefix:logger:on:)-3ttl7``
- ``execute(operation:path:httpMethod:serviceConfig:input:hostPrefix:logger:on:)-3dlpq``
- ``execute(operation:path:httpMethod:serviceConfig:input:hostPrefix:logger:on:stream:)-3c73e``
- ``execute(operation:path:httpMethod:serviceConfig:input:hostPrefix:logger:on:stream:)-3yiw5``
- ``execute(operation:path:httpMethod:serviceConfig:endpointDiscovery:logger:on:)-3ek2x``
- ``execute(operation:path:httpMethod:serviceConfig:endpointDiscovery:logger:on:)-4uver``
- ``execute(operation:path:httpMethod:serviceConfig:endpointDiscovery:logger:on:)-9pukf``
- ``execute(operation:path:httpMethod:serviceConfig:endpointDiscovery:logger:on:)-7gnt3``
- ``execute(operation:path:httpMethod:serviceConfig:input:hostPrefix:endpointDiscovery:logger:on:)-3hzuw``
- ``execute(operation:path:httpMethod:serviceConfig:input:hostPrefix:endpointDiscovery:logger:on:)-2l7fr``
- ``execute(operation:path:httpMethod:serviceConfig:input:hostPrefix:endpointDiscovery:logger:on:)-1vx0e``
- ``execute(operation:path:httpMethod:serviceConfig:input:hostPrefix:endpointDiscovery:logger:on:)-3mdnx``
- ``execute(operation:path:httpMethod:serviceConfig:input:hostPrefix:endpointDiscovery:logger:on:stream:)-30x0f``
- ``execute(operation:path:httpMethod:serviceConfig:input:hostPrefix:endpointDiscovery:logger:on:stream:)-1m1h2``

### Pagination

- ``PaginatorSequence``
- ``paginate(input:command:inputKey:outputKey:logger:on:onPage:)``
- ``paginate(input:initialValue:command:inputKey:outputKey:logger:on:onPage:)``
- ``paginate(input:command:tokenKey:logger:on:onPage:)``
- ``paginate(input:initialValue:command:tokenKey:logger:on:onPage:)``
- ``paginate(input:command:tokenKey:moreResultsKey:logger:on:onPage:)-5ujha``
- ``paginate(input:initialValue:command:tokenKey:moreResultsKey:logger:on:onPage:)-3uxbf``

### Waiters

- ``waitUntil(_:waiter:maxWaitTime:logger:on:)-3ccn1``
- ``waitUntil(_:waiter:maxWaitTime:logger:on:)-385eg``
- ``Waiter``
- ``WaiterState``
