# 01 Project, process and positioning (`RPJ`)

## Advantages

**RPJ-A01 Decisions are recorded with ids, dates and history.** `plan/decision_level*.md` keeps the question text after the answer, cross-links issues, and says what each decision was applied to. Few hobby or academic languages have this audit trail. Keep it.

**RPJ-A02 Test-first with an executable runner.** `script/runtest.py`, `expect.json`, `.out` files, exit-code conventions (D-009, D-010) and project tests as folders (D-073) give a real conformance harness. Level 1 (38 tests) passes on the VM. This is the right foundation for "many compilers, one specification" (D-003).

**RPJ-A03 Machine-readable spec tables.** JSON for operators, delimiters and keywords with schemas (D-001, `spec/schema/`) and generated feature tables in `manual/` (D-004) avoid the usual drift between prose and tools.

**RPJ-A04 Clear didactic mission.** "Learn how to build a compiler" is a coherent purpose that justifies a simple VM, Zig tips and a compiler page in the tutorial.

## Disadvantages

**RPJ-D01 Two missions pull in opposite directions.** *Answered 2026-10-04 by D-075: Eve is an enterprise ETL client/server platform; teaching is secondary.* Eve is (a) a teaching language for compiler students and (b) a production DSL for ETL, test automation and, now, a web/ETL server. A teaching language wants a tiny core; a production DSL wants batteries, data types and stability. The decisions do not say which one wins when they conflict (e.g. 1-based indexing and `$` last index help (b) little and cost students a special case in every lexer).

**todo** Drop the idea that EVE is for students. EVE is for enterpris professional ETL applications but this is not even important for what it is. Important is the implementation aspect and features. **RPJ-D01  Make the project single mission, professional ETL client/server environment. 

**RPJ-D02 The spec is mostly empty while tests and the VM advance.** `spec/` holds lexical rules, schemas and `semantics/variables.md`. Decisions D-030, D-032, D-036 announce "Spec additions: `spec/syntax/statements.md`, `spec/semantics/control.md`, `spec/semantics/types.md`, `spec/syntax/declarations.md`" — none of these files exist. Phases 3 and 4 have every step open (`plan/phase-3-syntax.md`, `phase-4-semantics.md`), while level 2 tests are being written (phase 5).

**todo** postpone specification implementation until tutorial is well defined.

**RPJ-D03 The tutorial lives in another repository under another license.** It is the reference the spec "builds on" (CLAUDE.md), yet it is versioned in `scl`, git-ignored here, and the scl repo is GPL-3.0 while the spec is CC BY 4.0 (D-061 note). A contributor cannot clone one repo and see the language.

**todo** nothing, we maintain /tutorial linked folder to /scl/projects/eve. After spec is well formed, we drop this link. Due in 5 years.

**RPJ-D04 BUSL-1.1 on the VM of an "open standard".** The VM is the only implementation and the conformance oracle. A non-OSI license, an "Additional Use Grant proposed by the model, to confirm" (D-061) and a strict trademark policy (D-062) will discourage exactly the third-party implementers and hosting providers a client-server platform needs.

**todo** Nothing, this is the intention. We need time before VM is ready for production when ideas will not need protection. Until then we need to focus on a single compiler. I do not have time to support other code base or external contributors.

**RPJ-D05 Scope promised far ahead of capability.** The manifest promises compression, encryption, database synchronization, archiving, image and video streams; the library today is `io.eve` (28 lines) and `exception.eve`. Readers judge a language by its promises.

**todo** drop scope that is not realistic actually scope is not necesary. We already have a version_map that describe what is included in every major version.

## Antipatterns

**RPJ-X01 Specification by implementation.** D-063 lists "model decisions taken while writing the interpreter"; Q-019 and Q-022 list rules that the tests "assume without a decision". When the VM and the tests decide, the language is whatever `interp.zig` does, which contradicts D-003 and the ground rule "the spec is normative". The tests become the spec, but tests show cases, not rules.

**todo** we postpone test implementation until spec is well formed. This was a warmup, we have created level1 and drafted a simple compiler to check how good AI is. Now that we know it can be done, we focus on /tutorial and postpone code maintenance and spec creation. 

**RPJ-X02 Design churn ("decision thrash").** About 70 decisions and questions between 2026-09-28 and 2026-10-03. Loop syntax changed in D-016, D-030, D-033, D-034 and D-045 (`repeat` removed, then re-added with another meaning; `cycle` added, then removed). Interpolation changed in D-059 and again in D-060 the same day. `new`/`let` swapped meaning in D-036. Each change rewrote 50 to 150 scripts. The cost is not the edits, it is that nobody can learn a moving target and that old pages (databases.html) silently stay in an older dialect.

