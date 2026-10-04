# Issues: topology.html

Page: `tutorial/topology.html` (597 lines). Reviewed 2026-09-28. How to answer: [README](README.md).

## Questions

### TOP-08 Built-in system variables for 0.1
The pages name `$EVE_DIR`, `$EVE_LIB`, `$MY_DIR`, `$MY_LIB`, `$MY_LOG`, `$OS_PWD`, `$error`,
`$stack`, `$trace`, `$object`, `$result`, and user ones like `$user_path`. "System constants are
capitalized". Which system variables must the VM provide in 0.1, with which types? Are OS
environment variables visible as `$NAME`?
**Answer:** Yes, environment variables are visible as $NAME. 
Status: partly done → D-031, D-052: environment variables are `$NAME` (applied); the 0.1 variable list and their types are open

## Improvements (applied only if you write "yes")

None open (TOP-I2 retired 2026-10-03).

## Spec additions once answered

- `spec/semantics/topology.md`: projects, scripts, modules, imports, execution (D-031, D-043).
- `spec/syntax/regions.md`: one scope per script, no regions (D-041); declarations and constants (D-031).
- `spec/semantics/scopes.md`: system variables (TOP-08), scopes of driver, aspect and module (D-043).
- `manual/usage.md`: VM modes and options (D-031).
