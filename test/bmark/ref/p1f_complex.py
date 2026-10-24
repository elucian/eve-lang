# reference for p1f_complex.eve: the same work with Python's complex numbers
total = 0
for yi in range(40):
    for xi in range(70):
        c = complex(-2.0 + xi * 0.04, -1.0 + yi * 0.05)
        z = 0j
        n = 0
        while n < 100 and abs(z) <= 2:
            z = z * z + c
            n += 1
        total += n
assert total == 91897
print(total)
