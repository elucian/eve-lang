# F-LIB-04 Files and paths

`fs` and `path` modules, text and bytes, line streams, globbing. *State:* `fs` files, folders and lines work; a `path` module, bytes and globbing are not done.

## Missing

- A `path` module (`path` is an undefined name).
- Globbing (`fs.glob` does not exist).
- Built: `Bytes` and `fs.read_bytes!` (D4). The Bytes of the formats (`gzip`, `zip`, the streams of `Stream(:Bytes)`) are not.
