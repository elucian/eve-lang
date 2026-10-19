# evedb: the Eve test database

`evedb` is a small database server around **DuckDB**, tuned for Eve. It answers as a **PostgreSQL server** (port 5432), so any PostgreSQL client and the Eve driver `postgres://` can use it; DuckDB runs the SQL. A second port, the **control port** (8044), speaks the native protocol of Eve: column batches for fast bulk work (the Eve driver `evedb://`), and, for tests, server counters, fault injection and a log of every statement.

SQLite stays the core database of Eve and is built into `eve.exe`; `evedb` is a separate program that `eve` never needs to run a script. Its first use is a remote database for tests that can fail on cue; it is also an analytic engine for ETL work (columnar storage, fast group-by).

## The files

| File | Role |
|---|---|
| `bin/evedb.exe` | the server and its commands |
| `bin/duckdb.dll` | DuckDB 1.5.6, loaded by `evedb.exe` |
| `evedb.cfg` | the configuration (any name; given on the command line) |
| `*.duckdb` | one database per file |

## Starting it

```
evedb serve --config evedb.cfg      in this window; Ctrl+C or `evedb stop` ends it
eve db serve evedb.cfg              the same, started by eve
eve -s -db --serve evedb.cfg        as a service (Windows) or daemon (Linux), silent, with a log file
```

## The configuration

```
# evedb.cfg
port = 5432                          # the PostgreSQL port (0: the system chooses)
control_port = 8044                  # the native port; "off" closes it
host = "127.0.0.1"                   # the address to listen on
data = "data"                        # the folder of the databases that are not listed
user = "eve"                         # the user of the PostgreSQL port
password = "secret"
auth = "md5"                         # trust, password or md5
test = false                         # true: faults, the statement log, 127.0.0.1 only, databases made on demand
token = "..."                        # the secret of the control port and of `evedb stop`
lease = 30                           # seconds a session lives without a request
database "shop" = "data/shop.duckdb" # a name a client may ask for, and its file
```

When `database` lines are given, a client may ask only for those names. A server that listens on another address than `127.0.0.1` needs `auth = md5` or `password`. Outside test mode the control port opens only with the token.

## Commands

| Command | Meaning |
|---|---|
| `evedb serve [--config f] [--port n] [--control-port n] [--test] ...` | run the server (options win over the file) |
| `evedb create <name>` | a new database file in the data folder |
| `evedb sql <name> "<statement>"` | run one statement on the file directly and print the result |
| `evedb sql --connect <host:port> <name> "<statement>"` | the same through a running server |
| `evedb describe <name> <table>` | the columns of a table, in Eve types |
| `evedb snapshot <name> <file>`, `evedb reset <name> <file>` | copy a database out and put it back (test fixtures) |
| `evedb status [--connect host:port]` | the counters of a server |
| `evedb stop [--connect host:port] [--token t]` | end a server |

## From Eve

The address of a database is a line of `eve.cfg` in the project; the program asks for it by name:

```
# eve.cfg
database "shop" = "postgres://eve:secret@127.0.0.1:5432/shop"   # any PostgreSQL server, evedb too
database "wh" = "evedb://127.0.0.1:8044/wh"                      # the native driver: column batches
```

```
new shop := database.connect("shop");
for i in shop.query!(:Item)("select * from items order by id") do
  print "{i.id} {i.name}";
done;
```

With `evedb://`, a `Memory` table moves whole columns at a time (`Memory.store`, `Memory.load`), which is much faster for bulk loads than records.

Logic stays in Eve jobs, not in the database: evedb runs SQL, bulk loads and DuckDB macros, but no Eve code, no stored procedures and no triggers.

## Security and limits

The token is a shared secret; there is no TLS (put a reverse proxy in front). One user per server; SCRAM on the server, several users, import and export of CSV, JSON and Parquet, and TLS come in later versions. Version of this build: 0.3.
