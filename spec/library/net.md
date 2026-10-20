# The module `net`

Status: **draft**, level 6 (D-189). Features: F-NET-02, F-NET-03. Native module (Zig), signatures in `lib/sys/net.eve`; code in `code/evevm/src/netlib.zig`. Tests: `test/level6/f09_net`. Registry: [registry.md](registry.md).

TCP for Eve code: a client connection and a listening server, as text. The module is the base of `rpc`, of the HTTP routes and of the machine-to-machine calls; it holds no protocol. Every address is a host name or an IP literal and a port; the machine itself listens only on `127.0.0.1` unless the configuration says otherwise (D-189: level 6 is tested on `localhost`).

```eve
async procedure echo(server: Listener) is
  new peer := server.accept!();
  peer.write("echo: {peer.read_line!()}\n");
  peer.close();
return;

process main is
  new server := net.listen!("127.0.0.1", 0);
  work: job
  do
    spawn echo(server);
    new c := net.connect!("127.0.0.1", server.port());
    c.write("hello\n");
    print c.read_line!();
    c.close();
  done work;
  server.close();
return;
```

## Functions

| Function | Result | Meaning |
|---|---|---|
| `net.listen!(host: String, port: Integer)` | `Listener` | opens a listening socket; port `0` lets the system choose (read it with `port()`); `$err_io` when the address is in use |
| `net.connect!(host: String, port: Integer)` | `Socket` | connects to a server; `$err_io` when it is refused or unreachable |

`Listener`: `accept!()` gives the next `Socket` (waits for a client); `port()` the port number; `close()`.

`Socket`: `read_line!()` the next line without its line ending (LF or CR LF), or `Null` at the end of the stream; `read!(n: Integer)` up to `n` bytes as text, waiting for at least one, `""` at the end of the stream; `read_exact!(n)` exactly `n` bytes or `$err_io` at the end; `write(text: String)` sends all of the text; `set_timeout(ms)` limits the wait of the reads ([Time-outs](#time-outs)); `close()`; `is_open()`; `peer()` the address of the other side as `"host:port"`.

## Waiting

A call that waits (`accept!`, `read_line!`, `read!`, `read_exact!`) gives the baton to the other tasks of the run (`multitasking.md`) while it waits, so a server and its clients can be tasks of one script, as in the example: the call runs on a helper thread and the task sleeps on the scheduler (state `io`) until the helper ends. Outside any task the call simply waits in the system. A task cancelled while it waits leaves its helper thread to end by itself (TD-28). `Listener.close()` while an `accept!` waits wakes that call (the module connects to the listener once and drops the connection); the `accept!` then raises `$err_io` "the listener is closed", which is how a `service.serve(server, routes, 0)` task ends.

## Time-outs

`Socket.set_timeout(ms: Integer)` sets how long a read (`read_line!`, `read!`, `read_exact!`) may wait: 0 (the default) waits for ever. A read that waits longer raises `$err_timeout` (41, `Time-out after {n} ms`). After a time-out the socket is **abandoned**: it can still be written (`write`) and closed, but not read again, because the helper thread of the read is still waiting in it; the system drops the connection when the other side ends. `accept!` has no time-out: a server ends its loop by closing the listener. Tests: `test/level6/f13_net_timeout`, `f14_service_idle`.

## Errors

| Case | Error |
|---|---|
| refused, unreachable or address in use | `$err_io` with the reason |
| `write`, `read_line!` on a closed socket | `$err_io` |
| a bad argument (a port outside 0 to 65535, a text that is not a String) | `$err_argument` |
