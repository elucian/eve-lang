# F-STR-11 `recover` in a function, procedure and method

The end of `recover` handles the error and the routine returns normally; `abort` passes it on; no `recover` in a constructor, generator or lambda (`spec/semantics/errors.md`; 2026-10-18).
