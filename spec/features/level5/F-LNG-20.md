# F-LNG-20 Generic functions and procedures

A first parameter list of types, `function largest(:T <: Comparable)(items:T)`, called `largest(xs)` (types inferred) or `largest(:Integer)(xs)`; also procedures, methods and processes; no type list on a lambda, overloaded functions instead; possible because self-calling lambdas are removed. All its tests pass (2026-10-20, see Tests).
