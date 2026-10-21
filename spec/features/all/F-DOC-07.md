# F-DOC-07 Manual generator

`generator/evegen.py` builds the manual from the features of the specification, the tracking files of the tests and the benchmark history, writes an index of the specification (`spec/spec.json`) and checks that the spec, the tests and the manual stay apart: only the generator reads both the spec and the tests.
