# 09 Client-server, protocol, web and WebAssembly (`RNW`)

Target: today a **client** (the Eve VM runs scripts that pull and push data, call services, write files); tomorrow a **server** that runs Eve aspects behind an efficient protocol, serves data and HTML like a web server, and ships Eve code to browsers through WebAssembly.

## Advantages

**RNW-A01 Aspects are already RPC-shaped.** Copy-in parameters, owned `@` outputs, no public members, state per call, errors re-raised at the call site with `{code, message, line}` (D-066, D-072). Replace "call site" with "client" and "state per call" with "per request" and you have a server handler contract. No language change is needed to make an aspect remote; only a transport.

**RNW-A02 M:N scheduling is already designed.** "A waiting aspect gives its core away" (D-067) is the property a server needs to hold 10 000 connections on 8 cores.

**RNW-A03 No shared mutable state by construction.** Modules without public variables (D-068), channels as the only shared object. A server built on these rules has no request-to-request leaks.

**RNW-A04 Purity in signatures.** Plain functions (D-025, D-027) can run on the client, on the server, or in the browser with identical results: the basis for code mobility.

**RNW-A05 Zig targets WebAssembly natively.** The VM can run in the browser without a rewrite (`RVM-A01`).

## Disadvantages

**RNW-D01 Nothing in the design talks about the network.** No socket, no HTTP, no URL type, no TLS, no serialization format, no notion of a remote aspect or a remote channel. The tutorial mentions "transfer data & upload data in the cloud" (databases.html) and nothing more.

**RNW-D02 No serving model.** A driver is a single master that ends; there is no long-running entry point, no request/response values, no routing, no static files, no lifecycle (start, drain, stop) (`RST-D01`).

**RNW-D03 No HTML story.** Interpolation (`\s{}`) is not context-aware: building HTML with it is an XSS hole. There is no template file format, no escaping rules, no `Html` type.

**RNW-D04 No security model.** `call` runs any shell command, `$NAME` exposes every environment variable (D-052), `external` binds native code, libraries are found by search paths (`$EVE_LIB`, `$EVE_ASP`, D-055). A server that runs Eve code from several teams (or the browser that runs code from a server) needs sandboxing and permissions.

**RNW-D05 Source as the deployable artifact.** Today scripts are found by name in folders and parsed at load. Shipping source to a browser or to a remote worker means re-parsing, trusting search paths, and no integrity check.

## Antipatterns to avoid when the server is designed

**RNW-X01 Inventing a transport.** A custom TCP protocol for everything (web pages included) means writing your own TLS integration, proxies, load balancers, debugging tools and browser support. Use HTTP where the web is, and a custom protocol only where it buys something measurable (streaming typed batches between Eve nodes).

**RNW-X02 Transparent remoting.** Making a remote `apply` look exactly like a local one hides latency, partial failure, and retries (the "fallacies of distributed computing"). The call must be visibly remote and carry a timeout and an idempotency key.

**RNW-X03 Server-side string templating of HTML.** See `RNW-D03`.

**RNW-X04 Eval of code received over the network.** If the browser or a worker receives Eve code, it must be signed bytecode with declared capabilities, never source passed to `eval`.

## Recommendations

**RNW-R01 The aspect is the unit of distribution.** One contract, three placements:

```eve
apply clean_rows(input, @output);                     ** local, serial (today)
parallel do start clean_rows(part, @out[i]); done;    ** local, parallel (D-066)
apply clean_rows(input, @output) at etl_node within 30s;  ** remote: visible, timed (proposal)
```

`at <endpoint>` names a configured node (not a URL in code); `within` sets the deadline; the error model is unchanged plus two codes (`unreachable`, `timeout`). Parameters and outputs must be serializable types (no channels, no generators, no closures — D-067 rule 6 already says this for `start`).

**RNW-R02 A `service` script kind for the server.**

