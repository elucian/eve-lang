# Library math

Status: **draft**, levels 1 to 3. Library step L2a: modules `basic`, `explog`, `trig`, `numtheory` and `math` are built, tests a110 and a111. Written in the VM, in Zig, behind `external` signatures in `lib/math/`. Feature: F-LIB-03.

The mathematics of plain numbers. Every function is a function of a module, `math.sqrt(x)`, never a global name. The functions are grouped in modules of the folder `lib/math/`, imported by path: `from lib/math/trig use (sin, cos);` or `use lib/math/basic;`. No function changes its argument. Rules of every library: [README.md](README.md).

A function works on `Integer`, `Real` and `Decimal` unless its row says otherwise. The functions of sections `explog` and `trig` give a `Real`. No function gives `NaN` or an infinity: a domain error is `$err_argument` (17) with a message, a result out of range is `$err_overflow`, a division by zero is `$err_divide`.

## Module basic

| Function | Result | Meaning |
|---|---|---|
| `abs(x)` | type of `x` | the absolute value; `abs` of the smallest `Integer` is `$err_overflow` |
| `sign(x)` | `Integer` | `-1`, `0` or `1` |
| `min(a, b)`, `max(a, b)` | the chosen argument, unchanged | the smaller or the larger; for a list use `xs.min()` |
| `clamp(x, low, high)` | the chosen argument, unchanged | `x` limited to `low .. high`; `low > high` is `$err_argument` |
| `pow(x, n)` | `Integer` for whole `x` and `n >= 0`; `Decimal` for `Decimal`; `Real` otherwise, also for a negative `n` | `x` to the power `n`; `0` to a negative power is `$err_divide`; a negative base with a non-whole exponent is `$err_argument` |
| `sqrt(x)` | `Real` | the square root; `x < 0` is `$err_argument` |
| `cbrt(x)` | `Real` | the cube root; a negative `x` is allowed |
| `hypot(x, y)` | `Real` | `sqrt(x*x + y*y)` without an overflow in the middle |
| `div(a, b)` | `Integer` | integer division rounded toward minus infinity; `b = 0` is `$err_divide` |
| `mod(a, b)` | `Integer` | the remainder with the sign of `b`; `a == div(a, b) * b + mod(a, b)` |
| `divmod(a, b)` | `(Integer, Integer)` | `(div(a, b), mod(a, b))` |
| `gcd(a, b)`, `lcm(a, b)` | `Integer` | greatest common divisor, least common multiple, never negative; `lcm` that does not fit is `$err_overflow` |

## Module explog

| Function | Result | Meaning |
|---|---|---|
| `exp(x)` | `Real` | e to the power `x`; a result out of range is `$err_overflow` |
| `log(x)` | `Real` | the natural logarithm; `x <= 0` is `$err_argument` |
| `log2(x)`, `log10(x)` | `Real` | logarithms of base 2 and 10; `x <= 0` is `$err_argument` |
| `log(x, base)` | `Real` | the logarithm of `x` in `base` (`base > 0`, `base != 1`) |

## Module trig

Angles are in radians; the functions `radians(d)` and `degrees(r)` convert.

| Function | Result | Meaning |
|---|---|---|
| `sin(x)`, `cos(x)`, `tan(x)` | `Real` | the usual functions |
| `asin(x)`, `acos(x)` | `Real` | `x` outside `-1 .. 1` is `$err_argument` |
| `atan(x)`, `atan2(y, x)` | `Real` | `atan2(0, 0)` is `0.0` |
| `sinh(x)`, `cosh(x)`, `tanh(x)` | `Real` | hyperbolic functions |
| `radians(d)`, `degrees(r)` | `Real` | degrees to radians and back |

## Module constants

`pi` (3.141592653589793), `e` (2.718281828459045) and `tau` (2 * `pi`) are `Real` constants declared with `set` and exported.

## Module numtheory

| Function | Result | Meaning |
|---|---|---|
| `is_prime(n)` | `Logic` | `False` for `n < 2`; deterministic for every `Integer` |
| `factors(n)` | `List` of `Integer` | the prime factors in ascending order with repeats (`12` gives `(2,2,3)`); `n < 2` is `$err_argument` |
| `mod_pow(base, exp, m)` | `Integer` | `base` to `exp` modulo `m` without overflow; `exp < 0` or `m <= 0` is `$err_argument` |

