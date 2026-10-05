# 03 Types, collections and data (`RTY`)

## Advantages

**RTY-A01 Explicit Null, zero values for basics.** "Basic types are initialized with zero values, and a missing value is the explicit `Null`" (manifest). A clear default story is valuable in data code.

**RTY-A02 `/` always returns Real.** D-032. Removes the integer-division trap of C and Python 2.

**RTY-A03 Ordered collections by default.** DataSet sorted by value, HashMap sorted by key (D-058): output is deterministic, which makes tests and diffs of ETL output stable.

**RTY-A04 `::` clone and `:=` share are visible in the code.** D-049. Value vs reference is a decision the reader can see, and parameters follow the same rule (D-048).

**RTY-A05 Views over slices.** `v[a..b]` as a view (D-049) avoids copies when processing large buffers: a good fit for streaming data.

## Disadvantages

**RTY-D01 The ETL data types are missing.** No `Decimal` (money, quantities from SQL `NUMERIC`), no instant or timestamp with time zone (`Time` is "milliseconds of the day", `Date` is a proposal with era/year/month/day, D-032), no `Bytes` ("`Binary` and `Word` do not exist", D-032, while the manifest promises binary data, images and video), no `UUID`, no record/schema type that maps a table row or a JSON object with known fields. These are the types an ETL and web platform moves all day.

**todo** Enhancements are required. Suggest draft and create new types, type conversion linraries we need to design, version 2. For version 1 we keep going with current types.

**RTY-D02 Too many numeric types for scripts, too few for data.** *Applied 2026-10-05: D-080.* `Byte, Short, Integer, Natural, Real, Float, Ordinal, Rational` plus native `u8…f64`. `Rational` with "evaluation postponed until needed, computed with a precision" (D-032) is a research feature; `Decimal` is the one users need.

**answer** Ok, we implement Decimal in version v1. 

**RTY-D03 Names that lie.** *Applied 2026-10-05: D-080.* `HashMap` is a sorted map (D-058) — a hash map is by definition unordered; the name will mislead every programmer and every implementer (they will reach for a hash table and fail the tests). `Real` is an IEEE double. `Symbol` is a code point (other languages use "symbol" for interned names).

**todo** We have list for unsorted collections we do not need other. Use DataMap instead of HashMap. I agree, let's rename Symbol, Rune. I agree Real is IEEE double. 

**RTY-D04 Null, NIL, `_`, empty Object.** *Applied 2026-10-05: D-080.* `''` is NIL (empty symbol), `Null` is no value, `_` is always Null, `let o :Object;` is the Null object, `x is Null` is an identity test (D-032, D-058, D-059, D-063). Four ways to say "nothing" without a type that says "may be nothing". 

**Answer** Make Null a type, It start with capital letter, and null a constant of type Null. When o is Null, o == null. '' == Nill and '' <> null. A string is empty "" and if is empty is not Null.

**RTY-D05 Literal shapes decide types in surprising ways.** *Applied 2026-10-05: D-080.* Unquoted keys make an Object, quoted keys a HashMap (D-058); `(x)` is grouping but `(x,)` is a list (D-063); `{}` is a DataSet and `{:}` a map. JSON — the main data format of the web — writes `{"a": 1}` for what Eve should parse as a record.

**answer** EVE is curious language but if can be implemented many developers will find this comprehensive. Eve will parse {"a": 1} into DataMap (we just introduced) the data map. A data map support nesting elements. Good point. Let's extend data map.

## Antipatterns

**RTY-X01 Silent data loss in conversions.** *Applied 2026-10-05: D-080.* "`parse` coerces to the type of the target: Integer loses the decimals, Real keeps them, no error" (D-032 TYP-14); `let x = a / b :Integer` drops decimals silently. In ETL, silent truncation is the most expensive class of bug: the job "passes" and the warehouse is wrong.

**answer** in debug mode, a warning will be generated at compilation type, warning in line:x possible data loss.

**RTY-X02 Implicit string concatenation with numbers.** *Applied 2026-10-05: D-080.* "`"a" + 1` gives a String" (D-058). `+` is then non-associative across types (`1 + 2 + "a"` vs `"a" + 1 + 2`) and hides a missing conversion. A gradual type checker should reject it.

