# reference for p2c_procedures.eve: the same work in Python
counter = 0


def swap(a, b):
    return b, a


def scale(x, factor=2, offset=1):
    return x * factor + offset


def count_all(*items):
    global counter
    counter += len(items)


p, q = 1, 2
for i in range(30000):
    p, q = swap(p, q)
assert (p, q) == (1, 2)
total = 0
for i in range(1, 30001):
    total += scale(i, offset=0)
assert total == 900030000
for i in range(1, 30001):
    count_all(i, i, i)
assert counter == 90000
print("%d,%d,%d,%d" % (p, q, total, counter))
