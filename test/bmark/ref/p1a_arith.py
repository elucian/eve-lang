# reference for p1a_arith.eve: the same work in Python
s = 0
for i in range(1, 300001):
    s += i % 7 * 3
x = 0.0
n = 0
while n < 200000:
    x += 0.5
    n += 1
assert s == 2699994 and x == 100000.0
print("%d,%d" % (s, x))
