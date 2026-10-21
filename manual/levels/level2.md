<!-- Generated from the specification, the tests and the benchmarks. Do not edit this page. -->

# Level 2: A project: subprograms and aspects

A script becomes a project: functions, procedures, lambdas and closures, and aspects, the units of work that `apply` calls with copy-in parameters, with errors recovered across `apply` and a log per call. Configuration files belong here. 

| Code | Feature | Stage |
|---|---|---|
| [`F-LNG-09`](#f-lng-09-functions-and-methods) | Functions and methods | validated |
| [`F-STR-02`](#f-str-02-aspects-serial) | Aspects (serial) | validated |
| [`F-STR-06`](#f-str-06-configuration-files) | Configuration files | validated |

## F-LNG-09 Functions and methods

Stage: **validated**.

Pure functions, `!` functions, procedures, `@` parameters, defaults, varargs, named arguments, lambdas, closures, recursion. A lambda is not called where it is written. Conformity level 2.

An example that runs, and what it prints:

```eve
# a lambda is an anonymous function: held by a name, passed as an argument, held by a function type
primary aspect b18_lambda is
  class BinEx = (p1, p2:Integer):Integer <: Function;
  procedure show(f: BinEx) is
    print f(3, 4);
  return;
  procedure each(items: Integer, action: Function) is
    for x in items do
      print action(x);
    done;
  return;
  process main is
    new double:= (x) => (x * 2);
    print double(5);
    show((a, b) => (a + b));
    each((1, 2, 3), (x) => (x + 100));
  return;
end b18_lambda;
```

```text
10
7
101
102
103
```

## F-STR-02 Aspects (serial)

Stage: **validated**.

`apply`, state per call, `@` outputs, named and spread arguments, errors and `over`/`panic` across `apply`, `exclusive` by default, `concurrent` kind.

An example that runs, and what it prints:

```eve
# a private process is applied by its bare name, in the aspect that declares it
primary aspect b50_private_process is
  process show(label: String, n: Integer) is
    print "{label}: {n}";
  return;

  process main is
    apply show("first", 1);
    apply show("second", 2);
  return;
end b50_private_process;
```

```text
first: 1
second: 2
```

## F-STR-06 Configuration files

Stage: **validated**.

`.cfg` with `$key = value`, loaded with `-s`.

*Done:* `-e file.cfg`, `--setup file.cfg` and the REPL command `setup` load the file (`$key = value` lines, `#` comments); `-s` is accepted by the command line.
