<p align="center">
<a href="https://sagecode.org/projects/eve" target="_blank" align="center">
<img src="https://sagecode.org/projects/eve/img/eve-logo.svg" alt="Eve Logo" width="140"></img>
</a>
</p>

<p align="center"><em>Effective Virtual Environment</em> &middot; Version <strong>0.0.1</strong></p>

<p>Eve is a data-centric DSL built for internet ETL pipelines. It provides a gradual typing JIT compiler and virtual machine. This new language delivers a unified syntax for data transforming and routing between local client and server backend. This repository holds the specification, the tests and the first implementation, the Eve virtual machine written in Zig.</p>

  
## Learning

You can learn Eve on our website: [sagecode.org](https://sagecode.org). The tutorial explains the language with examples. The features and their versions are planned in [plan/features_inventory.md](plan/features_inventory.md) and [plan/version_map.md](plan/version_map.md).

Read Sage-Code Tutorial: [Eve Programming Language](https://sagecode.org/projects/eve/index.html)</a>

## Testing

Our next priority is to create a "conformity test". This require test automation for future compilers. Our job is to create the standard examples required for testing. We write test first (TDD). In the future will have many interpreters and compilers that can use our these test framework for Eve.
  
## Contribution

You can contribute in 2 ways: First you can start a discussion or participate. Second, you can open and resolve work items. You can signal an error and you assign yourself to solve it. Then you solve it and commit your code or make a PR. If you have direct access on Eve repository you should create a developement branch. When a feature is ready, merge the code into main branch and signal on Discord.

# Compiler Manual

The compiler manual documents an Eve implementation: how to implement it, how to use it, what was implemented, and which features of the specification it supports. The feature tables are generated from the specification. Every other compiler can use the same layout for its own manual, with reference to this one.

Open: [Eve Compiler Manual](manual/README.md)

You can contribute to this documentation. Connect to Eve User Manual and reverse engineer the original documentation. Then add technical details and expand the concepts. Connect with examples of code and test use-cases.

WORK IN PROGRESS, CONTRIBUTORS ARE WELCOME

---

## License

We use 2 licenses:

### Eve virtual machine: Business Source License 1.1

The code in `evevm/` is under the Business Source License 1.1. On 2 October 2030 it becomes Apache License 2.0. Full text: [evevm/LICENSE](evevm/LICENSE).

### Everything else: CC BY-NC-SA 4.0

Everything outside `evevm/` (specification, tutorial text, manual, examples, tests, plans, scripts) is under Creative Commons Attribution-NonCommercial-ShareAlike 4.0 (CC BY-NC-SA 4.0). The code snippets and examples shown in the tutorial are under the Apache License 2.0, as the Sage-Code Laboratory licensing of the scl repository says. You may use and adapt it for learning, research and non-profit work, with credit and under the same license. A commercial implementation or product based on Eve needs written permission from the author. Full text: [spec/LICENSE](spec/LICENSE).

### Trademark

The name "EVE" and the logo are trademarks of Sage-Code Laboratory. See [TRADEMARK.md](TRADEMARK.md).

---
Copyright (c) 2024 - 2026 Sage-Code
