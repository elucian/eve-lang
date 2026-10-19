# service

Serve a route table on a Listener: one connection at a time, one request for each connection.
@spec spec/library/route.md  @feature F-NET-02, F-STR-08  @decision D-189  @tests test/level6/f10_route_hello

## `procedure handle(sock: Socket, routes: Any) is`

Read one request on the socket, write the reply of the route table, close the socket. A bad request gets a 400.

## `procedure serve(server: Listener, routes: Any, count: Integer) is`

Accept and handle count connections (0: until the listener is closed).

