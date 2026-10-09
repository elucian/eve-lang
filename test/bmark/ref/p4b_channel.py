# reference for p4b_channel.eve: a producer, two workers and a collector joined by bounded queues
import queue
import threading

jobs, results = queue.Queue(100), queue.Queue(100)
DONE = object()
total = [0]


def produce(n):
    for i in range(1, n + 1):
        jobs.put(i)
    for _ in range(2):
        jobs.put(DONE)


def square():
    while True:
        x = jobs.get()
        if x is DONE:
            results.put(DONE)
            return
        results.put(x * x)


def collect():
    closed = 0
    while closed < 2:
        y = results.get()
        if y is DONE:
            closed += 1
        else:
            total[0] += y


ts = [threading.Thread(target=produce, args=(50000,)), threading.Thread(target=square),
      threading.Thread(target=square), threading.Thread(target=collect)]
for t in ts:
    t.start()
for t in ts:
    t.join()
assert total[0] == 41667916675000
print(total[0])
