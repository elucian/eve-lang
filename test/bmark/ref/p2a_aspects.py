# reference for p2a_aspects.eve: the same work in Python (an aspect is a function that is called)
def adder(a, b):
    return a + b


acc = 0
for i in range(1, 5001):
    acc = adder(acc, i)
assert acc == 12502500
print(acc)