```eve
use lib/math/basic;
use lib/math/trig;
print basic.sqrt(16);          ** 4
print basic.divmod(-7, 2);     ** (-4,1)
print trig.degrees(trig.atan2(1, 1));   ** 45
```

## Module linear

A vector is a `List` of numbers; a matrix is a `List` of rows, each row a `List` of numbers, all rows of the same length (at least one row and one column). An element may be an `Integer`, a `Real` or a `Decimal`; the results are `Real` numbers and lists of `Real`. No function changes its argument. A wrong shape, a list that is not a list of numbers, or a singular matrix is `$err_argument` (17); a result out of range is `$err_overflow`.

| Function | Result | Meaning |
|---|---|---|
| `dot(a, b)` | `Real` | the dot product; the vectors have the same length |
| `cross(a, b)` | `List` | the cross product of two vectors of 3 elements |
| `norm(v)` | `Real` | the Euclidean length |
| `scale(x, k)` | `List` | a vector or a matrix with every element multiplied by `k` |
| `add(a, b)`, `subtract(a, b)` | `List` | the sum or the difference, element by element, of two vectors or two matrices of the same shape |
| `transpose(m)` | `List` | rows become columns |
| `matmul(a, b)` | `List` | the matrix product; the columns of `a` equal the rows of `b` |
| `matvec(m, v)` | `List` | the matrix times a vector |
| `identity(n)` | `List` | the identity matrix of size `n` (1 to 4096) |
| `trace(m)` | `Real` | the sum of the diagonal of a square matrix |
| `det(m)` | `Real` | the determinant of a square matrix |
| `inverse(m)` | `List` | the inverse of a square matrix; a singular matrix is an error |
| `solve(a, b)` | `List` | the vector `x` with `a * x = b` (Gaussian elimination with partial pivoting) |

```eve
use lib/math/linear;
print linear.dot((1, 2, 3), (4, 5, 6));              ** 32
print linear.det(((1, 2), (3, 4)));                  ** -2
print linear.solve(((2, 1), (1, -1)), (5, 1));       ** (2,1)
```

## Module random

