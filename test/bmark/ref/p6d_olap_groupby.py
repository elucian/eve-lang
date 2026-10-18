# reference for p6d_olap_groupby.eve: the same work in Python, with psycopg2 on the PostgreSQL port of the same evedb
import psycopg2

con = psycopg2.connect(host="127.0.0.1", port=55461, user="eve", dbname="bench6")
con.autocommit = True
cur = con.cursor()
cur.execute("create or replace table big as select i::bigint as id, case when i % 4 = 0 then 'north' when i % 4 = 1 then 'south' when i % 4 = 2 then 'east' else 'west' end as region, i * 1.5 as amount, i % 2 = 1 as paid from range(1000000) t(i)")
rows = 0
for k in range(10):
    cur.execute("select region, sum(amount) as total, count(*) as n from big group by region order by region")
    for region, total, n in cur.fetchall():
        rows += n
print(rows)
con.close()
