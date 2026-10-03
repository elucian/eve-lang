<p align="center">
<a href="https://sagecode.org/projects/eve" target="_blank" align="center">
<img src="https://sagecode.org/projects/eve/img/eve-logo.svg" alt="Eve Logo" width="140"></img>
</a>
</p>

<p align="center"><em>Effective Virtual Environment</em> &middot; Version <strong>0.0.1</strong></p>

<p>Eve is a domain specific scripting language for data processing and test automation. We design the language and we create code examples in this repository. This language is a standard in design and developement. It will have many interpreters and compilers implemented by diverse other organizations. First compiler is implemented in Zig, and belong to this repository.</p>

  
## Learning

You can learn Eve on our website: [sagecode.org](https://sagecode.org). After you learn the syntax you can start contributing, or just watch. We design Eve for learning how to make a compiler. We will add examples that demonstrate how we can use Eve for teaching programming concepts, algorithms and data structures.

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

### Everything else: CC BY 4.0

Everything outside `evevm/` (specification, manual, examples, tests, plans, scripts) is under Creative Commons Attribution 4.0 (CC BY 4.0). Anyone may write an Eve implementation using our specification. Full text: [spec/LICENSE](spec/LICENSE).

### Trademark

The name "EVE" and the logo are trademarks of Sage-Code Laboratory. See [TRADEMARK.md](TRADEMARK.md).

---
Copyright (c) 2024 - 2026 Sage-Code
