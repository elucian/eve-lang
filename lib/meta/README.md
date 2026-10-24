# lib/meta: reference data

The meta database `meta.db` (SQLite, read only, in Git LFS) is embedded in `eve.exe`; the modules of this folder are its library door. Page: `spec/library/meta.md`.

| Module | Contents | Step |
|---|---|---|
| `zone` | time zones: `exists`, `canonical`, `offset`, `abbreviation`, `is_dst`, `names` | M0.1 |
| `meta` | `info(name)`: the releases of the sources | M0.1 |

The tables `continent`, `country` (with a continent) and `zone` (with a country) are read with SQL: `database.connect("meta")` (page: `spec/library/meta.md#sql`).

`meta.db` is generated: `python tools/meta/build_meta.py --fetch temp/meta-src` (downloads the pinned releases of tzdata and Unicode CLDR, then builds), or `--src temp/meta-src` to build from sources already there. Never edit it by hand. A clone needs `git lfs pull` before the build.
