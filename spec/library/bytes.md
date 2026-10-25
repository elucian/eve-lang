# Bytes and Uuid

Status: **Bytes built** (step D4: tests e139 to e141; the rows marked *not built* below wait for the steps named in the tech debt). `Uuid` is the step D5 and still a draft. Level 5, step S15.50. Features: F-LNG-13, F-LIB-06.

## Bytes

`Bytes` is an immutable sequence of bytes. It is not text: it is not checked as UTF-8, it has no rune and no case. It is what a file read in binary, the body of an HTTP response, a hash, a key and a `BLOB` column are. `Stream(:Bytes)` is the source of the readers ([data-language.md](data-language.md#bytes)).

| Item | Rule |
|---|---|
| Zero value | the empty sequence |
| Literal | none: `Bytes.from_hex("DEADBEEF")`, `Bytes.of(0xDE, 0xAD)`, `"text".bytes()` |
| Index | `b[1]` is the first byte, as a `Natural` from 0 to 255 (Eve counts from 1); an index outside 1 to the length is `$err_index` |
| Slice | `b[2..4]` is a new `Bytes`, a copy as for a String; `b[2..-1]` runs to the end |
| `+` | joins two `Bytes`; with another kind it is an error (`$err_argument`, a compile error once the checker knows the types: *not built*) |
| `==`, `<>`, `<` ... | by content; the order is byte by byte, a shorter prefix is smaller |
| `print` and `{b}` | the canonical text: `0x` and lower-case hexadecimal, `0xdeadbeef`; at most 64 bytes, then `…(n bytes)` with the length (`0x` and the first 64 bytes, then `…(1024 bytes)`) |
| `length()` | the number of bytes |
| `hex()`, `Bytes.from_hex(text)` | lower-case hexadecimal text and back; an odd length or a bad digit is `$err_argument` |
| `base64()`, `Bytes.from_base64(text)` | standard Base64 with padding (RFC 4648); a text that is not Base64 is `$err_argument` |
| `base64url()` | the URL alphabet without padding (RFC 4648, section 5); the reverse `from_base64url` is *not built* |
| `text()` | the `String` of the bytes as UTF-8; a sequence that is not valid is `$err_convert` (14); `text(encoding)` with `"latin1"` or `"utf16le"` is *not built* |
| `"text".bytes()` | the UTF-8 bytes of a `String` |
| `index_of(b)` | the position of the first `b` counted from 1, as `find` of a String; 0 when there is none |
| `contains(b)`, `starts_with(b)`, `ends_with(b)` | search; the argument is a `Bytes` |
| `Bytes.of(...)` | every argument is a whole number from 0 to 255, else `$err_argument` |
| `fs.read_bytes!(path)` | the content of a file as `Bytes`; `fs.write_bytes(path, b)` writes a `Bytes` (a list of whole numbers from 0 to 255 is still accepted) |
| `crypto.sha256(b)` and the other functions of `crypto` | accept `Bytes` as well as `String` and give `Bytes` with `bytes: True` *(not built)* |

A `Bytes` value is an immutable copy, never changed in place. A buffer to build is `BytesBuilder` *(proposed, not built)*: `new b := BytesBuilder(); b.append(x); b.append_u32le(n); let out := b.build();`.

SQL: `BLOB` (SQLite), `bytea` (PostgreSQL), `BLOB` (DuckDB). JSON: a text of Base64 with a field of type `Bytes`; CSV: the same; a `TXT` field is not allowed. *The SQL and file-format mappings are not built.*

## Uuid

`Uuid` is a 128-bit identifier (RFC 9562). It is a value of 16 bytes, not a text.

| Item | Rule |
|---|---|
| Zero value | the nil Uuid `00000000-0000-0000-0000-000000000000` (`Uuid.nil`) |
| Literal | none: `Uuid.parse("...")` |
| Canonical text | 36 characters, lower case, hyphens: `550e8400-e29b-41d4-a716-446655440000` |
| `Uuid.parse(text)` | accepts upper and lower case, with or without hyphens and braces; anything else is `$err_parse` |
| `uuid.v4!()` | random (RFC 9562 version 4), from the generator of the operating system |
| `uuid.v7!()` | time-ordered (version 7): the first 48 bits are the milliseconds of the clock, so a new id is not smaller than an older one made by the same machine; good for keys of a table |
| `uuid.v5(namespace, name)`, `uuid.v3(namespace, name)` | the same name in the same namespace gives the same id (SHA-1 and MD5, RFC 9562); `uuid.namespace_dns`, `namespace_url`, `namespace_oid`, `namespace_x500` |
| `u.version()` | `Integer`, 1 to 8 |
| `u.bytes()`, `Uuid.from_bytes(b)` | the 16 bytes and back; another length is `$err_argument` |
| `u.instant()` | for a version 7 the `Instant` of its time stamp, else `$err_argument` |
| `==`, `<>`, `<`, `>` | by the bytes, in order; a version 7 sorts by creation time |

The functions that give a new value end with `!` (`v4!`, `v7!`): they give another value at each call. SQL: `uuid` (PostgreSQL, DuckDB), `TEXT` of 36 characters (SQLite). JSON and CSV: the canonical text.

```eve
from lib use (uuid);
new id := uuid.v7!();
print id.version();                                         ** 7
print Uuid.parse("550E8400E29B41D4A716446655440000");       ** 550e8400-e29b-41d4-a716-446655440000
print uuid.v5(uuid.namespace_dns, "eve.example") == uuid.v5(uuid.namespace_dns, "eve.example");   ** True
print Bytes.from_hex("0a0b").base64();                      ** Cgs=
```
