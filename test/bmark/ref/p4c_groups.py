# reference for p4c_groups.eve: 250 groups of 4 threads, each writes one output
import threading

total = 0
for r in range(1, 251):
    outs = [0] * 4

    def add_one(a, b):
        outs[b - 1] = a + b

    ts = [threading.Thread(target=add_one, args=(r, k)) for k in range(1, 5)]
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    total += sum(outs)
assert total == 128000
print(total)
