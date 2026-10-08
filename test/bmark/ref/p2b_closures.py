# reference for p2b_closures.eve: the same work in Python
def make_counter(first):
    current = [first]

    def nxt():
        current[0] += 1
        return current[0]
    return nxt


c = make_counter(0)
last = 0
for i in range(1, 50001):
    last = c()
assert last == 50000
add = lambda x, y: x + y
total = 0
for i in range(1, 50001):
    total = add(total, i)
assert total == 1250025000
made = 0
for i in range(1, 2001):
    d = make_counter(i)
    made += d()
assert made == 2003000
print("%d,%d,%d" % (last, total, made))
