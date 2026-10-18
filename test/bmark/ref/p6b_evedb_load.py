# reference for p6b_evedb_load.eve: the same work in Python, with psycopg2 on the PostgreSQL port of the same evedb
import psycopg2

con = psycopg2.connect(host="127.0.0.1", port=55461, user="eve", dbname="bench6")
con.autocommit = True
cur = con.cursor()
cur.execute("create or replace table big as select i::bigint as id, case when i % 4 = 0 then 'north' when i % 4 = 1 then 'south' when i % 4 = 2 then 'east' else 'west' end as region, i * 1.5 as amount, i % 2 = 1 as paid from range(200000) t(i)")
from psycopg2.extras import execute_values

cur.execute("drop table if exists big2")
cur.execute("select id, region, amount, paid from big")
rows = cur.fetchall()
cur.execute("create table big2 (id bigint, region varchar, amount double, paid boolean)")
execute_values(cur, "insert into big2 values %s", rows, page_size=100000)
print(len(rows))
cur.execute("select count(*) from big2")
print(cur.fetchone()[0])
con.close()
