<!-- Generated from the specification, the tests and the benchmarks. Do not edit this page. -->

# Delimiters

Comments, strings and the other bracketed forms of the source text.

| Opens | Closes | Kind | Meaning |
|---|---|---|---|
| `#` | end of line | comment | Title comment, indentation 0 only. |
| `##` | end of line | comment | Subtitle comment, indentation 0 only. |
| `**` | end of line | comment | Note: anywhere outside a literal. |
| `(**` | `**)` | comment | Expression comment, may span lines, does not nest. |
| `/*` | `*/` | comment | Block comment, ends at the first `*/`, does not nest. |
| `'` | `'` | literal | Rune: one Unicode code point; `''` is nil. |
| `"` | `"` | literal | String: UTF-8 text on one line; placeholders `{name}` and `{name % format}`; literal braces `\{` `\}`. |
| `"""` | `"""` | literal | Text literal on several lines: raw, no escapes, indentation of the closing quotes removed. |
| `{` | `}` | escape | Placeholder inside a string: `{name}` or `{name % format}`; the value is written by its type; a literal brace is `\{` or `\}`. |
| `{U+` | `}` | escape | Placeholder with a Unicode code point, 1 to 6 hexadecimal digits: `{U+03B1}` is α. |
| `(` | `)` | collection | List literal, parameters and arguments, grouping of an expression. |
| `[` | `]` | collection | Array literal (vector, matrix); index and slice after a value; `m[x, y]` is `m[x][y]`. |
| `{` | `}` | collection | Ordinal, DataSet, DataMap or Object literal; `{}` empty DataSet, `{:}` empty DataMap. |
| `;` | - | separator | Ends a statement. |
| `,` | - | separator | Separates elements, parameters and arguments. |
