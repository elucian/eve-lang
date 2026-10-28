// Client of the test f17_http_door: Node.js 18 or later, no package. The runner starts the machine with `eve ux start`.
// It posts raw JSON-RPC requests to /rpc with the headers a browser page would send, and checks what the HTTP door refuses.
// Every check prints "ok <what>"; the first one that fails prints "FAIL <what>" and ends the script with 1.
const http = require("node:http");
const { spawnSync } = require("node:child_process");
const eve = process.env.EVE || "eve";
const port = 8096;

function check(ok, what) {
  if (!ok) {
    console.error("FAIL " + what);
    process.exit(1);
  }
  console.log("ok " + what);
}

// a raw POST /rpc with the headers given (Host and Origin included)
function post(message, extra) {
  const body = JSON.stringify(message);
  return new Promise((resolve) => {
    const headers = Object.assign({ "content-type": "application/json", "content-length": Buffer.byteLength(body) }, extra || {});
    const req = http.request({ host: "127.0.0.1", port, method: "POST", path: "/rpc", headers }, (res) => {
      let data = "";
      res.on("data", (c) => (data += c));
      res.on("end", () => resolve({ status: res.statusCode, body: data }));
    });
    req.on("error", () => resolve({ status: 0, body: "" }));
    req.write(body);
    req.end();
  });
}

let nextId = 1;
async function rpc(method, params, extra) {
  const r = await post({ jsonrpc: "2.0", id: nextId++, method, params }, extra);
  return r.status === 200 ? JSON.parse(r.body) : { status: r.status };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const script = (text) => "primary aspect t is\n  process main is\n" + text + "  return;\nend t;\n";

async function main() {
  let up = false;
  for (let i = 0; i < 50 && !up; i++) {
    up = (await rpc("vm.ping")).result === "pong";
    if (!up) await sleep(200);
  }
  check(up, "the machine answers");

  check((await rpc("vm.ping", null, { host: "localhost:" + port })).result === "pong", "a loopback Host is served");
  check((await rpc("vm.ping", null, { host: "evil.example:" + port })).status === 403, "a foreign Host is 403");
  check((await rpc("vm.ping", null, { origin: "http://evil.example" })).status === 403, "a foreign Origin is 403");
  check((await rpc("vm.ping", null, { host: "localhost:" + port, origin: "http://localhost:" + port })).result === "pong", "the same Origin is served");

  const ev = await rpc("vm.eval", { session: "s1", line: "print 1" });
  check(ev.error && ev.error.code === -32001, "vm.eval is refused on the HTTP door");
  const sh = await rpc("vm.shell", { session: "s1", command: "echo hi" });
  check(sh.error && sh.error.code === -32001, "vm.shell is refused on the HTTP door");
  const op = await rpc("vm.open", { cwd: "." });
  check(op.error && op.error.code === -32001, "vm.open is refused on the HTTP door");
  const byPath = await rpc("vm.run", { path: "check/door.test.js" });
  check(byPath.error && byPath.error.code === -32001, "vm.run of a path of the machine is refused");

  const two = (await rpc("vm.run", { name: "two.eve", source: script("    print 1 + 1;\n"), args: [] })).result;
  check(two && two.status === 0 && two.output.trim() === "2", "vm.run of a script text still runs");
  const cmd = process.platform === "win32" ? "cmd" : "echo";
  const args = process.platform === "win32" ? '("/c", "echo", "pwned")' : '("pwned")';
  const bad = (await rpc("vm.run", { name: "bad.eve", source: script('    new r := os.run!("' + cmd + '", ' + args + ', ".");\n    print "ran";\n'), args: [] })).result;
  check(bad && bad.status !== 0 && !bad.output.includes("ran") && bad.errors.includes("os.run! is not available"), "os.run! fails in a script sent over the HTTP door");

  check((await rpc("vm.ping")).result === "pong", "the machine still answers after the refusals");
  const stop = spawnSync(eve, ["ux", "stop"], { encoding: "utf8", timeout: 20000 });
  check(stop.status === 0, "eve ux stop ends the machine with 0");
  console.log("door: all checks passed");
}

main();
