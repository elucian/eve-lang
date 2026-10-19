# database

Database connections (D-189). Signature file: the body is native, in comp/evevm/src/dlib.zig (databaseModule, connectionCall).
@spec spec/library/database.md#direct-sql  @feature F-DAT-01  @tests test/level5

## `external function connect(name: String) => (@result: Connection);`

Open a session on a connection declared with `database "name" = "url"`; the session ends with the process.

