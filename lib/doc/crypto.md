# crypto

Hashes, a keyed hash, random bytes and text codecs (F-LIB-10, D-189). Signature file: the body is native, in code/evevm/src/syslib.zig (cryptoModule).
@spec spec/library/crypto.md  @feature F-LIB-10  @decision D-189  @tests test/level6/f04_crypto

## `external function sha256(data: String) => (@result: String);`

SHA-256 of the bytes of data, as 64 lower-case hexadecimal digits.

## `external function sha512(data: String) => (@result: String);`

SHA-512 of the bytes of data, as 128 hexadecimal digits.

## `external function sha256_file!(path: String) => (@result: String);`

SHA-256 of a file.

## `external function hmac_sha256(key: String, data: String) => (@result: String);`

HMAC-SHA-256 (RFC 2104); the key is a String or a Secret.

## `external function hex_encode(data: String) => (@result: String);`

Bytes to hexadecimal text.

## `external function hex_decode(text: String) => (@result: String);`

Hexadecimal text to bytes; a bad digit is $err_argument.

## `external function base64_encode(data: String) => (@result: String);`

Standard Base64 with padding (RFC 4648).

## `external function base64_decode(text: String) => (@result: String);`

Base64 text to bytes; a bad character is $err_argument.

## `external function random_hex!(n: Natural) => (@result: String);`

n random bytes of the system generator, as 2n hexadecimal digits.

## `external function same(a: String, b: String) => (@result: Logic);`

Equality that takes the same time wherever the texts differ.

