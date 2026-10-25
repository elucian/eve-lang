# F-LIB-08 Secrets

A `Secret` type and `secret.get` from environment, file or vault. *Specified (2026-10-10):* `spec/library/data-language.md#secrets`.

## Built

- `secret.get` from the environment and from a file (`EVE_SECRET_<NAME>_FILE`), a `Secret` printed as `***` alone, in interpolation and in collections, a `Secret` as key of `crypto.hmac_sha256` (tests e29, e76, e79, e103, e163). A vault is later (level 6, the machine).

## Missing

Nothing.
