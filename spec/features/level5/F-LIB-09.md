# F-LIB-09 Compression and archives

Gzip, zip, stream codecs (manifest). *State:* the gzip reader of `csv`, `json`, `txt` and `fs.lines!` works for a path that ends in `.gz` (test e152).

## Missing

- Built: `gzip.open!` as a `Stream(:Bytes)` in chunks of 64 KiB (test e154); the gzip writer `gzip.write` and the `.gz` paths of the writers of `csv`, `json` and `txt` (test e165); zip: `zip.write`, `zip.list!`, `zip.read!` (test e166, archives checked with Python's `zipfile`).
- Not yet: a `Stream(:Bytes)` as the source of a reader (`csv`, `json` from a stream; TD-83); the files are inflated and deflated whole, in memory.
