<!-- Template of the release notes (policy: README.md of this folder). script/relnotes.py copies it to vX.Y.Z.md, removes this comment, writes the GEN blocks and keeps the rest. Replace every TODO by hand; `relnotes.py --check` fails while one is left. -->
# Eve X.Y.Z release notes

<!-- GEN:head (script/relnotes.py) -->
<!-- /GEN:head -->

## Highlights

TODO: three to six lines in plain words: what this release gives to a person who writes Eve or runs the machine. Name each feature with its code (`F-LNG-07`) and its stage.

## Features that changed stage

<!-- GEN:changes (script/relnotes.py) -->
<!-- /GEN:changes -->

## Decisions

TODO: the decisions settled since the previous release, one line each: `D-nnn` title (from `python script/plan.py list`). "None." when there are none.

## Breaking changes and migration

TODO: syntax or behaviour that changed for existing scripts, and how to migrate (the migration script, if any). "None." when nothing breaks.

## Known issues

TODO: tests that fail and why, features that went back a stage, open questions that block the next step (`Q-nnn`). "None." when there are none.

## Progress

<!-- GEN:progress (script/relnotes.py) -->
<!-- /GEN:progress -->

## Performance

<!-- GEN:performance (script/relnotes.py) -->
<!-- /GEN:performance -->

TODO: Performance notes: two to four lines from the paragraph of this version in "Notes by version" of test/bmark/README.md: what got faster or slower, and why.

## Links

<!-- GEN:links (script/relnotes.py) -->
<!-- /GEN:links -->

## Stage of every feature

<!-- GEN:stages (script/relnotes.py) -->
<!-- /GEN:stages -->
