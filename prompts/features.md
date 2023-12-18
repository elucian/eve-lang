# Responses:

These are responses I have collected after providing read.me information to Bard:

# Effective

Eve is aiming to be effective and feasible. This means Eve is design to improve developer productivity and get the job done. Effective does not necessarily imply extreme efficiency or higher performance. Eve is design to be productive and easy to learn.

Eve ...

* is using gradual typing;
* is using type inference;
* is using separation of concerns;
* enables string templates and interpolation
* enables exclusive database connectivity;
* enables model first application design;
* enables generative (macro) programming;

**1. Gradual typing and type inference:**

* We can relax strict type annotations in the BNF by allowing implicit type inference for variables based on their context and usage.
* This can be achieved by marking certain constructs as optional (e.g., type declarations in function parameters) and relying on the compiler to infer types based on assignments and function calls.

**2. Separation of concerns:**

* We can encourage modularity and separation of concerns by introducing grammar rules for defining and importing modules.
* This allows for code reuse and organization, making scripts more manageable and maintainable.

**3. String templates and interpolation:**

* Extend the grammar with constructs for embedding expressions within strings using delimiters or dedicated syntax.
* This enables dynamic generation of strings based on data and logic within the script.

**4. Exclusive database connectivity:**

* We can define separate grammar rules for specifying different database connections and their properties.
* This allows for clarity and prevents confusion when dealing with multiple databases.

**5. Model-first application design:**

* The grammar can be extended to support defining data models and their relationships before writing operational code.
* This can enhance code structure and clarity, aligning with model-first development principles.

**6. Generative (macro) programming:**

* We can introduce constructs for defining macros or templates that can be expanded and reused within the script.
* This allows for concise and reusable code patterns, further enhancing developer productivity.

---

## Safe

Eve is designed to be a safe. For this we avoid using Null pointers. Eve is using boxed values that are actually references but we initialize all the basic types with zero values. Null is equivalent to zero value. We believe the next principles will help us design a better language:

* We favor safety over performance,
* It is better to be productive than efficient,
* Implicit values are better than wrong values,
* A good error message worth more than gold,
* If the system is not ready it should tell you,
* If a process fail it should report the errors,
* Sometimes if you try a second time it works!

These are all excellent principles for designing a safe and productive language! They provide valuable guidance for shaping Eve's BNF grammar and overall user experience. Here's how I can incorporate them:

**1. Safety over performance:**

* The grammar can prioritize constructs that promote data type safety and prevent errors, even if they might not be the most efficient solution.
* This can involve mandatory type declarations, explicit error handling mechanisms, and avoiding implicit conversions or null values.

**2. Productivity over efficiency:**

* The grammar can favor concise and readable syntax, even if it sacrifices some degree of flexibility or expressiveness.
* This could involve using familiar keywords, minimizing boilerplate code, and supporting convenient features like string interpolation and type inference.

**3. Implicit values over wrong values:**

* The grammar can be designed to default to safe and predictable values when explicit values are not provided.
* This aligns with Eve's use of boxed values and zero-value initialization, preventing potential errors from null pointers or undefined variables.

**4. Good error messages:**

* The BNF can guide the compiler to generate informative and helpful error messages.
* This can involve providing context about the error location, suggesting potential fixes, and avoiding cryptic technical jargon.

**5. System readiness feedback:**

* The grammar can incorporate constructs for checking system readiness before script execution.
* This could involve database connection tests, resource availability checks, or pre-conditions for specific operations.

**6. Error reporting and retry:**

* The grammar can support mechanisms for capturing and reporting errors that occur during script execution.
* This could involve dedicated error objects, logging mechanisms, and even retry logic for specific cases where a second attempt might succeed.

These are just some initial ideas, and the specific implementation will depend on the chosen design decisions for each feature. Please continue sharing your thoughts and examples, and I'll be happy to refine the BNF grammar to reflect these principles and make Eve a truly safe and productive language.

