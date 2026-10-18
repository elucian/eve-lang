# reference for p6a_evedb_store.eve: the same work in Python, with psycopg2 on the PostgreSQL port of the same evedb
import psycopg2

con = psycopg2.connect(host="127.0.0.1", port=55461, user="eve", dbname="bench6")
con.autocommit = True
cur = con.cursor()
cur.execute("create or replace table big as select i::bigint as id, case when i % 4 = 0 then 'north' when i % 4 = 1 then 'south' when i % 4 = 2 then 'east' else 'west' end as region, i * 1.5 as amount, i % 2 = 1 as paid from range(1000000) t(i)")
cur.execute("select id, region, amount, paid from big")
rows = cur.fetchall()
cols = [list(c) for c in zip(*rows)]  # the same four columns as the Memory table
print(len(cols[0]))
print(sum(cols[0]))
con.close()
