# The module `http`

Status: **0.1-draft**, level 6 (D-189). Features: F-NET-02 (server side), F-DAT-02 (the client of `data-language.md`). Written in Eve: `lib/http.eve`, over [net](net.md). Tests: `test/level6/f10_route_hello`.

HTTP/1.1 as text on a `Socket`: read a request, write a response, call a server. One request for each connection (`Connection: close`); no keep-alive, no chunked bodies, no TLS (`https://` is level 9, D-189), no percent-decoding of the path.

## Classes

| Class | Fields |
|---|---|
| `Request` | `verb: String` (`"GET"`, `"POST"`, ...), `target: String` (as sent), `path: String` (before `?`), `query: DataMap` (`a=1&b=2` → `{"a":"1","b":"2"}`), `headers: DataMap` (names in lower case), `body: String` |
| `HttpResponse` | `status: Integer`, `headers: DataMap` (lower case), `body: String`; method `check()` raises `HttpError` for a status of 400 or more |

The field is `verb` and not `method` because `method` is a reserved word (`plan/library-gaps.md` G-6).

## Functions

| Function | Result | Meaning |
|---|---|---|
| `read_request!(sock: Socket)` | `Request` | reads the request line, the headers and the body (`Content-Length`); `verb` is `""` when the client closed before sending anything; a line that is not `VERB target HTTP/1.x` raises `$err_format` |
| `respond(sock, status: Integer, body: String, headers = {:})` | | writes `HTTP/1.1 <status> <reason>`, `Content-Length`, `Connection: close`, the given headers and the body |
| `get!(url: String, headers = {:})` | `HttpResponse` | `http://host:port/path` (port 80 when missing); the host is an IP literal at level 6 |
| `post!(url: String, body: String, headers = {:})` | `HttpResponse` | the same with a body |
| `reason(status: Integer)` | `String` | `"OK"`, `"Not Found"`, ...; `""` for an unknown code |

A status of 400 or more is not an error by itself (`data-language.md`); `answer.check()` raises. An `https://` URL raises `ConnectionError` text `"https needs the TLS client (level 9)"`. A refused connection is `$err_io` from `net`.