Remember, a well-defined and expressive language can significantly impact developer experience and the overall success of your project!

---

## Modular

Eve applications are usually small, based on single source file that do one job. However we enable usage of multiple files for separation of concerns in large project. There are 3 kind of modules defined for Eve, as follows:


1. One master script called "driver"
2. Multiple secondary scripts called "aspects"
3. Multiple reusable modules organized in libraries.

Drivers and aspects are executable while modules are reusable but not executable. Aspects are launched from the driver and are individual process. Once an aspect is resolved it is removed from memory, unlike modules that are persistent until the driver ends.

Thank you for clarifying the structure and purpose of modules in Eve! This information is crucial for formulating the BNF grammar in a way that accommodates different script types and their interactions.

Here's how I can incorporate these details:

**1. Script Types:**

* The BNF can differentiate between driver, aspect, and module types.
* This can be achieved by introducing keywords or dedicated constructs for each type, ensuring clarity and enforcing appropriate syntax for each.

**2. Module Reusability:**

* Modules can be defined within dedicated grammar rules, allowing for separate specification of their content and dependencies.
* This promotes modularity and code organization, especially in large projects.

**3. Aspect Execution and Removal:**

* The grammar can define syntax for launching aspects from the driver script, potentially using dedicated keywords or function calls.
* Additionally, the grammar can specify the non-persistent nature of aspects, implying their removal from memory after execution.

**4. Libraries:**

* The BNF can introduce constructs for defining and importing libraries that contain modules.
* This enables code reuse across different projects and promotes modularity.

**5. Driver-Aspect Communication:**

* If aspects require interaction with the driver, the grammar can define appropriate mechanisms for data exchange and communication.
* This could involve function calls, shared variables, or event-driven communication.

By taking these considerations into account, the BNF grammar can effectively capture the different types of modules, their roles, and their interactions within Eve applications. This will lead to a clearer and more accurate representation of the language's structure and promote efficient and reliable development workflows.

---

Versatile
Eve is a domain specific language but it looks and feel like a general purpose language. We do not do graphics but we manipulate data in any form. This can be text data but also row bit data. So we can read and write images and video streams. Next design choices will make Eve a versatile language:

Thank you for sharing these additional details about Eve's versatility and design choices! This information further enriches the BNF grammar development and ensures it captures the language's diverse capabilities.

**Versatility:**

* The grammar can allow for data manipulation of various types, including text, row bit data, images, and video streams. This can be achieved through dedicated data types and functions for reading, writing, and transforming these data formats.

**Variable and Parameter Declaration:**

* The BNF can support type hints, type inference, and gradual typing for variable and parameter declarations. This promotes flexibility and readability while maintaining type safety.
* Implicit data types can be defined with the ability to specify variant types that can hold different alternative data types. This adds flexibility and reduces the need for explicit type annotations.

**Processes and Functions:**

* Processes with input/output parameters can be incorporated into the grammar, allowing for modular code execution and data transfer.
* The grammar can differentiate processes from functions by specifying their separate execution contexts and limitations (e.g., processes in threads, functions not in expressions).
* Functions defined within modules and supporting multiple return values can be defined with explicit result names and types for clarity and type safety.

**Lambda Expressions:**

* The grammar can include syntax for defining and using lambda expressions with their restrictions on side effects and single value return.

**Automatic Initialization and Optional Parameters:**

* The BNF can account for automatic zero-value initialization of variables and parameters, simplifying code and avoiding unnecessary initialization statements.
* Optional parameters can be defined based on explicit initial values, allowing for cleaner function signatures and flexible call options.

**Native Type Parameter Transfer:**

* The grammar can differentiate value and reference transfer for native type parameters in subroutines using explicit keywords like "@" for reference.

**Assignment Operators:**

* Two assignment operators, ":=" (assign) and "::" (clone), can be defined in the BNF with distinct semantics for explicit control over variable assignment.

