# reference for p1c_collections.eve: the same work in Python
lst = [0]
for i in range(1, 60001):
    lst.append(i)
total = 0
for v in lst:
    total += v
m = {"zero": 0}
for i in range(1, 301):
    m["k%d" % i] = i
found = 0
for i in range(1, 301):
    found += m["k%d" % i]
s = {0}
for i in range(1, 2001):
    s.add(i % 100)
assert len(lst) == 60001 and len(m) == 301 and len(s) == 100
print("%d,%d" % (total, found))
