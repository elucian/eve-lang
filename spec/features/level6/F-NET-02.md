# F-NET-02 HTTP server

Routes, request and response records, static files, one state per request.

*Partial (2026-10-11):* the machine with its two doors, IPC (`--listen`, was `-lsn` until) and HTTP (`--serve`: the web folder, `POST /rpc`), JSON-RPC methods `ping`, `status`, `run`, `stop`, the client options `-loc` and `-rem` (`spec/library/machine.md`); tests `e95_web_hello` and `e95` to `e95` pass. *2026-10-13:* the machine at the prompt (`listen`, `serve`, `stop`, the doors in threads, one thread per connection), `evevm` (the machine in its own process, log in a file) and `eve -u` (open the web page). Not yet: routes and `service` scripts, HTTPS, login, WebSocket. *2026-10-18:* HTTP and routes in Eve: the system module `net` (TCP), the Eve modules `http`, `route` and `service` (`spec/library/net.md`, `http.md`, `route.md`; benchmark p6e: 0.72 s for 300 requests against 0.5 s for Python). Not yet: keep-alive, one task for each connection, the machine's own routes in Eve (`f11`).
