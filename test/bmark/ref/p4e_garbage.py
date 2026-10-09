# reference for p4e_garbage.eve: short-lived strings and lists in a loop
total = 0
for i in range(1, 200001):
    s = "item %d" % i
    parts = (i, i + 1, i + 2)
    total += len(s) + len(parts)
assert total == 2688895
print(total)
