# reference for p4a_parallel_sum.eve: four threads sum the four parts of a list, 5 rounds
import threading

rows = list(range(1, 200001))
total = 0
for _ in range(5):
    k = len(rows) // 4
    parts = [rows[i * k:(i + 1) * k] if i < 3 else rows[3 * k:] for i in range(4)]
    sums = [0] * 4

    def sum_part(i, part):
        s = 0
        for x in part:
            s += x
        sums[i] = s

    ts = [threading.Thread(target=sum_part, args=(i, list(parts[i]))) for i in range(4)]
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    total += sum(sums)
assert total == 100000500000
print(total)
