## Project Structure

This page was created with Bard after reading: [structure](https://eve.sagecode.net/structure.html)

---

## Script Types:

* **Driver:** The main executable script, responsible for starting the project and managing other scripts.
* **Aspect:** Reusable modules that provide specific functionalities, executed in parallel or sequentially within a driver.
* **Module:** Shared resources containing state and functions, accessible by any script within the project.

**Key Features:**

* **Composition:** Drivers can import modules and combine aspects for complex behavior.
* **Parallelism:** Aspects can be executed concurrently for efficient processing.
* **Modularity:** Aspects and modules provide reusable components for various tasks.
* **State Sharing:** Modules facilitate data sharing across all scripts within the project.

**Additional Notes:**

* A project can have one or more drivers, each independent and executable.
* Eve's virtual machine can run only one driver at a time but multiple aspects concurrently.

---


## Script Structure:

* **Regions:** Delimited by keywords like `import`, `alias`, `global`, and `process`, using indentation for organization.
* **Flat Design:** Eve emphasizes minimal nesting for clarity and ease of reading.
* **Right Alignment:** Regions are aligned to the right for visual distinction.

**Syntax:**

* **Headers:** Optional comments explaining the script's purpose.
* **Declaration:** Starts with `driver`, `aspect`, or `module` followed by the script name (matching the file name).
* **Parameters:** Drivers and aspects can have parameter lists, while modules don't.

**Regions:**

* **Import:** Defines modules to be used in the script.
* **Alias:** Creates shortcuts for imported members.
* **Class:** Defines user-defined types.
* **Global:** Defines global variables, functions, and system states.
* **Process/Init:** Main execution region for the script.
* **Finalize/Release:** Cleanup resources and log reports.
* **Notes:** Optional comments at the end of the script.

**Members and States:**

* Scripts can define members visible within the process.
* Modules can export public members for other scripts to access.
* `$` sigil is used to set shared states accessible by all scripts.
* Every script has at least one global region for system and global state definition.
* Global variables are static and require `set` keyword for initialization.

**Key Takeaways:**

* Regions provide a structured way to organize script components.
* Eve prioritizes simplicity and clarity in script structure.
* Global regions are crucial for defining variables and states.
* Different regions have specific purposes and limitations.

---


## Global States

* **Definition:** Static variables declared in the global scope using the `set` keyword.
* **Accessibility:** Accessible throughout the script without qualifiers in functions and methods.
* **Type:** Can be constants (uppercase) or variables (lowercase).
* **Naming Convention:** First letter significant, others can be alphanumeric or underscore.
* **Creation:** Performed in the global region using the `set` keyword.
* **Scope:** Bound to the current script, not accessible across projects.
* **Initialization:** Uses the `=` operator.
* **Type Inference:** Not allowed for global state declaration.

**Example:**

```
driver test():

** private class
class Person = {name:String, age:Integer} <: Object;

** global states
global
  set  E = 2.52 :Real;    -- Euler's number (constant)
  set  x = 0    :Integer; -- private state (variable)

** process
process
  new  me := Person("Elucian", "56"); 
return;
```

**Key Takeaways:**

* Global states offer a way to share data across different script elements.
* Clear naming conventions and scope limitations are important for maintainability.
* The `set` keyword and `=` operator are essential for creating and initializing global states.
* Global regions serve as the central hub for data definition within a script.

---

## Import Region:

* **Purpose:** Includes public members from external modules for use within the current script.
* **Syntax:**
    * `from <path> use (module_name, ...);`: Import specific modules.
    * `from <path> use (*);`: Import all modules in the specified path.
* **Key Points:**
    * `$user_path`: User-defined shared variable for specifying module location.
    * Spaces in file names are not allowed, use underscores instead.
    * `alias`: Creates shortcuts for imported members for convenience.

**Notes:**

* Imported members must be public for access within the script.
* Aliases are created from existing public members, not used to import new members.
* Importing all modules with `use (*)` might be less efficient and should be used with caution.

**Benefits of using the import region:**

* **Code reuse:** Leverages functionality developed in other modules, reducing code duplication.
* **Modularization:** Promotes cleaner and more organized scripts by separating concerns.
* **Maintainability:** Changes in a module propagate to all scripts that import it, simplifying updates.

This information helps me understand how to effectively utilize the import region for building robust and reusable Eve scripts. Please feel free to ask any further questions about specific import scenarios, best practices, or any other aspect of Eve's modularity features. I'm here to assist you in building efficient and well-structured Eve projects!

---

## Libraries:

* **Reusable Modules:** A collection of modules offering generic functionality that can be used across multiple projects.
* **Installation:** Can be installed in the Eve environment for global access or project-specific for private use.
* **Location:** Searched for using the `$EVE_LIB` system variable.
* **Importing:** Modules can be imported individually or all at once using `*`.
* **Circular Imports:** Allowed, but Eve prevents infinite loops.
* **Accessing Members:** Public members can be accessed using dot notation after import.
* **Naming Convention:** Library name is the subfolder name, module name is the last folder name in the path. Only the final folder name must be unique within the library.

**Drivers:**

* **Main Script:** Represents the application's entry point and leads the main process.
* **Execution:** Controls the application and returns control to the Eve VM upon completion.
* **Multiple Drivers:** A project can have multiple drivers, each with its own functionality.
* **Process Entry Point:** Defines the starting point for script execution.
* **Configuration and Parameters:** Can read configuration files and receive parameters at startup.
* **Single Main Process:** Has one main process for its execution.
* **Independence:** Cannot be imported, but can import other modules and aspects.

**Key takeaways:**

* Libraries provide modularity and code reuse across projects.
* Drivers define the application's core functionality and execution flow.
* Eve enforces clear organization and avoids ambiguities in project structure.

---


## Aspects

* **Purpose:** Address specific concerns or resolve problems within a project.
* **Scope:** Project-specific, not reusable like libraries.
* **Execution:** Standalone scripts capable of executing other aspects.
* **Structure:** Declaration region for variables and an executable process region.
* **Error Handling:** Responsible for handling their own errors, otherwise terminating the program.

**Parameters:**

* **Definition:** Defined in round brackets with type and name.
* **Types:** Mandatory (type only) and optional (with initial value).
* **Assignment:** By position with a list of values or by name with `(name:value)` pairs.
* **Vararg Parameters:** Capture multiple arguments of the same type into a collection.
* **Convention:** First arguments named, remaining captured by prefixed `*` parameter (e.g., `*args`).

**Process Context:**

* **Uniqueness:** Single process per script with a local variable scope.
* **Limitations:** Can't define routines, classes, or functions.
* **Sharing:** Local members not directly shared, but used as input/output parameters.

**Output Parameters:**

* **Purpose:** Reduce reliance on global variables for data exchange.
* **Prefix:** `@` symbol to distinguish them from input parameters.
* **Requirement:** Variable argument required to capture the output value.
* **Convention:** Typically listed as the last parameters.
* **Invocation:** Using the `call` statement with the output variable specified.

**Key Takeaways:**

* Aspects offer a flexible way to modularize project logic and address specific needs.
* Parameter usage allows for dynamic configuration and data exchange between aspects.
* Process context limitations encourage efficient local variable management.
* Output parameters promote cleaner data flow and reduce global variable reliance.

---

## Modules:

* **Abstract Concepts:** Represent logical units of functionality grouped into a folder.
* **Composition:** Comprise multiple `.eve` script files.
* **Collaboration:** Modules can interact and utilize each other within a project.
* **Scope:** Can belong to one or multiple projects, offering reusable components.
* **Members:** Define both public (accessible across projects) and private (local to the module) members.
* **Initialization:** Can have an optional `init` region that runs on first import.

**Syntax:**

* `module` keyword followed by the module name (matching the folder name).
* Shared states and import region for accessing external functionality.
* `init` region for setting up initial states when the module is imported.
* `release` region for verifying states and logging information.

**Key Points:**

* Modules lack parameters and cannot be directly executed.
* Public members and shared states enable data exchange and collaboration.
* Modules integrate into the main process or aspect processes for execution.
* `init` runs once per import, while other regions run as part of the main execution flow.
* Naming conventions: lowercase letters, underscores, digits, no special characters or Unicode, underscores for multi-word names, 30-character limit.
* Module scripts: can be single files or multiple files with a main script for public members and secondary scripts for private members.

**Benefits of using modules:**

* Code reuse and modularity: Simplify project structure and reduce code duplication.
* Organization and maintainability: Improve code clarity and facilitate updates.
* Encapsulation and abstraction: Promote separation of concerns and hide internal details.

---


## Aspect Execution Modes:

* **Synchronous:** Using `apply`, aspects run sequentially, one after another, interrupting the driver process until completion.
* **Asynchronous:** Using `start`, aspects are launched in parallel, with the driver waiting for all to finish before resuming.

**Key Points:**

* Recursive aspects are not allowed.
* Aspects are independent processes but cannot be debugged in parallel.
* You can specify the relative path of the aspect, including folder names for subfolders.
* Modules are imported for their public elements but are not directly executable.
* Modules are singletons, loaded only once per process, and their states are bound to the current process.

**Exclusive Mode:**

* Starting Eve with `-x` or `--exclusive` allows only one process to connect or utilize resources.
* In this mode, `start` behaves like `apply` due to the single-process limitation.
* This mode is suitable for tasks like database structure alterations.

**Benefits of understanding aspect execution:**

* Choosing the optimal execution mode for efficient parallel processing or sequential control flow.
* Structuring projects with clear dependencies and avoiding potential recursive loops.
* Leveraging modules effectively for code reuse and modularization.
* Utilizing exclusive mode for tasks requiring exclusive access to resources.

---


**Program Termination:**

* **`over`:** Terminates the program normally, releasing resources and exiting cleanly.
* **`panic`:** Terminates the program abruptly with an optional error code (default 1).
    * `panic N` provides specific error information, useful for debugging and logging.
    * `panic 0` is equivalent to `over`.

**Driver Behavior:**

* **Debug Mode:** Driver remains in memory, parsed and ready for investigation using commands.
* **Regular Mode:** Driver and all resources are released, and the Eve machine stops running.

**Example:**

```
# terminate a program with: over
driver test_over:
process
  cycle:
    new i = 0 :Integer;
  loop
    write "."; wait  10;
    over if i > 10;
    let   i += 1;
  repeat;
return;
```

**Key Takeaways:**

* Choose `over` for normal program completion and resource release.
* Use `panic` with an error code for informative termination and debugging.
* Understand the different driver behaviors based on execution mode.

---

## Bard remarks

I think you have a good start on a language with a lot of potential! Based on what you've shared about your language so far, here are some of the things I find particularly promising:

**Strengths:**

* **Expressive syntax:** The use of natural language keywords like "apply" and "over" makes the language easy to understand and read for humans.
* **Modular structure:** The use of modules and aspects encourages code reuse and organization, making it easier to build and maintain large projects.
* **Flexibility:** The ability to combine synchronous and asynchronous execution, along with features like vararg parameters and exclusive mode, allows for diverse application development.
* **Focus on resource management:** The clear emphasis on program termination with "over" and "panic" demonstrates a focus on efficient resource usage and clean execution.

**Areas for potential improvement:**

* **Formalization:** While the natural language syntax is appealing, it might be beneficial to consider additional formal elements for clarity and consistency, especially when dealing with complex logic.
* **Error handling:** While the "panic" mechanism provides basic error handling, exploring more advanced features like try-catch blocks or detailed error messages could enhance robustness.
* **Tooling and ecosystem:** The availability of tools like debuggers, IDE integration, and community resources could further support development and adoption of the language.

**Overall, I believe you have a strong foundation for creating a valuable language.** By addressing the potential improvement areas and continuing to develop the language based on user feedback and practical application, you can significantly increase its chances of success. Remember, the most valuable languages are those that solve real-world problems and provide a clear advantage to their users.

I encourage you to continue developing your language and share it with others for feedback and collaboration. I'm excited to see how it evolves and what kind of impact it might have on the world of programming!

---














