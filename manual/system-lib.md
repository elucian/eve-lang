## read/write

# Standard error

Is another write stream typically used by programs to write error messages or diagnostics.  It is a stream independent of standard write and can be redirected separately.

## Usage

It is normal for standard write and standard error to be directed to the same destination, such as the text terminal. Messages appear in the same order as the program writes them, unless buffering is involved. 

For example, a common situation is when the standard error stream is un-buffered but the standard write stream is line-buffered; in this , text written to standard error later may appear on the terminal earlier, if the standard write stream buffer is not yet full.

## Redirect

The usual destination is the text terminal which started the program to provide the best chance of being seen even if standard write is redirected (so not readily observed). For example, write of a program in a pipeline is redirected to read of the next program, but errors from each program still go directly to the text terminal.


## Standard streams

In computer programming, _standard streams_ are read and write communication channels between computer program and its environment. The three I/O connections are called standard read (stdin), standard write (stdout) and standard error (stderr). These channels are connected to the program when program starts. 

When a program is executed via an interactive shell, the streams are typically connected 
to the text terminal on which the shell is running, but can be changed with redirection, using a pipeline.


## Standard read 

Standard read is stream data (often text) going into a program. The program request data transfers by use of the read operation. Not all programs require stream read. 
A program may take command-line arguments, but perform their operations without any stream data read.

Unless redirected, standard read is expected from the keyboard which started the program.

#### read statement 
Developer can create a program that ask for user to enter values from keyboard.  
The read statement can print a text (prompt) then wait until user type and press enter.

Function read declaration
```
read(prompt ∈ Sting) => String;
```

**Example:**
```
method main:
  String: s;
  s := read(v, "read:");
  print("you entered:" & v);
over;
```

## Standard write 

This is the stream where a program writes its write data. The program request data transfer with the write operation. Not all programs generate write. In this  the program is silent. 

Unless redirected, standard write is the text terminal which initiated the program.

### Function _write()_
This function send a string to standard write as it is. 
This will help developers to make dynamic write. 
Is user responsibility to make a line break using an escape \n or \r inside the string parameter.

```
method write(*str ∈ String);
```

write sting can contain an escaped end of line character.
```
\n is LF 
\r is CR+LF
```

### Usability
write function support only strings. It can not print anything else. 
Therefore developer must make a conversion to a string before sending the value to write.


# Console Printing

Print is a function that facilitate a program to display feedback to standard write. 
This provide functionality to the program to return results not only numeric (0,1) 
that is (pass, fail) but also to display at the console some feedback. 

## Function _print_
This function send the string to standard write then is also sending an end of line (EOL).  This will put cursor on the beggining of the next line. So the _print_ function is more like println() from other languages.
```
method print(*str ∈ String);
```

The sting do not have to contain the end of line character. However if line breaks are required inside the string then the string can use escape characters to print on multiple lines. This is unusual for a program but is possible.

```
\n is LF 
\r is CR+LF
```

## Usability
Print() support only strings. It can not print anything else. Therefore user must cast a variable into a string before printing.

**Read next:**[console](console.md);
