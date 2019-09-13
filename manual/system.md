## System Library

This library is part of the language core. It is part of EVE runtime environment. Unlike standard library the system library is automatically loaded in EVE runtime environment. You do not need to import its modules.

## Standard streams

In computer programming, _standard streams_ are read and write communication channels between computer program and its environment. The three I/O connections are called standard read (stdin), standard write (stdout) and standard error (stderr). These channels are connected to the program when program starts. 

When a program is executed via an interactive shell, the streams are typically connected 
to the text terminal on which the shell is running, but can be changed with redirection, using a pipeline.


## Standard read 

Standard read is stream data (often text) going into a program. The program request data transfers by use of the read operation. Not all programs require stream read. 
A program may take command-line arguments, but perform their operations without any stream data read.

Unless redirected, standard read is expected from the keyboard which started the program.

**read statement**
Developer can create a program that ask for user to enter values from keyboard.  
The read statement can output a text then wait until user type the text and press enter.

Function read declaration
```
read (String: prompt) => String;
```

**Example:**
```
routine main():
  String: v = ""; //empty string
process  
  read  (v, "input v:");
  write ("you entered:" & v);
return;
```

## Standard write 

This is the stream where a program writes its write data. The program request data transfer with the write operation. Not all programs generate write. In this  the program is silent. 

Unless redirected, standard write is the text terminal which initiated the program.

** Function _write()_ **
This function send a string to standard write as it is. 
This will help developers to make dynamic write. 
Is user responsibility to make a line break using an escape \n or \r inside the string parameter.

```
routine write(String * args, Logic:eol=True, String:sep=" "):
 ...
return;
```

**parameters:**

* eol:False will cause "write" to not sent new line to console
* sep:","  will cause "write" to separate arguments by comma
* wrp: > n will cause end of line after n characters 

write sting can contain an escaped end of line character.
```
\LF   is LF 
\CRLF is CR+LF
```

### Usability
write function support only strings. It can not print anything else. 
Therefore developer must make a conversion to a string before sending the value to write.


## Standard error

Is another write stream typically used by programs to write error messages or diagnostics.  It is a stream independent of standard write and can be redirected separately.

**Usage**

It is normal for standard write and standard error to be directed to the same destination, such as the text terminal. Messages appear in the same order as the program writes them, unless buffering is involved. 

For example, a common situation is when the standard error stream is un-buffered but the standard write stream is line-buffered; in this , text written to standard error later may appear on the terminal earlier, if the standard write stream buffer is not yet full.

**Redirect**

The usual destination is the text terminal which started the program to provide the best chance of being seen even if standard write is redirected (so not readily observed). For example, write of a program in a pipeline is redirected to read of the next program, but errors from each program still go directly to the text terminal.