**answer** I agree, let's not do that, type check will fail compilation. We need explicit over implicit. "a" <+ 1, we can use instead of +, that will be safe because <+ will add to a collection that is a string. 

**RTY-X03 Type determined by the receiving variable.** `parse` adapts to the target type; a variant "takes a type when a value is assigned" (D-032 TYP-12). Behaviour depends on a declaration far away from the expression.

**RTY-X04 Mutable/immutable split by name (String vs Text).** D-058 makes `Text` a mutable rope. Two string types double every string API and every conversion; most modern runtimes use one immutable string plus a `StringBuilder`.

**answer** Unify via Interface: Implement a common string view interface (StrView) over both types so standard library functions (searching, regex, formatting) operate seamlessly on either without duplicating logic. Is this possible in Zig? If not maybe in other languages is possible. Eve better compilers will be smarter implementing this. The design stay. We have String and Text, two types.

## Recommendations

**RTY-R01 Add the data core for 0.1.**

| Type | Meaning | Why |
|---|---|---|
| `Decimal(p, s)` | exact base-10 number | money, SQL NUMERIC, CSV amounts |
| `Instant` | UTC point in time (ns or µs) | logs, events, HTTP dates |
| `DateTime` + `Zone` | local time with an IANA zone | business dates |
| `Date`, `Time`, `Duration` | as today, but specified | |
| `Bytes` | immutable byte buffer, with views | files, network, images, WASM memory |
| `Uuid` | 128-bit id | keys across systems |
| `Record` types | `record Person = {name: String, age: Integer?}` | rows, JSON objects, protocol messages |

**question** Do we need a record type? Looks like a class to me. Is a short-hend class declaration. In Eve would be:
class Person = {name: String, age: Integer?} <: Object;
Is this better?
type Person =  {name: String, age: Integer?} <: Record;
I let you decide.

**RTY-R02 Optional types instead of nullable everything.** *Applied 2026-10-05: D-080.* `T?` (or `Option(:T)`) and a `??` default operator; a plain `T` is never Null. Drop NIL as a separate concept; the empty symbol is just `''`.

**Answer** I agree, let's describe optional type and make some examples in specification. Good idea.

**RTY-R03 Fail loudly, convert explicitly.** *Applied 2026-10-05: D-080.* `Integer.parse("3.7")` is an error; `"3.7".to(Real).round()` is explicit. Division to Integer needs `div` or `floor`. `"a" + 1` is a type error; interpolation is the way to build text.

**answer** No, Integer.parse() is what developer whanted. Data may be real, but if user want it integer this is what he has intentionally wanted to happen. Real.parse("3.7") will not give a runtime error. In debug mode, throw a warning message. x + 1 when x is string is replaced by x <+ 1 in expression and will convert 1 to string and add to X, also 1 +> x will add 1 to x and will put "1" in front of x string.  

**RTY-R04 Rename to truthful names.** *Applied 2026-10-05: D-080.* `HashMap` → `Map` (sorted) and keep `HashMap` free for an unordered, faster map later; or `SortedMap`/`Dict`. `Real` may stay but document IEEE-754 binary64.
**answer** No deal: DataMap is invented and is sorted. By default a literlal {"key":"value"} will make a DataMap. If a Record is defined and a literal of this form is parsed {key:"value"} will create a Record. The record structure (fields) must be defined before use.

**RTY-R05 JSON-compatible literals.** Make `{"k": v}` a `Map(String, T)` and `{k: v}` a record literal, as today, but guarantee that every JSON document parses into Eve values and prints back unchanged (`json.parse`, `json.print`). Add a test level for round-trips.

**todo** Implement in spec/test

**RTY-R06 Columnar table type.** For ETL throughput a `Table` (named typed columns, Arrow-compatible layout) beats a list of objects by 10–100× in memory and speed. It also gives the server a natural wire format (`RNW-R04`).

**todo** Elaborate the solution direct in database.html when we define Table. Details for compiler implementation may be provided later in compliter.html

**RTY-R07 Drop or postpone `Rational`, `Ordinal` numeric meaning, native types in scripts.** *Applied 2026-10-05: D-080.* Keep the core small: `Integer` (i64), `Natural` maybe, `Real`, `Decimal`, `Logic`, `Symbol`, `String`, `Bytes`, time types.

**todo** Agree partially, we support from Ordinal. Very important, Boolean is an ordinal type. We support Rational in version 2.
