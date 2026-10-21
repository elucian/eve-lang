# The module `rpc`

Status: **draft**, level 6. Feature: F-NET-08. Written in Eve: `lib/rpc.eve`, over `json.parse` and `json.text` ([data-language.md](data-language.md#json-text-in-memory-jsonparse-and-jsontext)). The machine API that it speaks is in [machine.md](machine.md#the-machine-api-level-6).

JSON-RPC 2.0 messages as text, one message per line. The module builds and reads messages and dispatches a request to a table of handlers; it does not own a socket (the lines travel on a connection of `net` or on the `POST /rpc` of a route).

| Member | Meaning |
|---|---|
| `request(id, method, params)` | the text of a request; `params` is a `List` or a `DataMap` |
| `notify(method, params)` | the text of a notification (no `id`, no answer) |
| `reply(id, result)` | the text of a successful answer |
| `failure(id, code, message)` | the text of an error answer |
| `dispatch(line, handlers)` | reads a request line, calls the handler of the method with `params`, and gives the text of the answer; an empty text for a notification |
| `result_of(line)` | the `result` of an answer line; an error answer raises the error `rpc: <code> <message>` |

`handlers` is a `DataMap` from a method name to a function of one parameter (the `params` of the request) that gives the result value. Errors of `dispatch`, with the codes of JSON-RPC 2.0:

| Case | code | message |
|---|---|---|
| the line is not JSON | -32700 | `parse error` |
| not an object with `method` | -32600 | `invalid request` |
| the method is not in `handlers` | -32601 | `method not found: <name>` |
| the handler raises an error | -32603 | the message of the error |
