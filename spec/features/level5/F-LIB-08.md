# F-LIB-08 Secrets

A `Secret` type and `secret.get` from environment, file or vault. *Specified (2026-10-10):* `spec/library/data-language.md#secrets`.

## Missing

- `secret.get` from a file (environment works, the value is masked when printed); a vault is later.
- A test that a `Secret` never prints its value.
