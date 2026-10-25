# Statistics

Status: **draft**, level 3. Library step L3. Written in Eve (`lib/stats/`), over `math.basic`, `math.linear` and `math.random`. Feature: F-LIB-03.

The functions take lists of numbers (`Integer`, `Real` or `Decimal`) and give a `Real` unless the row says otherwise. A list that holds anything else, a list that is too short for the function, a size that makes no sense and a probability outside 0 to 1 are `$err_argument` (17). The names follow Excel where it has one (`VAR.S`, `STDEV.P`, `SKEW`, `KURT`, `QUANTILE.INC`).

## Rules of import

`from lib use (stats);` gives `stats.mean`, `stats.variance`, `stats.pearson` and the other functions of `describe` and `correlate`, and the modules `stats.regress`, `stats.distrib`, `stats.sample`, `stats.histogram` and `stats.moving`. A module of the folder can also be imported alone, `from lib/stats use (describe);`.

## Module describe

| Function | Result | Meaning |
|---|---|---|
| `count(xs)` | `Integer` | the number of items; the only function that accepts an empty list |
| `mean(xs)` | `Real` | the arithmetic mean |
| `median(xs)` | `Real` | the middle value; the mean of the two middle values when the count is even |
| `modes(xs)` | list | the most frequent values, in ascending order |
| `mode(xs)` | value | the smallest of the most frequent values |
| `variance(xs)`, `stddev(xs)` | `Real` | the sample variance and deviation (divided by n - 1, `VAR.S`); at least two numbers |
| `variance_p(xs)`, `stddev_p(xs)` | `Real` | the population forms (divided by n, `VAR.P`) |
| `quantile(xs, p)` | `Real` | the quantile `p` from 0 to 1 with linear interpolation (`QUANTILE.INC`); `quantile(xs, 0.5)` is the median |
| `range(xs)` | `Real` | the largest minus the smallest |
| `skew(xs)` | `Real` | the sample skewness (`SKEW`); at least three numbers that are not all equal |
| `kurtosis(xs)` | `Real` | the sample excess kurtosis (`KURT`); at least four numbers that are not all equal |
| `describe(xs)` | `DataMap` | the keys `count`, `mean`, `median`, `stddev`, `min`, `max`, `range`, `skew` and `kurtosis`; `stddev` is null for one number, `skew` and `kurtosis` are null when the list is too short or its numbers are all equal |

```eve
new xs := (2, 4, 4, 4, 5, 5, 7, 9);
print stats.mean(xs);          ** 5
print stats.stddev_p(xs);      ** 2
print stats.modes(xs);         ** (4)
```

## Module correlate

| Function | Result | Meaning |
|---|---|---|
| `covariance(xs, ys)` | `Real` | the sample covariance (divided by n - 1) |
| `pearson(xs, ys)` | `Real` | Pearson's coefficient, from -1 to 1; a list whose numbers are all equal is `$err_argument` |
| `spearman(xs, ys)` | `Real` | Spearman's coefficient: Pearson's coefficient of the ranks |
| `ranks(xs)` | list | the ranks from 1; equal numbers share the average of their ranks |

Both lists must have the same length and at least two items.

## Module regress

| Function | Result | Meaning |
|---|---|---|
| `linear(xs, ys)` | `DataMap` | the least squares line `y = intercept + slope * x`: the keys `slope`, `intercept` and `r2`; the x values must not all be equal |
| `poly(xs, ys, degree)` | list | the coefficients of the polynomial of that degree, lowest power first (`c0 + c1 x + c2 x^2`), solved with `math.linear.solve`; more points than the degree are needed |

## Module distrib

Each distribution has a density (`_pdf`; for a discrete distribution the probability of one value), a cumulative probability (`_cdf`) and an inverse (`_inv`).

| Function | Meaning |
|---|---|
| `erf(x)` | the error function |
| `norm_pdf(x, mean, sd)`, `norm_cdf(x, mean, sd)` | the normal distribution; `sd` is more than 0 |
| `norm_inv(p, mean, sd)` | the `x` with `norm_cdf(x, mean, sd) = p`; `p` is more than 0 and less than 1 |
| `binom_pdf(k, n, p)`, `binom_cdf(k, n, p)` | `k` successes in `n` tries of probability `p` |
| `binom_inv(q, n, p)` | the smallest `k` with `binom_cdf(k, n, p)` at least `q` |
| `poisson_pdf(k, rate)`, `poisson_cdf(k, rate)` | `k` events when `rate` events are expected; `rate` is more than 0 |
| `poisson_inv(q, rate)` | the smallest `k` with `poisson_cdf(k, rate)` at least `q`; `q` is less than 1 |
| `uniform_pdf(x, low, high)`, `uniform_cdf(x, low, high)`, `uniform_inv(p, low, high)` | the uniform distribution between `low` and `high` (`low` is less than `high`) |

The values agree with Python's `statistics.NormalDist` and `math.erf` to 12 digits.

## Module sample

| Function | Result | Meaning |
|---|---|---|
| `draw(xs, n, replace)` | list | `n` items of the list; without replacement (`False`) an item is taken at most once and `n` is at most the length of the list |
| `bootstrap(xs, rounds)` | list | for each of `rounds` rounds, the mean of a sample with replacement of the size of the list; the deviation of the result estimates the error of the mean |

Both use the generator of `math.random`: after `random.seed(n)` the same call gives the same result.

## Module histogram

`bins(xs, count)` gives a list of `count` records `Bin` with `low`, `high` and `count`: bins of equal width from the smallest to the largest number; a number belongs to the bin whose `low` it reaches, and the last bin also holds the largest number. When all the numbers are equal every bin has width 0 and the first holds them all.

## Module moving

| Function | Result | Meaning |
|---|---|---|
| `simple(xs, n)` | list | the mean of the last `n` numbers for each item; the first `n - 1` items are `null` |
| `exponential(xs, alpha)` | list | the first item is the first number, then `alpha * x + (1 - alpha) * the item before`; `alpha` is more than 0 and at most 1 |
