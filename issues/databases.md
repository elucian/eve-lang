# Issues: databases.html

Page: `tutorial/databases.html` (342 lines, "Eve Database/SQL"). Reviewed 2026-09-28. How to
answer: [README](README.md).

## Questions

### DB-01 Scope
test/readme.md puts databases in level 3 ("a long time until we have level 3 tests"). Should this
page say clearly that it is a design for a later version, not part of 0.1?
**Answer:** _(open)_
Status: open

### DB-02 Import with an alias
`import` + `db $evelib/db/core;` and `orcl: $evelib/db/oracle;`. topology.html uses
`from $path use (*);`. Is `name: path` an import alias form? Is `$evelib` the same as `$EVE_LIB`?
**Answer:** _(open)_
Status: open

### DB-03 `update … commit` statements
`update record1:` followed by `let field := value;` lines, then `commit;`. Is `update` a block
statement (what closes it)? Are `commit` and `rollback` statements or methods (`db.commit()`)?
**Answer:** _(open)_
Status: open

### DB-04 Compile-time table check
"If the table in the database does not exist, EVE compiler will complain." That needs a database
connection at compile time. Is the check at load time (when the VM loads the script)?
**Answer:** _(open)_
Status: open

## Fixes (applied unless you write "no")

### DB-F1 Wrong content
- `new demoDB =  set db := OracleSession(…);` mixes `new`, `=`, `set` and `:=`.
- Constructor `=> (@self db.Session)` has no `:` and returns another type than the class.
- `let self.location = location;` (three times) → `:=`; the class has no `location` attribute.
- `return` without `;` after the class; `global` + `new buffer` (`new` in a global region →
  `set`).
- `deleded1`, `deleded2`; `print (…)` without `;`.
- "ORM = Object Relational Model" → Mapping.
**Answer:** _(open)_

### DB-F2 Typos
formating, safly, opperations, automaticly, cashing, ocasions, crytical, "A record id identified",
commited, enaugh, retrive, "Data cashing".
**Answer:** _(open)_

### DB-F3 Authoring standard
"Eve has enough power to enable developers handle processes", "It will be a challenge".
**Answer:** _(open)_

## Spec additions once answered

None for 0.1 if DB-01 is "later"; the page stays a design note.
