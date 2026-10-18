# Gaps of the language found while writing the standard library (D-189)

One line per gap: what was missing or wrong, found by which module, where it should be fixed. Fix the language, never work around it in the library.

- **G-1** An error raised in a module of the standard library reports the file name of the *calling* script with the line of the module (`f03_test_module.eve:71` for a line of `lib/test.eve`). Found by `test`. Fix: the frame and the error carry the file of the code that raised.
- **G-2** The unhandled `raise "message"` ends with exit code 4; a test runner may want its own code. There is no `exit <code>` statement. Found by `test`. Decide (Q): `exit <code>;` or `$exit_code`.
- **G-3** A user module that declares `external` cannot be bound to a native (D-191 (4)). Found by the signature files.
