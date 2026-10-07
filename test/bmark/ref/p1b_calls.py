# reference for p1b_calls.eve: the same work in Python
def fib(n):
    return n if n < 2 else fib(n - 1) + fib(n - 2)


def twice(a):
    return a * 2


total = 0
for i in range(1, 50001):
    total += twice(i)
assert fib(20) == 6765 and total == 2500050000
print("%d,%d" % (fib(20), total))
