# reference for p3a_modules.eve: the same work in Python (a module is a namespace)
class mathx:
    STEP = 2

    @staticmethod
    def square(x):
        return x * x

    @staticmethod
    def clamp(x, lo, hi):
        return lo if x < lo else hi if x > hi else x


total = 0
for i in range(1, 50001):
    total += mathx.square(i % 10)
assert total == 1425000
clipped = 0
for i in range(1, 50001):
    clipped += mathx.clamp(i, 100, 200)
assert clipped == 9985050
steps = 0
for i in range(1, 50001):
    steps += mathx.STEP
assert steps == 100000
print("%d,%d,%d" % (total, clipped, steps))
