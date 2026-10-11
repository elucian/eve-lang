# Release policy

Every release of the Eve virtual machine (`bin/eve.exe`, version in `evevm/src/version.zig`) has **release notes** in this folder and **updates the manual**. The rule is decision D-153 (`python script/plan.py show D-153`). A release is a record: once tagged, its notes are never edited again; a mistake is corrected in the notes of the next release.

## What a release delivers

1. **Release notes** `manual/release/vX.Y.Z.md`, made from [template.md](template.md) by `script/relnotes.py`. Generated parts: the head (date, commit, previous release), the features that changed stage, the progress (tests and features), the performance (benchmarks against the previous release and against Python), the links, the stage of every feature. Written by hand: Highlights, Decisions, Breaking changes and migration, Known issues, Performance notes.
2. **The manual brought up to date** ([../README.md](../README.md)): the progress paragraph and the links are generated at each release; the pages of the manual that describe what changed (for example [../usage.md](../usage.md) for a new command or option) are edited by hand in the same commit.
3. **The project files**: the status of the features in [version_map.md](../../plan/version_map.md), a paragraph for the version in "Notes by version" of [test/bmark/README.md](../../test/bmark/README.md), the generated tutorial pages (`features.html`, `quality.html`).

## Stages of a feature

Each feature keeps its code `F-<area>-<nn>` from [version_map.md](../../plan/version_map.md). In the release notes a feature has one of three stages; a feature that has none of them is *planned* and is only counted.

| Stage | Meaning | Evidence | Read from `version_map.md` |
|---|---|---|---|
| `design` | what the feature is, is decided or proposed in writing; nothing is built | a decision `D-nnn`, a design file (`plan/design-*.md`, `<tool>/README.md`), a tutorial page | status `open`, the description names a decision or a design file |
| `drafted` | the specification or the conformance tests are written (tests first), the implementation is missing or partial | spec text, tests in `test/levelN/` that may still fail | status `partial`, or `open` with tests "written first" |
| `validated` | implemented in `bin/eve.exe` (or delivered, for tools and documents), its tests pass on the ReleaseSafe build | the tests pass; the feature is `✓ done` | status `✓ done` |

A stage is never written by hand in the notes: it follows the row of the feature in `version_map.md`. When the stage is wrong, correct the status or the description of the row (with its decision), then generate the notes again. A feature moves forward one stage at a time as a rule; a feature that goes back (a validated feature whose tests fail) is a known issue of the release and is named in its notes.

## Versions

Versions are `X.Y.Z` (`script/release.py patch|minor|major`). While the version is `0.0.Z`, every release is a step toward Version 0.1 of the [version map](../../plan/version_map.md); a minor version `0.Y.0` is released when every feature of its section is validated. Each release, even a patch, gets its notes.

## How to make a release

Run from the root of the repository, in this order. Each step must succeed before the next.

1. `python script/plan.py status` and `git status`: no work in progress is mixed with the release; the tree is committed.
2. Bump and build: `python script/release.py [patch|minor|major]` (rewrites the version labels, builds `bin/eve.exe`, runs `zig build test`; it restores the labels when the build fails).
3. Test on the ReleaseSafe build: `cd evevm && zig build -Doptimize=ReleaseSafe -p ../temp/rel`, then `python script/runtest.py all --eve temp/rel/bin/eve.exe` (this saves `status.json` of every level and regenerates the test pages).
4. Measure: `python script/bmark.py --build ReleaseSafe --eve temp/rel/bin/eve.exe --save`, then write the paragraph of the version in "Notes by version" of `test/bmark/README.md` (what changed, faster or slower, and why a drop of more than 10% happened).
5. Update the status of the features in `plan/version_map.md` (and its overview counts) for what this release finished.
6. Generate: `python script/relnotes.py` (writes `vX.Y.Z.md`, the progress and the links of the manual, the list below).
7. Write by hand every `TODO` of `vX.Y.Z.md`: Highlights, Decisions (`python script/plan.py list`, the ids settled since the previous release), Breaking changes and migration, Known issues, Performance notes (a summary of the paragraph of step 4). Update the pages of the manual that describe what changed.
8. Check: `python script/relnotes.py --check` and `python script/mdlinks.py check manual` must report no problem.
9. Commit and tag: `git commit -am "Release X.Y.Z"` and `git tag vX.Y.Z`; commit the tutorial pages in the scl repository (`git -C tutorial`). Push only when the author asks.

## Links in the manual

The manual is read on GitHub and in a local clone, so every link must work in both:

- **Files of this repository** (`spec/`, `test/`, `plan/`): a relative link to the exact path, with the exact case. GitHub is case-sensitive and Windows is not: the test folders hold `readme.md` in lowercase, `spec/` and `test/bmark/` hold `README.md`. `relnotes.py --check` compares every link with the files that git tracks.
- **The tutorial**: it lives in the scl repository and is git-ignored here, so a link to `tutorial/…` works in no clone. Link to the published page instead, `https://sagecode.org/projects/eve/<page>.html`; `--check` verifies that the page exists in the local `tutorial/` junction.

## Releases

<!-- GEN:releases (script/relnotes.py) -->
No release notes yet.
<!-- /GEN:releases -->
