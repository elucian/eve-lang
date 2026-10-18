# reference for p6c_pg_records.eve: the same work in Python, with psycopg2 on the PostgreSQL port of the same evedb
import psycopg2

con = psycopg2.connect(host="127.0.0.1", port=55461, user="eve", dbname="bench6")
con.autocommit = True
cur = con.cursor()
cur.execute("create or replace table big as select i::bigint as id, case when i % 4 = 0 then 'north' when i % 4 = 1 then 'south' when i % 4 = 2 then 'east' else 'west' end as region, i * 1.5 as amount, i % 2 = 1 as paid from range(100000) t(i)")
cur.execute("select id, region, amount, paid from big")
total = n = 0
for id_, region, amount, paid in cur.fetchall():
    r = {"id": id_, "region": region, "amount": amount, "paid": paid}  # one object per row, as a record
    total += r["id"]
    n += 1
print(n)
print(total)
con.close()
