# F-LIB-09 Compression and archives

Gzip, zip, stream codecs (manifest). *State:* the gzip reader of `csv`, `json`, `txt` and `fs.lines!` works for a path that ends in `.gz` (test e152).

## Missing

- Built: `gzip.open!` as a `Stream(:Bytes)` in chunks of 64 KiB (test e154).
- Not yet: a `Stream(:Bytes)` as the source of a reader (`csv`, `json` from a stream; TD-83).
- The gzip writer (`gzip.write`, and `.gz` paths in the writers of `csv`, `json` and `txt`) and zip (`zip.write`, `zip.list!`, `zip.read!`): level 5, proposed API in `data-language.md#compression`.