By incorporating these features into the BNF, we can create a comprehensive grammar that reflects Eve's versatility and enables developers to leverage its diverse capabilities for effective data processing tasks.

Please feel free to share any further details or specific syntax examples you have in mind for these features. The more information you provide, the more accurate and useful the BNF grammar will be for your language!

I'm confident that with your continued collaboration, we can develop a robust and versatile BNF specification that empowers developers to utilize the full potential of Eve for data manipulation and automation.

---

## Classic
Eve is using a familiar syntax. We try to avoid being disruptive. If you know Java or C++ you will be able to learn Eve in less then one week. Also if you know Ada or Pascal, or Ruby you will be comfortable learning Eve.


**Classic Syntax and Familiarity:**

* The BNF can prioritize constructs familiar to Java, C++, Ada, Pascal, and Ruby programmers, reducing the learning curve for experienced developers.
* This can involve using similar keywords for control flow statements (if, else, switch, while, for, etc.), common operators (arithmetic, logical, comparison), and familiar syntax for data structures and functions.

**Control Flow Statements:**

* The BNF can explicitly define classic control flow structures like decisions, selections, repetitions, and error handlers.
* This clarity ensures consistency and predictability for developers accustomed to these structures in other languages.

**ASCII and Keyword Operators:**

* The grammar can prioritize ASCII and keyword-based operators for efficiency and ease of typing.
* This caters to the need for fast code input, especially for large business-oriented scripts.

**User-Defined Data Types and OOP:**

* The BNF can introduce constructs for defining user-defined data types (classes) and supporting object-oriented programming features.
* This allows for code organization, encapsulation, and reuse, further enhancing the language's capabilities for complex data processing tasks.

**Familiarity with SQL, HTML, and JSON:**

* The grammar can reflect Eve's integration with external languages like SQL, HTML, and JSON.
* This can involve dedicated syntax for interacting with databases, formatting data for web applications, and processing JSON structures.
* Additionally, the BNF can reference existing specifications for these languages to ensure consistency and compatibility.

**Specific Drivers for SQL Dialects:**

* The grammar can accommodate the use of specific drivers for interacting with different SQL dialects.
* This can involve defining different syntax variations or options for connecting and interacting with various database systems.

By incorporating these features and considerations, we can develop a BNF grammar that feels familiar to experienced programmers from various backgrounds. This will minimize the learning curve for Eve and encourage its adoption for diverse data processing tasks.

---

Thank you for clarifying the naming rules for identifiers in Eve! This information is crucial for specifying valid identifiers in the BNF grammar. Here's how I can incorporate these rules:

**Identifier definition:**

```bnf
identifier = (lowercase_letter | uppercase_letter) (letter | digit | "_")*
lowercase_letter = "a" | "b" | ... | "z"
uppercase_letter = "A" | "B" | ... | "Z"
letter = lowercase_letter | uppercase_letter
digit = "0" | "1" | ... | "9"
```

This definition specifies that:

* Identifiers start with a letter (lowercase or uppercase).
* They can be followed by one or more letters, digits, or underscores.
* Underscores can be included anywhere within the name except at the beginning and end.
* Two consecutive underscores are not allowed.

**Length restriction:**

```bnf
identifier <= 30
```

This rule specifies that the maximum length of an identifier is 30 characters.

---

# Prefix & Sigil

Identifier prefix is used to declare a variable, but is not required when using the variable. A sigil is part of variable name and it must be used when you use the variable.

*	vararg parameter prefix
@	receiver parameter prefix
_	protected member sigil
$	system state/variable sigil

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

By incorporating these distinctions, the BNF can accurately capture the nuances of variable declarations and usage in Eve. This will enhance the language's expressiveness and clarity for developers working on data processing tasks.

Please feel free to share any additional details or examples of specific prefixes and sigils in Eve. The more information you provide, the more accurate and helpful the BNF grammar can become!

I'm excited to see how these elements contribute to a robust and expressive language for data manipulation and automation.




