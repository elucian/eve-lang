# ΞVΞ Concepts

These concepts are common to any computer language in Algol family. 

**bookmarks**

* [punctuation](#punctuation)
* [keywords](#keywords)
* [operators](#operators)
* [data types](#data-types)
* [variables](#variables)
* [identifiers](#identifier-names)
* [expressions](#expressions)

## Punctuation

* EVE is using infix expressions like other popular languages;
* Multiple expressions can be separated with comma and enclosed in parenthesis;
* Each statement start with a lowercase keyword and is ending with semicolon ";" 
* Native data types, variables, labels and methods use lowercase letters and numbers;
* Composite data types and classes start with capital letters;
* Constants usually start also with capital letters or Unicode symbols;
* System variables use prefix "$". User can define new system variables;

**Keywords**

Keywords are English words familiar to programmers used in logical semantic structures easy to grasp. We prefer English since the computer was invented in England so they deserve this honor.

* [keywords](keywords.md) 

**Operators:**

EVE has ASCII and Unicode operators. Unicode operators require one space before and one after. ASCII operators do not require space separator. Unicode and ASCII operators usually are independent used and not combined.

* [operators](operators.md) 

## Data types
A type is a data representation also considered as a "set" of data. It can be a supe-set/subset from which a variable can have values. For example Integer, Real, Complex, Rational or String are pre-defined data types. 

**Syntax:**
```
define
  <Name> <: <type_descriptor>;
define;  
```

**Notes:** 

* Developers can define new data types in each module. 
* Members defined in define region are public or private.
* Public member names start with "." prefix.

## Variables
A variable is represented by an identifier, and is associated to a type. Variable can be changed during the execution of the program using modifier operators { :=, +=, *:=, /:= ...}. 

**patterns:**
```
global
  var <name> ∈ <Type>;                -- use default value
  var <name> := <value> ∈ <Type>;     -- specific value and type
  var <name1>, <name2> ...:= <value>; -- multiple variables in one assignment
  
```

**examples**
```
global  
  var a ∈ Integer; 
  var b := 1 ∈ Integer; 
  var d := 2.5 ∈ Real;      
  var x,y,z := 0.0 ∈ Real;  
```

**default value**
When type is specified, and the initializer ":=" is missing the variable takes default "zero" value. This value is different for each data type. For example zero value for Real numbers is 0.0 and for strings is "". Notice the "zero" value is not Null. 

**system variables**
We define system variables using "$" name prefix. _Environment Variables_ from OS are created automatically along with other "implicit" variables required by EVE semantics. 

## Modify Value 
The assign operator ":=" is used to execute an expression and assign the result to a variable. 
The previous value of the variable is discarded if there is no other reference to it.

**Syntax:**
```
  <variable_name> := <expression>; 
```

## Identifier names
The name of identifiers in EVE can have a length of 64 characters. A name starts with lowercase letters (a..z) or capital letters (A..Z) followed by one or more characters or numbers. No special characters or spaces are permitted in the name except underscore ("_"). A variable can contain underscore but can not start or with underscore. 

The underscore is equivalent to space. So the identifiers that have space in a JSON or in a database can be mapped to internal variables that use underscore instead of a space. Variable names can not start with numbers. 

**Subscript**
It is possible to use subscript for variables:
```
A ₀ ₁ ₂ ₃ ₄ ₅ ₆ ₇ ₈ ₉ 
```
Alpha subscript is supported:
```
X ₐ ₑ ₕ ᵢ ⱼ ₖ ₗ ₘ ₙ ₒ ₚ ᵣ ₛ ₜ ᵤ ᵥ ₓ
```

**Superscript**
Alternative notation for "power" function:

```
x² ≡ x^2

A ⁺ ⁻ · ⁰ ¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹ 
A ⁱ ʲ ᵏ ⁿ ᵒ ᵖ ʳ ˢ ˣ ʸ ᶻ 
A ᵃ ᵇ ᶜ ᵈ ᵉ ᶠ ᵍ ʰ ⁱ ʲ ᵏ ᶩ ᵐ ⁿ ᵒ ᵖ ʳ ˢ ᵗ ᵘ ᵛ ʷ ˣ ʸ ᶻ 
A ᴬ ᴮ ᴰ ᴱ ᴳ ᴴ ᴵ ᴶ ᴷ ᴸ ᴹ ᴺ ᴼ ᴾ ᴿ ᵀ ᵁ ᵂ 
```
**Note:** Limited superscript expressions:
```
x⁻¹·⁵ 
xⁿ⁻¹
xⁿ⁺¹
```

**Greek Symbols**
We have eliminated the ones looking like Latin symbols.

```
Γ Δ Ξ Π Σ Φ Ψ Ω 
α β ε δ ζ η θ λ μ ν ξ π ρ σ ς τ υ φ
```

**Cyrillic Symbols**
We have eliminated the ones looking like Latin symbols or numbers.
```
Б Г Д Ж И Л Ф Ц Ч Ш Щ Э Я 
б г д ж з и ф ц ч ш щ   я 
```

**These are valid identifiers**  
```
 x, y, z
 a₁,a₂,aₙ  
 thisIsOK
 this_is_ok  
```
**These are invalid identifiers**  
```
 1`st
 \_this  
 this\_  
 \_this\_  
```

**Naming variables**
Variables usually have a meaning or a purpose therefore variable must have a proper name.  
Variables can not have are the language reserved keywords. Therefore we advise for variables to use a prefix.

* "v_" is a good prefix for local  variables;
* "p_" is a good prefix for input  parameters;
* "o_" is a good prefix for output parameters;

## Expressions

Expressions are created using identifiers, operators, functions and constant literals. 

* can be combined to create more complex expressions;
* have type that is calculated using type inference;
* can be assigned to variables using ":=" or "<+" operators;
* can be printed to console using "print" or "write" methods;
* can use () to establish order of operations;

**Examples**
```
-- simple expressions in put statement
-- no need for parentheses for a single value
print 10; -- print 10
print "this is a test";

--complex expressions can use ()  
print (10 + 10 + 15);     -- math
print (10 > 5) | (2 < 3); -- logical

--multiple expressions in a line
print (1,',',2,',',3); --expect 1,2,3
print (10, 11, 12);    --expected 101112   

--avoid new line after 2
write (1,2);
write (3,4);  
--> expect 1234
```

**Notes:** 
* print statement can receive multiple parameters
* print statement add new line by default
* to avoid new line use coma separated parameters
* to avoid new line you can use "write" statement instead of "print"
* multiple expressions or arguments are separated by comma
* you can omit the parentheses when you call a aspect with one single parameter

**Read next:** [Structure.md](structure.md)