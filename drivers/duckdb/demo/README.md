# Demo: a remote PostgreSQL connection from Eve to evedb on port 5432

evedb (DuckDB inside) answers as a PostgreSQL server on port 5432; the Eve machine of this folder connects to it with the Eve driver for PostgreSQL (`postgres://` in `eve.cfg`); a web page of the machine sends Eve scripts that read and write through that connection. Design: `../README.md` sections 5A, 5B and 9.

The page stands in for the database tab of **eveux**, which is designed (`design/components/eveux/README.md`) and not built: eveux will be a project written in Eve served by the machine, and this page is the smallest such page, one HTML file that calls the machine's `vm.run`.

## Run it

From this folder, with `bin/` of the repository built (`zig build -p .` at the root, `zig build -p ../..` in `drivers/duckdb/`):

```
eve -s -db --serve evedb.cfg      # evedb as a service, silent: PostgreSQL on 5432, control port 8044
eve -ux                           # starts the machine of eve.cfg (ports 4142 and 8142) and opens http://localhost:8142/
```

On the page: **Create the table and two rows**, then **List the items**, **Insert an item**, **Ask the server who it is**. Each button runs a small Eve script in the machine; the script calls `database.connect("shop")`, the driver logs in to evedb with md5 (user `eve`, password `demo`) and runs the SQL. The output of the script is shown under the buttons.

Any PostgreSQL client reaches the same database: `psql -h 127.0.0.1 -p 5432 -U eve shop` (password `demo`), or Python with psycopg2.

## Stop it

```
eve --serve stop                                         # the machine
evedb stop --connect 127.0.0.1:8044 --token demo-stop    # evedb (the token of evedb.cfg)
```

## Files

| File | What |
|---|---|
| `evedb.cfg` | evedb: port 5432, md5 login, the database `shop` in `data/shop.duckdb`, the control port 8044 with a token |
| `eve.cfg` | the machine: ports 4142 and 8142, the web folder, the connection `shop` = `postgres://eve:demo@127.0.0.1:5432/shop` |
| `web/index.html` | the page: four buttons, each sends an Eve script to `POST /rpc` (`vm.run`) |
