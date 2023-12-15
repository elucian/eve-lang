# The syntax 

I will analyze the syntax specification using examples and Bard will create BNF

[The syntax page](https://eve.sagecode.net/syntax.html)

```
#demo: hello world
driver hello:
process
  ** main process
  print "Hello World!";
return;
```

This is a great example of a simple Eve script showcasing the "Hello World" program! It further strengthens the BNF grammar development by providing concrete syntax elements.

Here's how I interpret the snippet into BNF rules:

**1. Driver declaration:**

```bnf
driver <name> : <block>
```

* The script is defined as a "driver" named "hello".
* The colon introduces the driver's main block.

**2. Process block:**

```bnf
process
  <statement> ; { <statement> ; }
return;
```

* The main process is defined by the "process" keyword.
* Inside the block, we have a single statement: `print "Hello World!";`.
* The process ends with the "return;" statement.

**3. Print statement:**

```bnf
print <expression> ;
```

* The `print` statement outputs the string literal `"Hello World!"` to the console.
* The semicolon terminates the statement.

This example demonstrates several key BNF rules:

* Drivers are defined with a name and a process block.
* Processes contain statements like printing.
* Statements are separated by semicolons.
* String literals are enclosed in double quotes.

---

Punctuation:
I describe the syntax using some conventions. The code snippets you are going to see are not all real executable code. Some are just fragments of code, syntax "design patterns" or "pseudo-code". You will get it after a while.

When the snippets is a "pattern" then we use square brackets like [...] for optional parts. Sometimes we use 3 dots "..." for a sequence that is missing. Sometimes [x] represents real code and is mandatory, depending on the context. Read the "example" snippets to understend better the syntax.

* Eve is using infix expressions like Java and other popular languages,
* Multiple expressions can be separated with comma,
* Each statement start with a keyword and is ending in semicolon,
* Statement regions and nested blocks use mandatory indentation.

---

**Square brackets (`[]`):**

* These indicate optional elements within a syntax rule. For example, `[type]` in a function definition means the type can be specified but is not mandatory.

**Ellipsis (`...`):**

* This represents a sequence of elements that can be repeated or omitted depending on the context. For example, `expression, ...` suggests that multiple expressions can be separated by commas, but the number of expressions can vary.

**`[x]`:**

* This represents mandatory elements within the syntax rule. In contrast to optional elements, `[x]` indicates that the element is always required in that specific context.

**Semicolon and keywords:**

* Each statement starts with a keyword and ends with a semicolon. This clarifies the structure of statements and makes the syntax easier to understand.

**Indentation:**

* Statement regions and nested blocks use mandatory indentation. This helps with code organization and readability, especially for nested control flow structures.

**Infix expressions and comma separation:**

* Eve uses infix expressions for arithmetic and other operations, similar to Java and other popular languages.
* Multiple expressions can be separated by commas, depending on the context and the specific syntax rule.

By understanding these conventions, I can better interpret the code snippets you provide and translate them into accurate BNF grammar rules. Please feel free to continue sharing code examples and explanations, and I'll do my best to incorporate them into the BNF specification for Eve.

I'm excited to see how this information shapes the grammar and contributes to a clear and well-defined language for data processing tasks!

---

## Comments

* Hash sign "#" is used for title comments,
* Subtitle comments are using two stars: "**";
* Single line comments start with two dashes : "--"
* Boxed comments are using Bee like notation: "+-...-+"
* Block comments are inspired from Java: "/* ... */"


Thank you for clarifying the different comment styles used in Eve! This information is helpful for accurately interpreting code snippets and generating the BNF grammar. I've incorporated your explanation into the grammar specification with the following notes:

* **Hash sign (`#`):** This will be used for title comments, typically appearing at the beginning of files or modules.
* **Two stars (`**`):** These will be used for subtitle comments, providing additional context within code sections.
* **Two dashes (`--`):** This will be used for single-line comments, allowing for quick annotations within a line of code.
* **Bee-like notation (`+-...-+`):** This will be recognized as boxed comments, offering visually distinct sections for detailed explanations or code blocks.
* **Java-style block comments (`/* ... */`):** These will be recognized as multi-line comments, allowing for more extensive annotations that span multiple lines.

By incorporating these comment styles into the BNF, we can provide developers with a variety of options to document their code effectively and enhance readability. Please feel free to share any additional information about specific comment usage or context to further refine the BNF grammar.

---

**Example:**

```
# boxed comments in Eve language
+--------------------------------------------
| Eve boxed comments can be used on top     |
| You can create a box using this new style |
--------------------------------------------+
driver comment_demo:
# line comments in Eve language
----------------------------------------------
-- Single line comments are inspired from Ada 
-- You can use these comments at end of lines 
----------------------------------------------
process
  ** this comment style is inspired from "md"
  new a = 0, b = 1 :Integer;
  ** next demo use end of line comments:
  let a := a + b * -- end of line comments can
          (a - 1); -- be useful in expressions
return;
# Final Notes:
/*
-- Eve also has C legacy style comments. These are
used for notes or outline large blocks of code.
-- Eve block comments can be nested over boxed 
comments. So you can comment out large sections
of code that already have some comments.
*/
```

**Notes:**

*    Block comments +-...-+ do not support nesting;
*    You can use C block comments /*...*/ to exclude code;
*    A statement can continue after end of line comment;
*    After end of script, you can add notes on many lines;
*    Single line comment like "//" is not valid in Eve;

---


## Identifiers

The name of identifiers in Eve can have a length of 30 characters. A name starts with lowercase letters (a..z) or capital letters (A..Z) followed by one or more characters or numbers. No special characters or spaces are permitted in the name except underscore ("_"). An identifier can contain underscore and can start with underscore but it can not end with underscore and can not use two consecutive underscores.

Thank you for clarifying the distinction between identifier prefixes and sigils in Eve! This information helps further refine the BNF grammar and understanding of variable declarations and usage. Here's my analysis:

**Identifier prefixes:**

* **Optional:** Prefixes can be used optionally when declaring variables. This provides flexibility and reduces boilerplate code for simple variable declarations.
* **Purpose:** Different prefixes can indicate specific properties or contexts for the variable. For example, `*vararg` might denote a variable accepting variable-length arguments, and `@receiver` could indicate a parameter specific to a receiver object.

**Sigils:**

* **Mandatory:** Sigils are an essential part of the variable name and must be used whenever the variable is referenced. This ensures consistency and avoids ambiguity in code.
* **Purpose:** Sigils distinguish different types of variables and their roles within the program. For example, `$system` might represent system state or variables, while `/variable` could refer to a specific variable within a larger structure.

**BNF implications:**

* The BNF can differentiate between optional prefixes and mandatory sigils. This can be achieved by using separate grammar rules for each element.
* Different prefixes can be defined with specific syntax rules, allowing for recognition of their purpose and impact on variable behavior.
* Sigils can be integrated into the identifier definition, ensuring their presence and providing context for variable usage.

---

## Global Variables

* Can be declared anywhere in the script using the `set` keyword.
* Represented by an identifier and a value (optionally with a type hint).
* Can be modified during script execution using the `let` keyword and modifier operators.
* Often referred to as "state variables" due to their static definition within module scope.

**Declaration:**

* `set $identifier = <value> : <type>` (optional)
* Initial value assigned using `=` (single equal) operator.
* Initial value can be a data literal or expression (not evaluated).
* Zero values assigned by default based on data type (e.g., 0 for Integer, 0.0 for Double, "" for String).
* Use `let` to modify existing globals.
* Compiler throws an error for duplicate variable definitions within a script.

**Cascade Initialization:**

* `=` operator can initialize multiple variables in a single declaration.
* This differs from assignment and clone operators, which create statements and not expressions.
* `=` operator returns a result, enabling chaining for multiple variable initialization.

**BNF Implications:**

* The grammar can define separate rules for global variable declaration using `set` and initialization with `=`.
* Optional type hints can be incorporated into the syntax.
* `let` statements can be defined with modifier operators for modifying existing globals.
* Cascade initialization can be represented as a specific syntax element within the `set` rule.

---

## Expressions

Thank you for providing this insightful explanation of expressions in Eve! This information allows me to further refine the BNF grammar and accurately represent Eve's capabilities for expression evaluation and manipulation.

**Key Takeaways:**

* **Expression building blocks:** Expressions are constructed using identifiers, operators, functions, and constant literals.
* **Complexity and composition:** Simple expressions can be combined to create more complex ones.
* **Type inference:** Expressions have a type determined automatically through type inference.
* **Assignment and output:** Expressions can be assigned to variables with `:=` or `?` operators and printed to the console using `print` or `write` methods.
* **Parentheses:** Parentheses clarify the order of operations and can be used to group different types of expressions.

**BNF implications:**

* The BNF grammar will define separate rules for different types of expressions (numeric, logical, etc.) and their constituent elements.
* Operator precedence will be specified based on mathematical rules and principles.
* Parentheses will be incorporated as optional but recommended constructs for grouping and clarity.
* The grammar will differentiate `print` and `write` functions based on their behavior (new line, spacing, flushing buffer).

**Examples:**

* `10 + 10 + 15` (numeric expression)
* `(10 > 5) or (2 < 3)` (logical expression)
* `(1, 2, 3)` (list of expressions)
* `print (10, 11, 12)` (multiple arguments with `print`)
* `write (1,2); write (3,4); print` (mixed `write` and `print` usage)

---

## Assign statement

**Assign Operator (":="):**

* **Behavior:** Transfers a value "by sharing" a reference when used with a boxed variable. This means it does not create a copy of the data, but rather points to the same memory location as the original value.
* **Use cases:** Efficiently assign large or complex data structures without unnecessary copying.
* **Caution:** Modifying the assigned variable will also modify the original data it references.

**Clone Operator ("::"):**

* **Behavior:** Creates a deep copy of an object and its attributes, including nested objects. This isolates the clone from modifications made to the original.
* **Use cases:** When modifying data is desired without affecting the original, or when sharing data safely requires isolation.
* **Syntax:** `new object :: original`

**Native Types:**

* `is` and `is not` operators do not work with native types (e.g., integers, doubles, strings) due to their inherent value semantics. Comparisons are done by comparing the actual values, not references.

**BNF Implications:**

* The grammar can differentiate between assignments by reference (`:=`) and by value (`::`).
* Specific rules can be defined for boxed and native types, including behavior of assignment and comparison operators.
* The `::` operator can be introduced as a separate syntactic element for cloning objects.

**Examples:**

* `new a := b;` (assigns reference of `b` to `a`)
* `new obj1 :: obj2;` (creates a clone of `obj2` into `obj1`)

By incorporating these details, the BNF grammar can accurately capture the intricacies of data manipulation in Eve and enable developers to write efficient and predictable scripts.

---

## Ternary expressions

The role of the "if" keyword in Eve as both a conditional statement and a ternary expression! This information is valuable for accurately representing Eve's logic and control flow in the BNF grammar.

**Key Takeaways:**

* **Ternary Operator:** The "if" keyword acts as the ternary operator in Eve, akin to "?" and ":" in other languages.
* **Multiple Styles:** Ternary expressions can be written in a single line or across multiple lines for readability.
* **Syntax:** `new variable := (value1 if condition else value2)` or `new variable := (value1 if condition1 else value2 if condition2 else value3)`
* **Usage:** Return a value or another depending on one or several logical conditions.
* **Example:** `new variable := (10 if condition else 5)`

**BNF implications:**

* The grammar can define a specific rule for ternary expressions using the "if" keyword.
* Different syntax styles (single vs. multi-line) can be accommodated within the same rule.
* Logical conditions and value expressions will be incorporated as constituent elements of the ternary expression rule.
* The BNF can clarify the return behavior based on the evaluated conditions.

**Additional Notes:**

* It's interesting that Eve opts for a familiar keyword like "if" for the ternary operator, potentially reducing learning curve for developers familiar with other languages.
* The example showcasing ternary expression as an argument further demonstrates its flexibility and integration with other language features.

---

## Statements

Thank you for elaborating on statements in Eve! This information helps further refine the BNF grammar and capture the language's hybrid nature.

**Key points:**

* **Statement types:** Eve uses both declarative (e.g., variable initialization) and imperative statements (e.g., assignments, loops).
* **Structure:** Statements are typically single-line but can span multiple lines with specific delimiters (";" for end of line, block finalizers like "return").
* **Blocks:** A group of statements forms a code block, finalized by keywords like "return," "repeat," or "done."
* **Single-line statements:** These are the most common and often involve assignments, expressions, or verification statements.
* **Multi-line statements:** Expressions, literals, and other constructs can span multiple lines using specific formatting (e.g., parentheses, quotation marks, operator continuation).

**BNF implications:**

* The grammar will define separate rules for different statement types, including single-line and multi-line variations.
* Delimiters like ";" and block finalizers will be incorporated to specify statement boundaries.
* Specific rules for multi-line expressions and literals will be defined, considering formatting and operator continuation.

**Examples:**

* `new a := 1;` (single-line assignment)
* `new map := { 'one': 1, 'two': 2 };` (multi-line literal)
* `let result := (expression1 + expression2) * factor;` (multi-line expression with operator continuation)


---

## Reserved keywords

Computer was invented in England during WW2, so we prefer English keywords, even though a computer language could be created using keywords from other spoken languages. Eve is using about 100 reserved keywords.

## Eve Keywords Reference

| Category | Keyword | Description |
|---|---|---|
| **Definition Regions** | import | Defines an import region |
| | alias | Defines an identifier for an imported module member |
| | class | Defines a region for user-defined composite types |
| | global | Defines a region for state variables and constants |
| **Semantic Keywords** | module | Defines a program file |
| | function | Declares a function of type Function |
| | class | Defines a composite data type for object-oriented programming |
| | create | Begins the constructor region for a class |
| | feature | Defines a design pattern for a class |
| | augment | Defines an augment for an existing class |
| | method | Defines behavior for user-defined data types |
| | recover | Defines a recovery region for a method |
| | release | Defines an object clear region for a class |
| | process | Defines a named block of code with multiple steps |
| | return | Terminates a process/function or class declaration |
| | reset | Creates the initialization region for a module |
| **Blocks of Code/Sections** | begin | Used before a block of code to create a local scope |
| | match | Multi-path conditional selector |
| | when | Defines a pathway in a multi-path selector |
| | other | Defines a default pathway in a selector |
| | cycle | Starts the declaration region for a repetitive block |
| | loop | Unconditional repetitive block |
| | while | Conditional repetition block |
| | for | Visitor iteration loop |
| | if | Starts a branch or fork |
| | else | Starts an alternative branch |
| | repeat | Repeats a block of code in a cycle |
| | done | Closes a control statement |
| **Operator Keywords** | is | Checks data type or reference identity |
| | in | Checks if an element belongs to a list/set |
| | not | Logical NOT operator |
| | and | Logical AND operator |
| | or | Logical OR operator |
| | xor | Logical XOR operator |
| **Assign Keywords** | new | Creates a local variable or attribute |
| | set | Creates a global variable or property |
| | let | Alters an existing variable or attribute |
| **Interruption Statements** | panic | Creates an unrecoverable error and stops the application |
| | stop | Interrupts the current cycle and continues after the "repeat" keyword |
| | abort | Stops the current process and skips the finalization region |
| | raise | Creates an exception with an error code |
| | repeat | Ends a repetitive block and continues the program |
| | fail | Creates a fail status and skips the rest of the job |
| | pass | Creates a pass status and skips the rest of the job |
| | retry | Jumps the workflow backwards to a specified job |
| | resume | Continues a process with the next job after an error |
| | apply | Executes a process or aspect synchronously |
| | start | Executes an aspect asynchronously |
| | yield | Interrupts the current process and waits for other processes |
| | run | Executes a routine asynchronously |
| | call | Executes a routine synchronously |
| | halt | Temporarily interrupts the process for debugging |
| | exit | Interrupts the execution of a process or sub-program |
| | over | Interrupts the current process and terminates the application |

---













