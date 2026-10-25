# F-LIB-09 Compression and archives

Gzip, zip, stream codecs (manifest). *State:* the gzip reader of `csv`, `json`, `txt` and `fs.lines!` works for a path that ends in `.gz` (test e152).

## Built

- `gzip.open!` as a `Stream(:Bytes)` (e154), a stream as the source of the readers of `csv`, `json`, `txt` and `fs.lines!` (e170), `Bytes` and `fs.read_bytes!`, the gzip writer and zip (e165, e166). The files are processed whole, in memory.

## Missing

Nothing.
