# Engineering

Status: **draft**, level 3. Library step L7. Written in Eve (`lib/eng/`), over `math`. Feature: F-LIB-03.

Constants of physics, units of measure, numerical methods, signals and plane geometry. Numbers are `Real`; the lists that stand for points or spectra are lists of numbers. A wrong argument is `$err_argument` (17).

## Rules of import

`from lib use (eng);` gives the modules `eng.constants`, `eng.units`, `eng.numeric`, `eng.signal` and `eng.geometry`, and their functions are also members of `eng`; a module can be imported alone, `from lib/eng use (units);`.

## Module constants

The values of CODATA 2018 in SI units, as `Real` constants. The speed of light, the Planck constant, the elementary charge, the Boltzmann constant and the Avogadro constant are exact.

| Constant | Meaning | Value |
|---|---|---|
| `c` | speed of light in vacuum, m/s | 299792458 |
| `h`, `hbar` | Planck constant and its reduced form, J s | 6.62607015e-34, 1.054571817e-34 |
| `e_charge` | elementary charge, C | 1.602176634e-19 |
| `k_b` | Boltzmann constant, J/K | 1.380649e-23 |
| `n_a` | Avogadro constant, 1/mol | 6.02214076e23 |
| `r_gas` | molar gas constant, J/(mol K) | 8.314462618 |
| `g_gravity` | gravitational constant, m3/(kg s2) | 6.67430e-11 |
| `g_standard` | standard acceleration of gravity, m/s2 | 9.80665 |
| `eps0`, `mu0` | vacuum permittivity (F/m) and permeability (N/A2) | 8.8541878128e-12, 1.25663706212e-6 |
| `sigma` | Stefan-Boltzmann constant, W/(m2 K4) | 5.670374419e-8 |
| `m_e`, `m_p`, `m_n`, `u_mass` | masses of the electron, proton and neutron, and the atomic mass constant, kg | 9.1093837015e-31, 1.67262192369e-27, 1.67492749804e-27, 1.66053906660e-27 |
| `atm_pressure` | standard atmosphere, Pa | 101325 |
| `zero_celsius` | zero degrees Celsius, K | 273.15 |

## Module units

A `Quantity` has `value` (a `Real`) and `unit` (a `String`). Units of the same dimension convert into each other; a conversion between two dimensions, and a unit the library does not know, is `$err_argument`.

| Dimension | Units |
|---|---|
| `length` | `m` `km` `cm` `mm` `um` `nm` `in` `ft` `yd` `mi` `nmi` |
| `mass` | `kg` `g` `mg` `ug` `t` `lb` `oz` |
| `time` | `s` `ms` `us` `ns` `min` `h` `d` `wk` |
| `temperature` | `K` `C` `F` |
| `pressure` | `Pa` `kPa` `MPa` `bar` `mbar` `atm` `psi` `mmHg` `Torr` |
| `energy` | `J` `kJ` `MJ` `cal` `kcal` `Wh` `kWh` `eV` `BTU` |
| `power` | `W` `kW` `MW` `hp` |
| `area` | `m2` `cm2` `km2` `ha` `ft2` `ac` |
| `volume` | `m3` `L` `mL` `cm3` `gal` `qt` `pt` `floz` `ft3` (US measures) |
| `speed` | `m/s` `km/h` `mph` `kn` |
| `angle` | `rad` `deg` `grad` `turn` |
| `frequency` | `Hz` `kHz` `MHz` `GHz` |
| `data` | `bit` `B` `kB` `MB` `GB` `TB` (powers of 1000) and `KiB` `MiB` `GiB` `TiB` (powers of 1024) |

| Function | Result | Meaning |
|---|---|---|
| `convert(value, from, to)` | `Real` | a number written in another unit: `convert(100, "C", "F")` is 212 |
| `quantity(value, unit)` | `Quantity` | |
| `to(q, unit)` | `Quantity` | the quantity in another unit of its dimension |
| `add(a, b)`, `subtract(a, b)` | `Quantity` | the sum and the difference, in the unit of the first; two temperatures cannot be added (they are points, not differences), and the difference of two temperatures is a difference in degrees |
| `scale(q, k)` | `Quantity` | the quantity times a number |
| `compare(a, b)` | `Integer` | -1, 0 or 1, compared in the unit of the first |
| `dimension(unit)` | `String` | the dimension of a unit |
| `names(dimension)` | list | the units of a dimension, sorted |
| `is_unit(text)` | `Logic` | is the text a unit that the library knows |

## Module numeric

The function `f` of a method is a function of one `Real` (of two for a differential equation), usually a lambda: `(x) => (x ^ 2 - 2)`.

| Function | Result | Meaning |
|---|---|---|
| `bisect(f, a, b)`, `bisect(f, a, b, tolerance)` | `Real` | a root between `a` and `b`; `f` has different signs at the two ends; the tolerance is 1e-12 by default |
| `newton(f, df, x0)`, `newton(f, df, x0, tolerance)` | `Real` | a root by Newton's method; a derivative of 0 and no convergence in 100 steps are `$err_argument` |
| `secant(f, x0, x1)`, `secant(f, x0, x1, tolerance)` | `Real` | a root by the secant method, without a derivative |
| `trapezoid(f, a, b, n)`, `simpson(f, a, b, n)` | `Real` | the integral of `f` from `a` to `b` with `n` intervals (`n` is even for Simpson) |
| `euler(f, t0, y0, t1, n)`, `rk4(f, t0, y0, t1, n)` | `Real` | the value at `t1` of the solution of `y' = f(t, y)` with `y(t0) = y0`, with `n` steps, by Euler's method and by the Runge-Kutta method of the fourth order |
| `interpolate(xs, ys, x)` | `Real` | the line through the nearest two points of a table with rising `xs`; `x` outside the table is `$err_argument` |
| `lagrange(xs, ys, x)` | `Real` | the polynomial of the lowest degree through all the points |

## Module signal

| Function | Result | Meaning |
|---|---|---|
| `convolve(a, b)` | list | the convolution, of length `a + b - 1` |
| `dft(xs)` | list | the discrete Fourier transform as pairs `[re, im]`; it takes N squared steps |
| `idft(spectrum)` | list | the inverse transform, the real parts |
| `magnitudes(spectrum)` | list | `sqrt(re^2 + im^2)` of each pair |
| `frequencies(n, rate)` | list | the frequencies in hertz of a transform of `n` numbers sampled `rate` times a second |

## Module geometry

A point is a pair `[x, y]`, a polygon a list of points in order (3 or more), whose sides do not cross.

| Function | Result | Meaning |
|---|---|---|
| `distance(p, q)`, `midpoint(p, q)`, `angle(p, q)` | | the distance, the middle, and the direction from `p` to `q` in radians from -pi to pi |
| `polygon_area(polygon)`, `perimeter(polygon)`, `centroid(polygon)` | | the area (by the shoelace formula), the length of the sides, and the centre of mass of the area |
| `contains(polygon, p)` | `Logic` | is the point inside the polygon; a point on a side is inside |
| `triangle_area(a, b, c)` | `Real` | the area from the three sides (Heron) |
| `circle_area(r)`, `circumference(r)` | `Real` | |
| `hull(points)` | list | the corners of the convex hull, counter-clockwise from the lowest left point |
| `segments_cross(a, b, c, d)` | `Logic` | do the segments a-b and c-d cross or touch |
