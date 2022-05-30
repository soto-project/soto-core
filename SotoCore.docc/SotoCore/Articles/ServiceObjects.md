# AWS Service Objects

Defining an AWS service.

In Soto each AWS Service has a service object. This object brings together an `AWSClient` and a service configuration, `AWSServiceConfig`, and provides methods for accessing all the operations available from that service.

## Initialisation

The `init` for each service is as follows. Details about each parameter are available below.

```swift
public init(
    client: AWSClient,
    region: SotoCore.Region? = nil,
    partition: AWSPartition = .aws,
    endpoint: String? = nil,
    timeout: TimeAmount? = nil,
    byteBufferAllocator: ByteBufferAllocator = ByteBufferAllocator(),
    options: AWSServiceConfig.Options = []
)
```

#### Client

The client is the `AWSClient` this service object will use when communicating with AWS.

#### Region and Partition

The `region` defines which AWS region you want to use for that service. The `partition` defines which set of AWS server regions you want to work with. Partitions include the standard `.aws`, US government `.awsusgov` and China `.awscn`. If you provide a `region`, the `partition` parameter is ignored. If you don't supply a `region` then the `region` will be set as the default region for the specified `partition`, if that is not defined it will check the `AWS_DEFAULT_REGION` environment variable or default to `us-east-1`.

Some services do not have a `region` parameter in their initializer, such as IAM. These services require you to communicate with one global region which is defined by the service. You can still control which partition you connect to though.

#### Endpoint

If you want to communicate with non-AWS servers you can provide an endpoint which replaces the `amazonaws.com` web address. You may want to do this if you are using a AWS mocking service for debugging purposes for example, or you are communicating with a non-AWS service that replicates AWS functionality.

#### Time out

Time out defines how long the HTTP client will wait until it cancels a request. This value defaults to 20 seconds. If you are planning on downloading/uploading large objects you should probably increase this value. `AsyncHTTPClient` allows you to set an additional connection timeout value. If you are extending your general timeout, use an `HTTPClient` configured with a shorter connection timeout to avoid waiting for long periods when a connection fails.

#### ByteBufferAllocator

During request processing the `AWSClient` will most likely be required to allocate space for `ByteBuffer`s. You can define how these are allocated with the `byteBufferAllocator` parameter.

#### Options

A series of flags, that can affect how requests are constructed. The only option available at the moment is `s3ForceVirtualHost`. S3 uses virtual host addressing by default except if you use a custom endpoint. `s3ForceVirtualHost` will force virtual host addressing even when you specify a custom endpoint.

## AWSService

All service objects conform to the `AWSService` protocol. This protocol brings along a couple of extra bits of functionality

### Presigned URLs

When a request is made to AWS it has to be signed. This uses your AWS credentials and the contents of the request to create a signature. When the request is sent to the AWS server, the server also creates a version of this signature. If these two signatures match then AWS knows who is making the request and that it can be trusted. If you want to allow your clients to access AWS resources, creating a presigned request to send to your client is a common way to do this. Alternatively you would have to send AWS credentials to the client and these could be abused.

One of the most common operations where this is used is for uploading an object to S3. Below creates a presigned URL which someone could use to upload a file to S3.
```swift
let signedURL = s3.signURL(
    url: URL(string: "https://<bucketname>.s3.us-east-1.amazonaws.com/<key>")!,
    httpMethod: .PUT,
    expires: .minutes(60)
).wait()
```

The function `signURL` returns an `EventLoopFuture<URL>` as it is dependent on a credential provider that may not have been resolved yet. In most cases though you are safe to just `wait` on the result as the credentials will be available.

### Creating new service objects from existing

It is possible to create a new version of a service object from an already existing one with additional `AWSServiceMiddleware`, an edited `timeOut`, `byteBufferAllocator` or `options` using the `AWSService.with(middlewares:timeout:byteBufferAllocator:options)` function.

If you are loading a much larger object then usual into S3 and want to extend the `timeout` value for this one operation you can do it as follows.
```swift
s3.with(timeout: .minutes(10)).putObject(request)
```
