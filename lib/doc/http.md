# http

HTTP/1.1 as text on a net Socket: read a request, write a response, call a server. One request for each connection.
@spec spec/library/http.md  @feature F-NET-02  @decision D-189  @tests test/level6/f10_route_hello

## `class Request = {verb: String, target: String, path: String, query: Any, headers: Any, body: String} <: Object is`

A request as the server reads it; verb is "" when the client closed before sending anything.

## `class HttpResponse = {status: Integer, headers: Any, body: String} <: Object is`

An answer as the client reads it.

## `function reason(status: Integer) => (@result: String) is`

The standard text of a status code.

## `function byte_length(text: String) => (@result: Integer) is`

The number of bytes of a text (length() counts runes).

## `function parse_query(text: String) => (@result: Any) is`

a=1&b=2 into a DataMap of texts.

## `function read_headers!(sock: Socket) => (@result: Any) is`

The headers after the first line, up to the empty line; names in lower case.

## `function read_request!(sock: Socket) => (@result: Request) is`

Read one request from the socket.

## `procedure respond(sock: Socket, status: Integer, body: String, headers = {:} :Any) is`

Write a response and nothing else; the caller closes the socket.

## `function exchange!(verb: String, url: String, body: String, headers: Any) => (@result: HttpResponse) is`

Send a request to http://host:port/path and read the whole answer.

## `function get!(url: String, headers = {:} :Any) => (@result: HttpResponse) is`

GET a URL; a status of 400 or more is not an error by itself (call check()).

## `function post!(url: String, body: String, headers = {:} :Any) => (@result: HttpResponse) is`

POST a body to a URL.