**todo** we must cleanup history, to eliminate garbage and confusion. What is at the moment is most important. For now we work in main branch and we can change the hystory in Git. No other user is yet involved in this work.

**RPJ-X03 Model-proposed rules entering the language unreviewed.** Many entries say "proposed by the model", "assumed", "to confirm" (D-039, D-047, D-054, D-061, D-068, D-072). Some are applied to the tutorial before confirmation. An assumption applied to 10 pages becomes a decision by inertia.
**todo** Review. If they are wrong, we reffer them and review the decision. I hope the cost is not too high. Trial and error is a good approach.

**RPJ-X04 Feature design by keyword table.** The keyword table had 111 words, 30 never used (Q-002 evidence), many from database ideas that were dropped (`cursor`, `fetch`, `rollback`, `select`). Reserving words for features that have no design is premature.

**todo** Create back-log.md and move these reserved keywords. Draft ideas and possible keywords we need. EVE is a verbose language but we don't have to waste keywords just for fun.

## Recommendations

**RPJ-R01 Syntax moratorium for 0.1.** Freeze lexical rules, closers, declarations, assignment and control flow as they are after one cleanup pass (see `RSY-R*`). From then on a syntax change needs (1) a written problem, (2) evidence from tests, (3) a migration script. New ideas go to `plan/backlog-0.2.md`. Spend design energy on the library and on the client-server model, where Eve has nothing yet.

**todo** I try my best. 

**RPJ-R02 Grammar before more tests.** Derive the EBNF from `evevm/src/parser.zig` (1 226 lines) now (S3.1), check it against every `.eve` file (S3.6), and only then write level 2 and 3 tests. Every Q-019/Q-022 assumption becomes a sentence in the spec before the test that relies on it is merged.

**todo** bed idea, we draft specification from /tutorial not from code. The code will be revised and will refer specification items with code for faster identification.

**RPJ-R03 Decide the primary mission, write it down.** *Done 2026-10-04: D-075.* Recommended: "a production DSL for data pipelines whose implementation is small enough to teach". Then a tie-break rule: when teaching simplicity and production needs conflict, production wins in the language, teaching wins in the VM architecture.

**todo** Improve the primary mission. Make a draft directly in tutorial and readme. Primary mission is to create enterprise quality fast scripting language for ETL and Internet. Is a data oriented DSL and JIT compiler with gradual typing.

**RPJ-R04 Bring the tutorial source into this repo, or make the spec self-sufficient.** *Answered 2026-10-04 by D-075: the spec becomes self-sufficient; the tutorial stays in scl as didactic material.* Either move the tutorial HTML into `eve-lang/tutorial/` and let scl publish it as a submodule, or make `spec/` complete enough that the tutorial is only didactic. Align the license of the tutorial text with the spec (CC BY 4.0).

**todo** nothing, the tutorial already have a license page that specify (CC BY 4.0). Dual license is described in Readme.md 

**RPJ-R05 License the VM under Apache-2.0 or MPL-2.0 now, protect the brand with the trademark only.** *Rejected 2026-10-05; the documents moved to CC BY-NC-SA 4.0 instead (D-078).* The trademark policy (D-062) already prevents confusing forks; the BUSL adds friction without real protection for a project at version 0.0.1. If commercial protection is needed later, protect the hosted server product, not the client VM.
**todo** Rejected proposal. License is established already at advice from Gemini. I want to keep ownership of ideas and people can't make compilers and products based on these ideas. Except for learning and non profit with obligation to contribute back to specification and tutorial.

**RPJ-R06 Version map.** *Addressed 2026-10-04: [plan/version_map.md](../plan/version_map.md) and [plan/features_inventory.md](../plan/features_inventory.md).* Publish one table: feature → version (0.1 client core, 0.2 library + generators, 0.3 parallel aspects + channels, 0.4 server, 0.5 WebAssembly). Today "not in 0.1" (D-050), "version 2" (D-067) and "about 0.9" (D-031) use different scales.

**todo** good idea, done. 

**RPJ-R07 Retire `demo/` now.** *Rejected 2026-10-04 by D-075: demos stay as ideas, never run or parsed.* D-065 already decided it; 16 demos still need VM work and 30 tutorial copies carry old errors. Convert the 29 running demos to tests in one pass and delete the folder.

**todo** move demo in /tutorial/projects/eve/demo folder that is missing. then we maintain demo and create a page for it, to view eve code with scl code viewer.
