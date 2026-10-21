# test Level 4

This level tests parallel processing and streams, and generics and traits (D-138): parallel groups, channels, streams, region memory (version 0.3, design/decision/level4.md). Tests are deterministic: the same input gives the same output and the same errors in the same order.

A test is a single file (`d17_job_spawn.eve`) or a project folder (D-073): `test/level4/d04_parallel_group/` holds the driver `d04_parallel_group.eve` and its `asp/` and `lib/`; the expectations are in the `/*@expect*/` block of the driver. Test names start with `d`. The specification is `spec/semantics/multitasking.md` and `spec/syntax/declarations.md#traits-and-generic-classes` (D-140 to D-145). Tests d04 to d35 were written before the VM (TDD, 2026-10-08) and pass on stage A of the VM (D-144). A compile-error test also checks the message (`contains`: the VM writes compile errors to the standard output), so it passes only for the right error. Run `python script/runtest.py 4 --repeat 100` to check that the results are the same at every run.

## Tests

The tests and the result of the last run are in `level4.json` of this folder (written by the test runner after every run).
