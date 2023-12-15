## Data Types

[Data Types](https://eve.sagecode.net/types.html)

**Strengths of Eve's data types:**

* **Gradual typing:** Allows for both explicit and implicit type declaration, improving code flexibility and readability.
* **Composite types:** Enables creation of complex data structures like records, variants, and arrays.
* **Safe coercion:** Implicit conversion between types is carefully controlled to prevent data loss and errors.
* **Expressive literals:** Various formats for dates, times, durations, and symbols make code concise and intuitive.
* **Logical type:** Provides a clear and consistent way to represent boolean values and perform logical operations.
* **User-defined types:** Allows programmers to create custom data types tailored to specific needs.

**Specific points that I found particularly interesting:**

* The use of native types and primitive types for different performance and feature requirements.
* The emphasis on safe coercion and the use of explicit conversion functions to avoid data loss.
* The detailed explanation of variant types and their potential for creating generic routines.
* The support for calendar dates, times, and durations with various formats for user input and output.

Overall, Eve's data type system appears well-designed and powerful, offering a good balance between flexibility and safety. It allows developers to create efficient and expressive programs while minimizing the risk of errors.

---

## Eve Data Types Table

| Type             | Description                                              | Storage                                       | Literals                                       |
|-------------------|---------------------------------------------------------|----------------------------------------------------|-------------------------------------------------------|
| **Native Types**     | Implemented by operating system, not directly used     | Single byte                                        | Numeric range (0x00..0xFF)                    |
| **Primitive Types** | Predefined with equivalent native types, faster     | Varies depending on type (Byte, Short, Integer)   | Numeric range, decimals, symbols, dates, times     |
| **Numeric Types**     | Discrete (bytes) and continuous (floating point)     | Varies depending on type (Byte, Short, Integer)   | Numeric range, decimals, fractions               |
| **Single Symbol**    | Represent a single UTF-8 code point                  | 4 bytes                                          | Single quoted characters                        |
| **Unicode Literal** | Unicode characters with case-insensitive hexadecimals | 4 bytes                                          | U+ or U- followed by hexadecimals               |
| **Composite Types**  | Unions of data elements, can be null                  | Varies depending on type (Record, Variant, List) | Data literals depending on type ((), [], {})     |
| **Range**           | Discrete range of elements                           | Not directly stored, calculated on demand        | Numeric range with optional ratio and limits      |
| **Logical Type**     | Boolean values (True, False)                        | Byte                                            | 0 for False, 1 for True                       |
| **User Types**       | Custom data types derived from system types         | Varies depending on user definition              | User-defined literals                         |
| **Variant**         | Polymorphic variable with one of multiple types       | Varies depending on variant type                  | User-defined literals depending on variant types  |
| **Calendar Date**   | Represented as YYYY/MM/DD                           | 4 bytes                                          | "YYYY/DD/MM", "DD/MM/YYYY", "MM/DD/YYYY"          |
| **Time & Duration** | Time (T12/T24) and Duration (ms)                   | Varies depending on type (Time, Duration)        | "hhhh:mm:ssxx,999ms" for Time; "y", "d", "m", "s", "ms" for Duration |

**Notes:**

* Implicit data conversion is possible with safe coercion to avoid data loss.
* Type inference helps determine data types based on literals and expressions.
* Gradual typing allows flexibility in type declarations.
* Eve offers a variety of data types for different needs and performance considerations.

I hope this table provides a helpful overview of Eve's data types. Please let me know if you have any questions or want to explore specific types in more detail.


---
So far so good.

