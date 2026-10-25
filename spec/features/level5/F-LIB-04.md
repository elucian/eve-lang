# F-LIB-04 Files and paths

`fs` module (files, folders, paths, lines, globbing), text and bytes. *State:* `fs` files, folders, lines, the path functions and globbing work (e151); the path functions are in `fs`, not in a `path` module (data-language.md#files-and-paths).

## Missing

- Built: `Bytes` and `fs.read_bytes!` (D4), `gzip.open!` as a stream of Bytes (e154). Not yet: a stream of Bytes as the source of a reader (TD-83).
