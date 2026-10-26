# Finance

Status: **draft**, level 3. Library step L6. Written in Eve (`lib/finance/`), over `Decimal` and `math`. Feature: F-LIB-03.

An amount of money is a `Decimal`: it keeps its scale and never has the error of a `Real`. A currency is its ISO 4217 code; the digits of its smallest unit come from the meta database ([meta.md](meta.md), table `currency`). A rate is a fraction of 1 (`0.05` is 5%), except in the module `percent`, where a percentage is a number of percent (`5` is 5%). The calculations that grow or discount (interest, loans, investments) are made with `Real` numbers and give a `Real`; `money.from_real` and the functions that say "money" give an amount rounded to the smallest unit of a currency. A wrong argument is `$err_argument` (17), a division by zero `$err_divide` (12).

## Rules of import

`from lib use (finance);` gives the modules `finance.money`, `finance.percent`, `finance.interest`, `finance.loan`, `finance.invest`, `finance.tax`, `finance.depreciation` and `finance.invoice`; a module can be imported alone, `from lib/finance use (money);`.

## Decimal rounding

These methods of the type `Decimal` are what the module `money` stands on.

| Method | Result | Meaning |
|---|---|---|
| `d.scale()` | `Integer` | the digits after the point: `12.50d.scale()` is 2 |
| `d.units()` | `Integer` | the number without its point, as a whole number: `12.50d.units()` is 1250 |
| `d.round(n)`, `d.round(n, mode)` | `Decimal` | the value with the scale `n` (0 to 18): more digits are zeros, fewer are rounded by the mode; the default mode is `"half_up"` |
| `Decimal.of(units, scale)` | `Decimal` | `Decimal.of(1250, 2)` is `12.50d` |
| `Decimal.parse(text)` | `Decimal` | `Decimal.parse("3.14")` is `3.14d`; anything else is `$err_parse` |

The modes of `round`:

