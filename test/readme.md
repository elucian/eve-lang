## Acceptance Test

EVE test folder contains examples of EVE code used for testing the interpreter, or the compiler. I have organized the tes on level1,leve2, level3 because EVE use to be called LEVEL and now is just EVE. So I have used the name to test some features.

## Level 1

Single script tests each test is a driver. We verify basic syntax elements and make examples as dump as possible, We name each file using convention pattern: "a01-feature.eve", each test is a "basic case". 

You can run every script individually by hand using the interpreter command line. For this level we do not have test automation scripts. These tests are developer tests. After you pass level 1, you can start testing Level2. 

## Level 2

This level is more advanced. It contains automation drivers. Each driver is a series of related tests. Driver has convention: "b01-feature.eve" and it can have associate a folder that contains aspects of the test. You can run each driver separate. Aspects are using same convention as Level 1.


## Level 3

This level contains advanced features. Working with files, databases and internet. At this level you can work with libraries. There is a long time until we have Level 3 tests in place. I hope your compiler will reach this level and is approved. This level use convention "c01-feature.eve".

# Approval

We do not yet have an approval process. But the idea is, community will test your compiler and will decide if the compiler is high quality and deserve to be approved. We publish news and promote approved compilers on our homepage and offer monetary rewards for best compilers.


