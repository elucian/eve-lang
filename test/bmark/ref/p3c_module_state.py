# reference for p3c_module_state.eve: the same work in Python
class mathx:
    total = 0

    @staticmethod
    def tick():
        mathx.total += 2

    @staticmethod
    def ticks():
        return mathx.total


for i in range(50000):
    mathx.tick()
seen = 0
for i in range(50000):
    seen = mathx.ticks()
assert seen == 100000
print(seen)
