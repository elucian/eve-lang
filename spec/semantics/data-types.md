# Data file types

Status: **0.1-draft**, level 5 (the data language, D-125). Everything on this page is a **proposal** for the author's review (Q-038); no tests and no implementation yet. Sources: the author's request of 2026-10-08.

## What they are

Six types describe the content of a file that a program loads and parses in memory: `Html`, `Xml`, `Htmlt`, `Csv`, `Dat` and `Json`. A value of one of these types is made by **opening** a file (or a stream of bytes, for example the body of an HTTP response); the type tells the parser how to read it and what a traversal gives back.

| Type | The file | A traversal gives | Status |
|---|---|---|---|
| `Json` | JSON text | one **element** (an object, an array, a scalar) at a time, depth first | proposed |
| `Csv` | text with separated fields, usually a header row | one **row** at a time | proposed |
| `Dat` | text with fixed-width fields (a record layout) | one **record** (one row of the layout) at a time | proposed |
| `Xml` | XML text | one **element** at a time, depth first | proposed |
| `Html` | HTML text | one **element** at a time, depth first | proposed; the name is shared with the safe-page type of the HTML templates (Q-038) |
| `Htmlt` | an HTML template: HTML with `{expression}` holes | the **nodes** of the template; rendering fills the holes | proposed; see `tutorial/templates.html` (Q-027) |

## Rules

- **Derived types.** Every one of these types is derived with `<:` from a common ancestor, like any class: `class Csv = {…} <: Source;` (the name of the ancestor is open). They are **defined mostly in Eve**, later, in the standard library: the compiler needs to know only the ancestor and the traversal protocol below.
- **Buffered load.** Opening a file does not read it all. The value keeps a **buffer**: the parser reads a block of the file, hands out the units of that block one by one and reads the next block when the buffer is empty. A file larger than the memory can be processed, and the memory used does not depend on the size of the file. A call that asks for the whole content (`.all()`, proposed) is allowed and loads everything.
- **Traversal.** A value of these types can be the source of a `for` loop. The loop takes the units in the order of the file: **row by row** for `Csv` and `Dat`, **element by element** (object by object) for `Json`, `Xml` and `Html`. The loop variable holds one unit; the unit is valid inside the body (a `clone` keeps it longer).
- **Errors.** A file that is not well formed raises an error when the parser **reaches** the bad unit, not when the file is opened: the units before it have already been given to the loop. The error carries the position (line and column, or byte offset).
- **Close.** The file is closed when the loop ends, by `break` or by an error, and when the value goes out of scope (a registered `defer` is not needed).
- **Strings and placeholders.** The text of a unit is a `String`. The values inside it are not converted to numbers or dates unless the program asks (`row["total"].real()`, or a declared layout).

## Example *(proposed, the module and the calls are illustrations)*

```eve
from "lib" use (csv);
process main is
  new orders: Csv := csv.open("orders.csv");   ** nothing is read yet but the first block
  new sum := 0.0;
  for row in orders do                          ** one row at a time
    let sum += row["total"].real();
  done;
  print "total = {sum % f10.2}";
return;
```

```eve
new tree: Json := json.open("customers.json");
for item in tree.each("orders") do              ** one object at a time
  print "{item["id"]}: {item["customer"]}";
done;
```

## Open points

All are collected in Q-038 (`plan/decision_level5.md`): the ancestor class and the traversal protocol (the iterator), the names of the modules, `Html` against the `Html` of the templates, the layout of a `Dat` file, the access to a unit (`row["name"]`, `row.name`, `row[2]`), writing and not only reading, streams from the network, encodings and the line ending, and the level of each type.
