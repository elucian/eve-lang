# reference for p4d_tasks.eve: 50 rounds of 20 asyncio tasks gathered at the end of each round
import asyncio


async def square(n, outs, i):
    outs[i] = n * n


async def main():
    total = 0
    outs = [0] * 20
    for _ in range(50):
        await asyncio.gather(*(square(i + 1, outs, i) for i in range(20)))
        total += sum(outs)
    return total


total = asyncio.run(main())
assert total == 143500
print(total)
