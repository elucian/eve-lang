# reference for p5a_sql_function.eve: the same work in Python, with sqlite3 and a function made by create_function
import os
import sqlite3

path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "db", "bench_py.db")
os.makedirs(os.path.dirname(path), exist_ok=True)
con = sqlite3.connect(path)
con.create_function("weight", 1, lambda x: x * 3 + 1, deterministic=True)
con.execute("drop table if exists t")
con.execute("create table t (n integer primary key)")
con.execute("with recursive c(n) as (select 1 union all select n + 1 from c where n < 20000) insert into t select n from c")
con.commit()
total = 0
for k in range(3):
    count, s = con.execute("select count(*), sum(weight(n)) from t").fetchone()
    total += s
assert total == 1800150000
print(total)
con.close()