| Mode | Rule | 2.5 | 3.5 | -2.5 |
|---|---|---|---|---|
| `half_up` | the tie goes away from zero (the school rule) | 3 | 4 | -3 |
| `half_even` | the tie goes to the even neighbour (banker's rounding, the rule for money) | 2 | 4 | -2 |
| `half_down` | the tie goes toward zero | 2 | 3 | -2 |
| `up` | away from zero when anything is cut | 3 | 4 | -3 |
| `down` | toward zero (the digits are cut) | 2 | 3 | -2 |
| `ceiling` | toward plus infinity | 3 | 4 | -2 |
| `floor` | toward minus infinity | 2 | 3 | -3 |

A mode that is not one of these, and a scale outside 0 to 18, are `$err_argument`.

## Module money

| Function | Result | Meaning |
|---|---|---|
| `digits(currency)` | `Integer` | the digits of the smallest unit: 2 for `EUR` and `USD`, 0 for `JPY`, 3 for `KWD`; an unknown code is `$err_argument` |
| `is_currency(code)` | `Logic` | is the text a currency code (capital letters) |
| `real(x)` | `Real` | an `Integer`, a `Real` or a `Decimal` as a `Real` |
| `round(amount, currency)`, `round(amount, currency, mode)` | `Decimal` | the amount rounded to the smallest unit; the default mode is `"half_even"` |
| `from_real(x, currency)`, `from_real(x, currency, mode)` | `Decimal` | an amount from a `Real`, rounded the same way; a tie is judged on 9 digits, so 2.675 as a `Real` rounds like the text 2.675 |
| `minor(amount, currency)` | `Integer` | the amount in the smallest units (`12.50` EUR is 1250), rounded first |
| `from_minor(units, currency)` | `Decimal` | the amount of a whole number of smallest units |
| `allocate(amount, ratios, currency)` | list | the amount shared in proportion to the ratios (numbers, not negative, not all zero) so that the parts add up to it exactly: each part is rounded down to the smallest unit and the units left go one by one to the parts with the largest remainders, the first of them first |
| `split(amount, parts, currency)` | list | the amount shared in equal parts that add up to it: the first parts have the extra units |

```eve
print money.allocate(100.00d, (1, 1, 1), "EUR");   ** (33.34,33.33,33.33)
```

## Module percent

| Function | Result | Meaning |
|---|---|---|
| `change(old, new)` | `Real` | the change in percent: `change(50, 60)` is 20; an old value of 0 is `$err_divide` |
| `of(part, whole)` | `Real` | the share in percent: `of(25, 200)` is 12.5 |
| `markup(cost, price)` | `Real` | the price over the cost in percent of the cost |
| `margin(cost, price)` | `Real` | the price over the cost in percent of the price |
| `price_from_markup(cost, markup)`, `price_from_margin(cost, margin)` | `Real` | the price that gives the markup or the margin; a margin of 100 or more is `$err_argument` |
| `add(amount, percentage, currency)` | `Decimal` | the amount raised by the percentage (cut by a negative one), rounded to the smallest unit |
| `part(amount, percentage, currency)` | `Decimal` | the percentage of the amount, rounded the same way |

## Module interest

| Function | Result | Meaning |
|---|---|---|
| `simple(principal, rate, years)` | `Real` | the simple interest |
| `compound(principal, rate, years)`, `compound(principal, rate, years, times_a_year)` | `Real` | the amount after the years, compounded some times a year (1 by default) |
| `future_value(present, rate, periods)`, `present_value(future, rate, periods)` | `Real` | the value after, and the value now of, an amount that grows at the rate of each period |
| `effective_rate(nominal, times_a_year)`, `nominal_rate(effective, times_a_year)` | `Real` | the effective yearly rate of a nominal one compounded some times a year, and back |
| `periods_to_reach(present, future, rate)` | `Real` | the periods that a value needs to grow to another; the values are more than 0 and the rate is not 0 |

## Module loan

| Function | Result | Meaning |
|---|---|---|
| `payment(principal, yearly_rate, months)` | `Real` | the monthly payment of an annuity loan; a rate of 0 divides the principal |
| `schedule(principal, yearly_rate, months, currency)` | list of `Payment` | one `Payment` for each month, with `number`, `amount`, `interest`, `principal` and `balance` as amounts of money; the payment is rounded to the smallest unit, the interest of each month by half-even, and the last payment is what clears the balance |
| `total_interest(schedule)` | `Decimal` | the sum of the interest of a schedule |

## Module invest

The first cash flow is at time 0, usually the negative investment; the next ones come one period after the other.

| Function | Result | Meaning |
|---|---|---|
| `npv(rate, flows)` | `Real` | the net present value: the flow *k* divided by (1 + rate) to the power *k* - 1 |
| `irr(flows)` | `Real` | the rate at which the net present value is 0, searched between -99% and 1000%; flows with no loss or no gain, and a flow with no such rate, are `$err_argument` |
| `payback(flows)` | `Real?` | the periods after which the sum of the flows is 0 or more, the last period by a straight line; `null` when it never is |

## Module tax

| Function | Result | Meaning |
|---|---|---|
| `brackets(income, table, currency)` | `Decimal` | the tax by brackets: the table is a list of pairs (upper limit, rate) with rising limits and `null` as the last limit; each part of the income between two limits is taxed at the rate of its bracket |
| `vat_of(net, rate, currency)` | `Decimal` | the VAT in a net price |
| `vat_add(net, rate, currency)` | `Decimal` | the price with VAT |
| `vat_remove(gross, rate, currency)` | `Decimal` | the net price of a price with VAT |

## Module depreciation

| Function | Result | Meaning |
|---|---|---|
| `straight_line(cost, salvage, life)` | `Real` | the same loss every year |
| `declining_balance(cost, salvage, life, year)`, `declining_balance(cost, salvage, life, year, factor)` | `Real` | the loss of a year: each year `factor / life` of the value at the start of the year (the factor is 2 by default), never below the salvage value |
| `sum_of_years(cost, salvage, life, year)` | `Real` | the loss of a year by the sum of the years' digits |

The salvage value is from 0 to the cost, the life is 1 or more, and the year is from 1 to the life.

## Module invoice

A `Line` has `description`, `quantity` (a `Decimal`), `unit_price` (without tax) and `tax_rate` (a `Decimal`, `0.19d` for 19%).

| Function | Result | Meaning |
|---|---|---|
| `line_net(line, currency)` | `Decimal` | quantity times unit price, rounded to the smallest unit |
| `totals(lines, currency)`, `totals(lines, currency, rounding)` | `DataMap` | the keys `net`, `tax` and `gross`. With the rounding `"line"` (the default) each line is rounded, its net and its tax, and the totals are the sums of the rounded amounts; with `"total"` the exact amounts are added and only the totals are rounded. An empty list gives zeros |