```eve
service shop is
  use (http, db);
  set pool := db.pool("orders", size: 20);         ** created once, closed at shutdown
  route get  "/orders/{id}"   apply get_order;     ** each request: a fresh aspect state
  route post "/orders"        apply create_order;
  route get  "/static/*"      files "web/static";
  stream "/feeds/orders"      apply order_feed;    ** server push / EWP stream
end shop;
```

An aspect handler receives a `Request` record and writes `@response`. Lifecycle: `initialize` (pools, caches), request loop (one arena per request, `RVM-R02`), `finalize` on drain. The driver rules stay unchanged.

**RNW-R03 Two protocols, one data model.**

| Use | Protocol |
|---|---|
| Browsers, REST clients, HTML, files | HTTP/1.1 + HTTP/2 (later HTTP/3), JSON and HTML bodies |
| Eve client ↔ Eve server, server ↔ server data | **EWP**, Eve Wire Protocol, below |

**RNW-R04 EWP, a small framed binary protocol.** Over TCP+TLS (or QUIC later), and over WebSocket for browsers.

- Frame: `length (u32) | type (u8) | stream id (u32) | flags (u8) | payload`.
- Types: `HELLO` (version, capabilities, auth), `APPLY` (aspect name, args, deadline, idempotency key), `RESULT` (`@` outputs), `ERROR` (code, message, line, data), `BATCH` (a slice of a stream), `CREDIT` (flow control: how many batches the receiver accepts — the network form of channel capacity), `CANCEL`, `PING`, `CLOSE`.
- Payload: a self-describing binary encoding of Eve values (start from CBOR, RFC 8949, with tags for Decimal, Instant, Record), and for `BATCH` a columnar layout compatible with Apache Arrow IPC, so a Table moves without per-row encoding and other tools can read it.
- Multiplexed streams: one connection carries many `APPLY`s and streams; head-of-line blocking is handled by QUIC later.
- Resumable streams: `BATCH` carries a sequence number; after reconnect the client sends the last acknowledged one — this is the checkpoint of `RIO-R05` on the wire.

**RNW-R05 Safe HTML by type.** A `Html` type that is produced only by templates or `html.escape`, and a template literal or file (`.evh`) where `{expr}` is escaped by context (text, attribute, URL, script). `http.respond(html)` accepts `Html`, not `String`. Optionally components: a function `fn card(o: Order) -> Html`.

**RNW-R06 WebAssembly in three steps.**

1. **VM in the browser.** Compile `evevm` to `wasm32-freestanding`; host imports for console, fetch, timers. The tutorial gets a "Run" button on every example — the best teaching feature Eve could have.
2. **Eve on the client page.** The server ships signed `.evb` bytecode (`RVM-R05`); the browser VM runs pure functions and aspects that only have the `net` capability towards their origin; DOM access through a small `dom` module.
3. **Eve compiled to WASM** (later, optional): an ahead-of-time backend for hot pure functions. Not before the bytecode is stable.

Prefer the WebAssembly Component Model / WASI for host interfaces on the server side, so Eve components can be hosted by other runtimes too.

**RNW-R07 One data model end to end.** The same `record` types describe a CSV row, a database row, a JSON body, an EWP payload and a browser form. A schema registry is just a module of record types imported by client and server.

**RNW-R08 Capabilities.** The project file declares what it may use (`fs: read "data/", write "out/"`, `net: "api.example.com"`, `db: "orders"`, `shell: no`); each aspect declares what it needs; the VM refuses the rest. A `Secret` type (`RIO-R01`) is never printable or serializable except to its sink. The browser VM gets no `fs`, no `shell`, `net` only to its origin.

**RNW-R09 Observability built in.** Every request and every job carries a trace id; job events, `apply` durations and errors go to a structured log (JSON lines) and optionally OpenTelemetry. Debugging a distributed ETL without this is guesswork.

**RNW-R10 Client first, but on the server's foundations.** Build in this order: (1) `http` client + `json` + `fs` in the client VM, (2) bytecode + per-call arenas, (3) EWP client against a test server written in the VM's serve mode, (4) the `service` kind, (5) WASM VM. Each step is useful alone and none has to be undone by the next.
