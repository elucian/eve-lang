# Identifiers and checks

Status: **draft**, level 3. Library step L9. Written in Eve (`lib/ids/`), with two native hash functions in [crypto.md](crypto.md). Feature: F-LIB-03.

The identifiers of the program: ULID, short texts of UUID, random ids, and the check digits of numbers that people type. The `Uuid` type and its versions (`uuid.v4!`, `uuid.v7!`, `uuid.v3`, `uuid.v5`) are in [bytes.md](bytes.md); compression and archives are `gzip` and `zip` ([data-language.md](data-language.md#compression)). A wrong argument is `$err_argument` (17).

## Rules of import

`from lib use (ids);` gives the functions of the three modules `base32`, `ulid` and `check` as members of `ids` and the modules themselves (`ids.base32`, `ids.check`); a module can be imported alone, `from lib/ids use (ulid);`.

## Hash functions of crypto

| Function | Result | Meaning |
|---|---|---|
| `crypto.crc32(data)` | `Integer` | the CRC-32 checksum of the bytes (IEEE 802.3, as in zip and gzip), 0 to 4294967295 |
| `crypto.fnv1a(data)` | `Integer` | the FNV-1a hash of 32 bits, for tables and partitions |

Neither is a safe hash: they find a damaged file or spread rows, they do not protect against an attacker (use `crypto.sha256`).

## Module base32

The alphabet of Douglas Crockford: `0123456789ABCDEFGHJKMNPQRSTVWXYZ` (no I, L, O and U), 5 bits for a character. Bytes are given and returned as hexadecimal text.

| Function | Result | Meaning |
|---|---|---|
| `alphabet` | `String` | the 32 characters, in order of value |
| `encode(hex)` | `String` | the bytes as base32; the last character is padded with zero bits; an odd number of digits or a character that is not a hexadecimal digit is `$err_argument` |
| `decode(text, bytes)` | `String` | the hexadecimal text of the given number of bytes; small letters are read as capital ones; a character outside the alphabet or a text of the wrong length for the bytes is `$err_argument` |

## Module ulid

A ULID is 26 characters of base32: 10 for the time in milliseconds since 1970 (48 bits) and 16 for 80 random bits. ULIDs made in different milliseconds sort, as texts, in the order of their time.

| Function | Result | Meaning |
|---|---|---|
| `ulid_from(at, entropy)` | `String` | the ULID of an instant and 20 hexadecimal digits (10 bytes) |
| `ulid!()` | `String` | a new ULID: the time now and random bytes of the system |
| `time_of(text)` | `Instant` | the instant of a ULID, to the millisecond |
| `is_ulid(text)` | `Logic` | is the text 26 characters of the alphabet, the first at most 7 |
| `short(id)`, `from_short(text)` | `String`, `Uuid` | the 128 bits of a `Uuid` in 26 base32 characters, and back |
| `nanoid_from(entropy, size, alphabet)` | `String` | `size` characters of an alphabet (64 URL-safe characters by default) picked from the random bytes of a hexadecimal text; a byte that would make some characters likelier is skipped, and an entropy that is too short is `$err_argument` |
| `nanoid!(size, alphabet)` | `String` | a new random text (21 characters by default) |

## Module check

| Function | Result | Meaning |
|---|---|---|
| `luhn_digit(payload)` | `Integer` | the Luhn check digit to append to digits: `luhn_digit("7992739871")` is 3 |
| `luhn_valid(number)` | `Logic` | does the last digit of the number agree with the others by the Luhn rule (cards, identity numbers); spaces and dashes are ignored |
| `isbn13_digit(payload)` | `Integer` | the check digit of the first 12 digits of an ISBN-13 or an EAN-13 |
| `isbn13_valid(text)` | `Logic` | is the text 13 digits with the right check digit; spaces and dashes are ignored |
| `iban_valid(text)` | `Logic` | is the text an IBAN (ISO 13616): two capital letters, two digits, 11 to 30 letters and digits, and the check of the number modulo 97; spaces are ignored and small letters are read as capital ones; the length of the national form is not checked |
| `iban_digits(country, account)` | `String` | the two check digits of an IBAN for a country (two letters) and the national account number: `iban_digits("GB", "WEST12345698765432")` is `"82"` |

A text that holds a character that is not a digit, where only digits are allowed, is `$err_argument`; a text of the wrong shape for `iban_valid` and `isbn13_valid` is `False`.
