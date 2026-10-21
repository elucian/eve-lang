# The modules `route` and `service`

Status: **draft**, level 6. Features: F-NET-02, F-STR-08, F-TLS-14. Written in Eve: `lib/route.eve`, `lib/service.eve`, over [http](http.md).

A **route table** is a list of routes; a route is made with `route.get`, `route.post` or `route.add`. A handler is a function of two values, the `Request` and the `DataMap` of the path parameters, that gives a `Reply`. `service.serve` accepts connections on a `Listener` and answers each one.

```eve
from lib use (route, service);

new routes := (
  route.get("/hello", (req, p) => (route.text("hello"))),
  route.get("/users/{id}", (req, p) => (route.text("user " + p["id"]))),
  route.post("/echo", (req, p) => (route.text(req.body))),
);
service.serve(server, routes, 3);
```

## `route`

| Member | Meaning |
|---|---|
| `get(pattern, handler)`, `post(pattern, handler)`, `add(verb, pattern, handler)` | a route; a pattern is `/a/b` with `{name}` for one segment that is captured |
| `text(body)`, `as_json(value)`, `status(code, body)` | a `Reply`: `text` is 200 with a plain text body, `as_json` is 200 with `json.text(value)` and `content-type: application/json`, `status` has the given code |
| `find(routes, verb, path)` | the first route that matches, as a `Match` (`found`, `params`, `handler`); `found` is `False` for no route; a path that matches a route of another verb is a 405 in `dispatch` |
| `dispatch(routes, request)` | the `Reply` for the request: 404 when no route matches the path, 405 when only another verb does, 500 with the message when the handler raises (a `recover` in the function) |

`Reply` has the fields `status: Integer`, `body: String`, `headers: DataMap`. Patterns are matched segment by segment from the left; a trailing `/` is ignored; the first route in the list wins.

## `service`

| Member | Meaning |
|---|---|
| `handle(socket, routes)` | reads one request on the socket, writes the reply of `dispatch`, closes the socket |
| `idle(ms: Integer)` | how long a client may stay silent before the reply `408 Request Time-out` (default 5000 ms) |
| `serve(server: Listener, routes, count: Integer)` | accepts and handles `count` connections one after the other; `count` 0 serves until the listener is closed |

Run `serve` in an `async procedure` started with `spawn` in a job, so the client or the other code of the script goes on (the example of [net.md](net.md)). One connection at a time at level 6; a handler that waits stops the other clients (TD-29).

The function is `as_json` and not `json`: inside a module a member named `json` would hide the module `json`.
