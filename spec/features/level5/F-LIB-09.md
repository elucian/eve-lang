# F-LIB-09 Compression and archives

Gzip, zip, stream codecs (manifest). *State:* the gzip reader of `csv`, `json`, `txt` and `fs.lines!` works for a path that ends in `.gz` (test e152).

## Missing

- `gzip.open!` as a `Stream(:Bytes)`: the streams of Bytes are not built (TD-88).
- Zip and the gzip writers: level 6 in `data-language.md`.
