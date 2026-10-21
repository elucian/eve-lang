# F-DAT-04 Checkpoints and restart

Resume a failed pipeline at the last committed batch. *Specified (2026-10-10):* checkpoints in the target database, `commit;` in a job (`spec/library/database.md#transactions`). *State:* `commit;` with a checkpoint is tested; restart of a killed load from its checkpoint is not tested yet.
