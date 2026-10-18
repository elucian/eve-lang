# The module `crypto`

Status: **0.1-draft**, level 6 (D-189). Feature: F-LIB-10. Native module (Zig, `std.crypto`), signatures in `lib/sys/crypto.eve`. Tests: `test/level6/f04_crypto`. Registry: [registry.md](registry.md).

Hashes, a keyed hash, random bytes and the text codecs. A `String` is a sequence of bytes (UTF-8 text); a function that works on bytes takes and gives a `String`, and a digest is given as lower-case hexadecimal text.

| Function | Result | Meaning |
|---|---|---|
| `sha256(data: String)` | `String` (64 hex digits) | SHA-256 of the bytes of `data` |
| `sha512(data: String)` | `String` (128 hex digits) | SHA-512 |
| `sha256_file!(path: String)` | `String` | SHA-256 of a file, read in blocks (a big file does not fill the memory); `$err_file` when it can not be read |
| `hmac_sha256(key: String or Secret, data: String)` | `String` (64 hex digits) | HMAC-SHA-256 (RFC 2104) |
| `hex_encode(data: String)` / `hex_decode(text: String)` | `String` | bytes to hex and back; a bad digit is `$err_argument` |
| `base64_encode(data: String)` / `base64_decode(text: String)` | `String` | standard Base64 with padding (RFC 4648); a bad character is `$err_argument` |
| `random_hex!(n: Natural)` | `String` (2n hex digits) | `n` random bytes from the system generator; non-deterministic, so `!` (D-087) |
| `same(a: String, b: String)` | `Logic` | equality that takes the same time whatever the position of the first difference (for tokens and digests) |

`base64_decode` and `hex_decode` give bytes that need not be valid UTF-8; such a `String` can be written with `fs.write_bytes` after conversion, or compared, but printing it is the business of the caller.

A `Secret` given as key is read but never printed or logged (registry rule 5). The functions `md5` and `sha1` are **not** provided: they are broken for security and a file checksum is `sha256_file!`.

## Errors

| Case | Error |
|---|---|
| a bad hex or Base64 text | `$err_argument` |
| `sha256_file!` of a missing or unreadable file | `$err_file` |
| `random_hex!(-1)` or not a number | `$err_argument` |
