# ``SotoCore/AWSClient``

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
