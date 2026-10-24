# reference for p1e_rational.eve: the same work with fractions.Fraction
from fractions import Fraction
total = Fraction(0)
for k in range(1, 200001):
    total = total + Fraction(1) / (k * (k + 1))
assert total == Fraction(200000, 200001)
last = Fraction(1)
for r in range(1, 20001):
    x = Fraction(1)
    for step in range(5):
        x = (x + Fraction(2) / x) / 2
    last = x
assert last == Fraction(886731088897, 627013566048)
below = 0
probe = Fraction(1, 3)
for k in range(1, 100001):
    if probe < Fraction(1) * k / (k + 1):
        below += 1
assert below == 100000
print("%d" "\\" "%d,%d" "\\" "%d,%d" % (total.numerator, total.denominator, last.numerator, last.denominator, below))
