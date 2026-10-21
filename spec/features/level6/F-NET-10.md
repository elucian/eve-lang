# F-NET-10 Time-outs of the waiting calls

`Socket.set_timeout(ms)` (a read fails with `$err_timeout`), `service.idle(ms)` and the reply `408`, `os.run!` with `timeout_ms` (status 124) (`spec/library/net.md#time-outs`; TD-27, TD-29).

*Open:* `accept!` has no time-out, one connection at a time (TD-29), no streaming `os.run!` (TD-9).
