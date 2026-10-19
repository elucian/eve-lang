# route

Route tables: patterns with {name} segments, handlers that give a Reply, and the dispatch of a request (404, 405, 500).
@spec spec/library/route.md  @feature F-NET-02  @decision D-189, D-192  @tests test/level6/f10_route_hello

## `class Reply = {status: Integer, body: String, headers: Any} <: Object is`

What a handler gives back.

## `class Route = {verb: String, pattern: String, handler: Any} <: Object is`

One route: the verb, the pattern and the handler (req, params) => Reply.

## `class Match = {found: Logic, other_verb: Logic, params: Any, handler: Any?} <: Object is`

The result of find: found, or only another verb matches; the captured parameters; the handler.

## `function add(verb: String, pattern: String, handler: Any) => (@result: Route) is`

A route for any verb.

## `function get(pattern: String, handler: Any) => (@result: Route) is`

A GET route.

## `function post(pattern: String, handler: Any) => (@result: Route) is`

A POST route.

## `function status(code: Integer, body: String) => (@result: Reply) is`

A reply with a status and a text body.

## `function text(body: String) => (@result: Reply) is`

A 200 reply with a text body.

## `function as_json(:T)(value: T) => (@result: Reply) is`

A 200 reply with the JSON text of a value.

## `function segments(path: String) => (@result: Any) is`

The non-empty segments of a path.

## `function match_path(pattern: String, path: String) => (@result: Any?) is`

The parameters captured by a pattern in a path, or null when the path does not match.

## `function find(routes: Any, verb: String, path: String) => (@result: Match) is`

The first route of the table that matches the verb and the path.

## `function dispatch(routes: Any, req: Any) => (@result: Reply) is`

The reply for a request: 404, 405 or the handler result; a handler that raises gives a 500 with the message.

