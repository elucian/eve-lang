// Client of the test e95_test5: Node.js 18 or later, no package. It starts the machine itself, `eve --stdio`, the way an
// IDE does (evetx), and speaks JSON-RPC on its standard input and output, one message per line: the lasting door, the
// sessions (vm.open, vm.eval, vm.close), the streamed output (vm.output notifications), vm.shell, vm.run by path,
// vm.cancel, the order of the answers, and vm.stop. Every check prints "ok <what>"; the first one that fails prints
// "FAIL <what>" and ends the script with 1.
const { spawn } = require("node:child_process");
const eve = process.env.EVE || "eve";

function check(ok, what) {
  if (!ok) {
    console.error("FAIL " + what);
    process.exit(1);
  }
  console.log("ok " + what);
}

const machine = spawn(eve, ["--stdio"], { stdio: ["pipe", "pipe", "pipe"] });
const waiting = new Map(); // id -> resolve
const outputs = new Map(); // id -> streamed text
const order = []; // ids in the order their answers came
let rest = "";
machine.stdout.on("data", (chunk) => {
  rest += chunk.toString("utf8");
  let nl;
  while ((nl = rest.indexOf("\n")) >= 0) {
    const line = rest.slice(0, nl).trim();
    rest = rest.slice(nl + 1);
    if (!line) continue;
    const msg = JSON.parse(line);
    if (msg.method === "vm.output") {
      outputs.set(msg.params.id, (outputs.get(msg.params.id) || "") + msg.params.text);
    } else if (waiting.has(msg.id)) {
      order.push(msg.id);
      waiting.get(msg.id)(msg);
      waiting.delete(msg.id);
    }
  }
});
let ended = null;
machine.on("exit", (code) => (ended = code));

let nextId = 1;
function send(method, params) {
  const id = nextId++;
  const p = new Promise((resolve) => waiting.set(id, resolve));
  machine.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  return { id, answer: p };
}
const call = async (method, params) => (await send(method, params).answer);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const timer = setTimeout(() => check(false, "the machine answers within 30 s"), 30000);
  check((await call("vm.ping")).result === "pong", "vm.ping answers pong on the stdio door");
  check((await call("vm.ping")).result === "pong", "a second message on the same channel is answered");

  const stat = (await call("vm.stat")).result;
  check(stat.door === "stdio" && stat.ipc === false && stat.http === false, "vm.stat says the door is stdio");

  const opened = (await call("vm.open", { cwd: "check" })).result;
  check(Number.isInteger(opened.session) && opened.cwd === "check", "vm.open makes a session in the folder check");
  const sid = opened.session;

  const loaded = (await call("vm.eval", { session: sid, line: "load hello.eve" })).result;
  check(loaded.status === 0 && loaded.output.includes("hello: loaded"), "vm.eval loads a file from the folder of the session");

  const ran = send("vm.eval", { session: sid, line: "run", stream: true });
  const ranAnswer = (await ran.answer).result;
  check(ranAnswer.status === 0 && ranAnswer.output === "", "a streamed eval answers with its status");
  check((outputs.get(ran.id) || "").includes("Hello from the machine"), "the output of the run came as vm.output notifications");

  const bang = (await call("vm.eval", { session: sid, line: "!echo eve-shell" })).result;
  check(bang.status === 0 && bang.output.includes("eve-shell"), "!<command> in a session runs the system shell and stays in eve");

  const shell = send("vm.shell", { command: "echo hi from the shell", stream: true });
  check((await shell.answer).result.status === 0 && (outputs.get(shell.id) || "").includes("hi from the shell"), "vm.shell streams the output of a command");

  const byPath = send("vm.run", { path: "check/hello.eve", stream: true });
  const byPathAnswer = (await byPath.answer).result;
  check(byPathAnswer.status === 0 && (outputs.get(byPath.id) || "").includes("Hello from the machine"), "vm.run runs a file of the machine by its path");

  const missing = (await call("vm.run", { path: "check/no-such.eve" })).result;
  check(missing.status === 66, "vm.run of a missing file answers 66");

  const unknown = (await call("vm.eval", { session: sid, line: "frob" })).result;
  check(unknown.status === 64 && unknown.output.includes("unknown command: frob"), "an unknown word in a session is 64");

  // three evals sent at once are answered in the order they were sent
  order.length = 0;
  const a = send("vm.eval", { session: sid, line: "status" });
  const b = send("vm.eval", { session: sid, line: "!echo second" });
  const c = send("vm.eval", { session: sid, line: "report" });
  await Promise.all([a.answer, b.answer, c.answer]);
  check(order.join(",") === [a.id, b.id, c.id].join(","), "the evals of a channel run in the order they came");

  check((await call("vm.cancel")).result === "cancelled", "vm.cancel answers");
  const plain = (await call("vm.eval", { line: "cd check", cwd: "." })).result;
  check(plain.status === 0 && plain.session !== sid && /^folder: .*[\\/]check\r?\n$/.test(plain.output), "an eval without a session uses the default session of the channel");
  check((await call("vm.stat")).result.sessions === 2, "vm.stat counts the open sessions");
  check((await call("vm.close", { session: sid })).result === "closed", "vm.close ends the session");
  check((await call("vm.eval", { session: sid, line: "status" })).error.code === -32602, "an eval in a closed session is -32602");
  check((await call("vm.frob")).error.code === -32601, "an unknown method is -32601");

  check((await call("vm.stop")).result === "stopping", "vm.stop answers stopping");
  for (let i = 0; i < 50 && ended === null; i++) await sleep(100);
  check(ended === 0, "the machine ends with 0 after vm.stop");

  // the end of the input ends a machine too (the IDE closed)
  const second = spawn(eve, ["--stdio"], { stdio: ["pipe", "ignore", "ignore"] });
  let secondEnded = null;
  second.on("exit", (code) => (secondEnded = code));
  second.stdin.end();
  for (let i = 0; i < 50 && secondEnded === null; i++) await sleep(100);
  check(secondEnded === 0, "the end of the input ends the machine with 0");
  // the run in the session wrote its reports where the prompt writes them (temp/output of the folder): not part of the test
  require("node:fs").rmSync("temp", { recursive: true, force: true });
  clearTimeout(timer);
  console.log("stdio: all checks passed");
}

main();
