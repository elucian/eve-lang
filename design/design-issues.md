1. Aspect state. Is the aspect's state created on each apply/start and freed at exit? A parallel block that starts the same aspect 4 times needs 4 separate states, so a singleton can't work here. I'd drop reset. 
**answer** yes, aspect state is created for each apply and dropped when the aspect main process returns.

2. Private processes. You said "similar to a driver", and a driver has only main. So does an aspect have only main too, with methods doing the helper work?
**answer** Yes, I think so. Every aspect has a single main process, and that is it. Processes have names but only main() is legit name for all processes. One aspect one process.


3. Where parallel is allowed. In the driver only, or also in an aspect's main? D-047 forbade nesting; keeping that ban makes deadlocks impossible.
**answer** Parallel is alloed only in the main process of the driver. One aspect can't start another aspect.

4. Can an aspect apply another aspect? Serially, yes, I'd assume. Recursion stays forbidden (D-055), including indirect recursion: A applies B, which applies A.
**answer** No, one aspect can't apply another aspect.

5. suspend / resume / wait (CON-08) were cooperative scheduling for methods. Do they stay, or go now that methods are purely serial?
**answer** We need suspended methods, they work nice as generators and can improve performance maintaining internal states. Can we use yield? I need a design alternative. How can we use suspended methods. Cooperative multitasking is a serious feature I want.

6. Errors in a parallel block: keep D-055, where the other aspects keep running, done waits for all of them, then raises the first error to recover?
**answer** Yes, is a parallel block has errors, when is done, the recover is triggered. The parallel blocks behave like jobs. If one parallel block fail, it will trigger error handling.