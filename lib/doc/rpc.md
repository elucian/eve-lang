# rpc

JSON-RPC 2.0 messages as lines of text: build a request, an answer or an error, and dispatch a request to a table of handlers.
@spec spec/library/rpc.md  @feature F-NET-08  @decision D-189  @tests test/level6/f07_rpc

## `function request(:T)(id: Integer, name: String, params: T) => (@result: String) is`

The text of a request; params is a List or a DataMap.

## `function notify(:T)(name: String, params: T) => (@result: String) is`

The text of a notification: a request with no id.

## `function reply(:T)(id: Integer, value: T) => (@result: String) is`

The text of a successful answer.

## `function failure(:T)(id: T, code: Integer, message: String) => (@result: String) is`

The text of an error answer; id is the id of the request, or null when it is unknown.

## `function answer(:H, :I, :P)(handler: H, id: I, params: P) => (@result: String) is`

The answer of one handler call; an error of the handler becomes the answer -32603 (recover in a function, D-192).

## `function dispatch(:H)(line: String, handlers: H) => (@result: String) is`

Read one request line, call handlers[method](params) and give the text of the answer; "" for a notification.

## `function result_of(line: String) => (@result: Any) is`

The result of an answer line; an error answer raises the error "rpc: code message".