One generator for the whole process. The functions that give a value end with `!`: their answer differs at each call; `seed` is a procedure and has no `!` (a procedure can't end with `!`). The generator is xoshiro256** seeded through SplitMix64, so **a seed gives the same numbers on every machine and every release**. Without a call of `seed` the generator is seeded from the operating system at the first use: the numbers cannot be predicted, only their type and range. A test of an unseeded generator writes the type of the expected value in braces, `{Integer}`, `{Real}`, `{Logic}`, `{String}` or `{Any}`.

| Function | Result | Meaning |
|---|---|---|
| `seed(n)` | none | start the sequence of the whole number `n` |
| `next!()` | `Real` | from 0 up to, not including, 1 |
| `integer!(low, high)` | `Integer` | from `low` to `high`, both included; `low > high` is `$err_argument` |
| `real!(low, high)` | `Real` | from `low` up to, not including, `high` |
| `normal!(mean, deviation)` | `Real` | the normal distribution; a negative deviation is `$err_argument` |
| `choice!(xs)` | element | one element of a list; an empty list is `$err_argument` |
| `shuffle!(xs)` | `List` | a new list with the elements in random order (Fisher-Yates) |
| `sample!(xs, n)` | `List` | `n` different elements, without replacement; `n` from 0 to the length |

```eve
use lib/math/random;
random.seed(42);
new a = random.integer!(1, 6) :Integer;   ** the same number at each run
print random.next!();                      ** a Real, between 0 and 1
```

## Module rational

The type `Rational` and its literal `3\4` belong to the language ([types.md](../semantics/types.md#rational)); this module builds fractions and takes them apart. An argument may be a `Rational` or an `Integer`. `abs`, `sign`, `min`, `max`, `clamp` and `pow` of module `basic` accept a `Rational` and give an exact result; the functions of `explog`, `trig` and `sqrt` convert it to a `Real`.

| Function | Result | Meaning |
|---|---|---|
| `of(n, d)` | `Rational` | `n` over `d` in lowest terms; `d = 0` is `$err_divide` |
| `numerator(r)`, `denominator(r)` | `Integer` | the parts of the fraction in lowest terms (the sign is on the numerator, the denominator is positive) |
| `reciprocal(r)` | `Rational` | one over `r`; zero is `$err_divide` |
| `truncate(r)` | `Integer` | the whole part, toward zero (`floor`, `ceiling` and `round` are the global functions, exact for a `Rational`) |
| `is_whole(r)` | `Logic` | is the denominator 1 |
| `to_real(r)` | `Real` | the nearest `Real` |
| `from_real(x, max_den)` | `Rational` | the simplest fraction nearest to `x` whose denominator is at most `max_den` (continued fractions); `max_den` below 1 or a `x` that is not finite is `$err_argument` |
| `parse(text)` | `Rational` | reads `"3\\4"`, `"3/4"` or `"-7"`; anything else is `$err_parse` |
| `mediant(a, b)` | `Rational` | `(a.n + b.n) / (a.d + b.d)`, the Farey neighbour between two fractions |
| `continued(r)` | `List` | the terms of the continued fraction: `355\113` gives `(3,7,16)` |

```eve
from lib use (math);
print 1\3 + 1\6;                  ** 1\2
print math.from_real(0.75, 100);  ** 3\4
print math.continued(355\113);    ** (3,7,16)
```

## Module complex

The type `Complex` and its imaginary literal `i99` belong to the language ([types.md](../semantics/types.md#complex)); this module takes complex numbers apart and computes with them. An argument may be a `Complex` or any real number (`Integer`, `Real`, `Rational`); a `Decimal` is `$err_argument`. A result that is not finite is `$err_overflow`. Through `from lib use (math)` the names `real_part`, `imag_part`, `modulus`, `argument`, `conjugate`, `from_polar` and `is_real` are `math.name`; `of`, `exp`, `log`, `sqrt` and `pow` have the names of other modules and are reached as `math.complex.sqrt(z)`. `basic.abs(z)` is the modulus.

| Function | Result | Meaning |
|---|---|---|
| `of(re, im)` | `Complex` | the number from two real numbers |
| `real_part(z)`, `imag_part(z)` | `Real` | the parts |
| `modulus(z)` | `Real` | `sqrt(re*re + im*im)` without an overflow in the middle |
| `argument(z)` | `Real` | the angle in radians in (-pi, pi]; 0 for zero |
| `conjugate(z)` | `Complex` | `re - i im` |
| `from_polar(modulus, angle)` | `Complex` | the number with that modulus and angle; a negative modulus is `$err_argument` |
| `exp(z)` | `Complex` | e to the power `z` |
| `log(z)` | `Complex` | the principal logarithm; zero is `$err_argument` |
| `sqrt(z)` | `Complex` | the principal square root, real part not negative: `sqrt(-4)` is `(0 + i2)` |
| `pow(a, b)` | `Complex` | `a` to the power `b`; zero to a power that is not a positive real is `$err_divide`, `0^0` is 1 |
| `is_real(z)` | `Logic` | is the imaginary part zero |

```eve
from lib use (math);
new z := (3 + i4);
print math.modulus(z);                  ** 5
print math.complex.sqrt(-4);            ** (0 + i2)
print math.complex.exp(math.pi * i1);   ** (-1 + i0.00000000000000012246467991473532): Euler, up to rounding
```

## Later sub-steps (not in this page)

L2 is complete: `basic`, `explog`, `trig`, `constants`, `numtheory`, `linear`, `random`, `rational` and `complex`. The next library is L3, statistics.

## Rules of import and conversion

- **Import form.** The name before the dot is what was imported: `use lib/math;` gives `math.sqrt(x)` (every module of the folder), `use lib/math/basic;` gives `basic.sqrt(x)`, `from lib/math/trig use (sin, cos);` gives `sin(x)`. The file `lib/math.eve` re-exports `basic`, `explog`, `trig`, `constants` and `numtheory`.
- **`Decimal` arguments.** A function that gives a `Real` accepts a `Decimal` and converts it; when the target variable is a `Decimal`, the assignment converts the `Real` back.
- **`pow` with a negative exponent** gives a `Real`: `pow(2, -1)` is `0.5`.
