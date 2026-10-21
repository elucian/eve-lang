<!-- Generated from the specification, the tests and the benchmarks. Do not edit this page. -->

# Operators

From the tightest binding to the loosest: a higher precedence binds tighter. Assignment and modifier operators have precedence 0.

| Symbol | Name | Kind | Precedence | Associativity | Meaning |
|---|---|---|---|---|---|
| `()` | call | postfix | 140 | left | Call of a function or method. |
| `[]` | index or slice | postfix | 140 | left | Index (1-based) or slice `[n..m]`; `$` is the last index; `[*]` selects a whole dimension. |
| `.` | member access | postfix | 140 | left | Member of an object, module or class; qualified name. |
| `-` | negation | prefix | 130 | right | Unary minus. It binds tighter than `^`: `-2 ^ 2` is `(-2) ^ 2 = 4`; with an operand on its left `-` is the subtraction. |
| `not` | logical not | prefix | 130 | right | Logical negation. |
| `^` | power | infix | 120 | right | Power. `**` is a comment. |
| `/` | division | infix | 110 | left | Division always returns Real; between paths it is the smart concatenation. |
| `*` | multiplication | infix | 110 | left | Multiplication; string replication (`'-' * 80`). |
| `%` | remainder | infix | 110 | left | Remainder. Inside a placeholder `%` is the format operator: `{n % i5}`. |
| `+` | addition | infix | 100 | left | Addition; string concatenation (a string joined with another literal gives a String). |
| `-` | subtraction | infix | 100 | left | Subtraction; set difference. |
| `><` | cartesian product | infix | 90 | left | Pairs in row-major order, the left operand is the outer loop. Precedence proposed. |
| `..` | closed range | infix | 90 | none | Range [a, b]. The step follows in parentheses: `(1..5)(0.1)`. Also slice notation in an index. |
| `>..<` | open range | infix | 90 | none | Range (a, b). The step follows in parentheses: `(1..5)(0.1)`. Also slice notation in an index. |
| `..<` | range open at the end | infix | 90 | none | Range [a, b). The step follows in parentheses: `(1..5)(0.1)`. Also slice notation in an index. |
| `>..` | range open at the start | infix | 90 | none | Range (a, b]. The step follows in parentheses: `(1..5)(0.1)`. Also slice notation in an index. |
| `+-` | range around a value | infix | 90 | none | `b +- t` is the closed range `(b - t)..(b + t)`. |
| `<<` | shift left | infix | 80 | left | Shift left; also a modifier that shifts a variable in place. |
| `>>` | shift right | infix | 80 | left | Shift right; also a modifier that shifts a variable in place. |
| `&&` | intersection | infix | 70 | left | Intersection of two sets; a list operand gives a DataSet. |
| `\|\|` | union | infix | 60 | left | Union of two sets; a list operand gives a DataSet. |
| `as` | quick format | infix | 55 | left | Formats a value into a string (date, time, number). Precedence proposed. |
| `==` | equal | infix | 50 | left | Equal value (deep comparison for objects). |
| `eq` | equivalent | infix | 50 | left | Same value and same type. |
| `>` | greater than | infix | 50 | left | Greater than. |
| `>=` | greater or equal | infix | 50 | left | Greater than or equal to. |
| `in` | belongs to | infix | 50 | left | Membership; also the generator of a builder and the visitor of a `for`. |
| `is` | same object | infix | 50 | left | Compares locations (identity), or checks a type. |
| `is not` | different object | infix | 50 | left | Different locations. |
| `<` | less than | infix | 50 | left | Less than. |
| `<=` | less or equal | infix | 50 | left | Less than or equal to. |
| `=~` | approximate match | infix | 50 | left | Approximate match: a string matches a pattern (`s =~ "/re/"`), a number is within a tolerance (`x =~ b +- 0.01`, or `$epsilon` when omitted). `==` is the exact match. |
| `<>` | not equal | infix | 50 | left | Different value. `!=` is not Eve. |
| `not eq` | not equivalent | infix | 50 | left | Different value or different type. |
| `not in` | does not belong to | infix | 50 | left | Negated membership. |
| `and` | logical and | infix | 40 | left | Logical AND; also joins the generators and the condition of a builder. |
| `xor` | logical exclusive or | infix | 30 | left | Logical XOR. |
| `or` | logical or | infix | 20 | left | Logical OR. |
| `if else` | conditional | ternary | 10 | right | `a if c else b`. |
| `+=` | increment, or add elements | modifier | 0 | right | Changes the variable on its left. On a List or Array and a scalar it updates every element in place; on a DataSet or a DataMap `+=` adds and `-=` removes. |
| `<+` | append | modifier | 0 | left | Appends at the end of a list; `a <+ b` concatenates. Used as an expression it returns a new list (precedence open). |
| `:=` | assign | modifier | 0 | right | A statement: infers the type; shares the reference of an object or collection and copies a native value. |
| `=` | assignment expression | infix | 0 | right | An expression: no type inference, returns its value, chains (`a = b = 5:Integer`); also binds typed parameters and defaults. |
| `::` | assign a clone | modifier | 0 | right | Assigns a deep copy. |
| `:>` | numeric conversion | infix | - | left | Numeric conversion; subtype to supertype. Precedence open. |
| `/=` | divide in place | modifier | 0 | right | Changes the variable on its left. On a List or Array and a scalar it updates every element in place; on a DataSet or a DataMap `+=` adds and `-=` removes. |
| `*=` | multiply in place | modifier | 0 | right | Changes the variable on its left. On a List or Array and a scalar it updates every element in place; on a DataSet or a DataMap `+=` adds and `-=` removes. |
| `:` | pair, label, type hint | syntax | - | none | Type hint (`x:Integer`), label (`name: job`), pair (`key:value`), named argument (`y: 2`). |
| `^=` | power in place | modifier | 0 | right | Changes the variable on its left. On a List or Array and a scalar it updates every element in place; on a DataSet or a DataMap `+=` adds and `-=` removes. |
| `+>` | insert at start | modifier | 0 | left | Puts the element or list on its left in front of the list on its right: `let x +> lst;`. |
| `%=` | remainder in place | modifier | 0 | right | Changes the variable on its left. On a List or Array and a scalar it updates every element in place; on a DataSet or a DataMap `+=` adds and `-=` removes. |
| `<-` | remove first | modifier | 0 | right | `<- lst` removes the first element; `x <- lst` removes the first element equal to `x`. Capture form open. |
| `->` | remove last | modifier | 0 | left | `lst ->` removes the last element; `lst -> x` removes the last element equal to `x`. Capture form open. |
| `=>` | result | syntax | - | none | Result list of a function, method or lambda. |
| `-=` | decrement, or remove elements by value | modifier | 0 | right | Changes the variable on its left. On a List or Array and a scalar it updates every element in place; on a DataSet or a DataMap `+=` adds and `-=` removes. |
| `<:` | supertype | syntax | - | none | Supertype in a derived type declaration. |
