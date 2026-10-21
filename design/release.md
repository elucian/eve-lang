# Release policy

Every release of the Eve virtual machine (`bin/eve.exe`, version in `code/evevm/src/version.zig`) has **release notes** in `manual/releases/` and **updates the manual**. The rule is decision D-153 (`python script/plan.py show D-153`). A release is a record: once tagged, its notes are never edited again; a mistake is corrected in the notes of the next release.

## What a release delivers

1. **Release notes** `manual/releases/vX.Y.Z.md`, made from [template.md](template/release-notes.md) by `script/relnotes.py`. Generated parts: the head (date, commit, previous release), the features that changed stage, the progress (tests and features), the performance (benchmarks against the previous release and against Python), the links, the stage of every feature. Written by hand: Highlights, Decisions, Breaking changes and migration, Known issues, Performance notes.
2. **The manual brought up to date** ([../README.md](../manual/README.md)): the progress paragraph and the links are generated at each release; the pages of the manual that describe what changed (for example [../usage.md](../manual/usage.md) for a new command or option) are edited by hand in the same commit.
3. **The project files**: the status of the features in spec/features, a paragraph for the version in "Notes by version" of [test/bmark/README.md](../test/bmark/README.md), the generated tutorial pages (`features.html`, `quality.html`).

## Stages of a feature

Each feature keeps its code `F-<area>-<nn>` from `spec/features/`. In the release notes a feature has one of three stages.

| Stage | Meaning | Read from `spec/features/` |
|---|---|---|
| `planned` | named for a level; work has not started. Counted, not listed | status `open` |
| `drafted` | the specification or the conformance tests are written (tests first), the implementation is missing or partial | status `partial` |
| `validated` | implemented in `bin/eve.exe` (or delivered, for tools and documents), its tests pass on the ReleaseSafe build | status `done` |

A stage is never written by hand in the notes: it follows the `status` of the feature in `spec/features/<level>.json`. When the stage is wrong, correct the status (with its decision), then generate the notes again. A feature moves forward one stage at a time as a rule.

## Versions

Versions are `X.Y.Z` (`script/release.py patch|minor|major`). While the version is `0.0.Z`, every release is a step toward Version 0.1 of the feature map; a minor version `0.Y.0` is released when every feature of its section is validated. Each release, even a patch, gets its notes.

## How to make a release

Run from the root of the repository, in this order. Each step must succeed before the next.

1. `python script/plan.py status` and `git status`: no work in progress is mixed with the release; the tree is committed.
2. Bump and build: `python script/release.py [patch|minor|major]` (rewrites the version labels, builds `bin/eve.exe`, runs `zig build test`; it restores the labels when the build fails).
3. Test on the ReleaseSafe build: `cd evevm && zig build -Doptimize=ReleaseSafe -p ../../temp/rel`, then `python script/runtest.py all --eve temp/rel/bin/eve.exe` (this saves the tracking file of every suite and regenerates the test pages).
4. Measure: `python script/bmark.py --build ReleaseSafe --eve temp/rel/bin/eve.exe --save`, then write the paragraph of the version in "Notes by version" of `test/bmark/README.md` (what changed, faster or slower, and why a drop of more than 10% happened).
5. Update the status of the features in `spec/features/` (and its overview counts) for what this release finished.
6. Generate: `python script/relnotes.py` (writes `vX.Y.Z.md`, the progress and the links of the manual, the list below).
7. Write by hand every `TODO` of `vX.Y.Z.md`: Highlights, Decisions (`python script/plan.py list`, the ids settled since the previous release), Breaking changes and migration, Known issues, Performance notes (a summary of the paragraph of step 4). Update the pages of the manual that describe what changed.
8. Check: `python script/relnotes.py --check` and `python script/mdlinks.py check manual` must report no problem.
9. Commit and tag: `git commit -am "Release X.Y.Z"` and `git tag vX.Y.Z`; commit the tutorial pages in the scl repository (`git -C tutorial`). Push only when the author asks.
10. Distribute (after the commit is pushed with its tag, when the author asks): `./run.sh dist` builds the Windows distribution in `dist/` (ReleaseSafe builds of `eve`, `evedb`, `evetx` and `eveux`, the folders `bin/`, `lib/`, `manual/`, `tools/`) and writes `dist/eve-X.Y.Z-windows-x64.zip` with `dist/SHA256SUMS.txt`; `./run.sh release` publishes both with `gh release create` as the release `vX.Y.Z`, with the notes of step 6. `./run.sh release --dry-run` prints the command without publishing. The folder `dist/` is git-ignored and is never committed.

## Links in the manual

The manual is read on GitHub and in a local clone, so every link must work in both:

- **Files of this repository** (`spec/`, `test/`, `design/`): a relative link to the exact path, with the exact case. GitHub is case-sensitive and Windows is not: the test folders hold `readme.md` in lowercase, `spec/` and `test/bmark/` hold `README.md`. `relnotes.py --check` compares every link with the files that git tracks.
- **The tutorial**: it lives in the scl repository and is git-ignored here, so a link to `tutorial/…` works in no clone. Link to the published page instead, `https://sagecode.org/projects/eve/<page>.html`; `--check` verifies that the page exists in the local `tutorial/` junction.

## Releases

The list of the releases, with their notes, is the page [manual/releases/README.md](../manual/releases/README.md) (its block `GEN:releases` is written by `script/relnotes.py`).
