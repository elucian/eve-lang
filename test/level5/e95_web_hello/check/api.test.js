// Client of the test e95_test4: Node.js 18 or later, no package. The runner starts the machine with `eve ux start`.
// It calls JSON-RPC directly in POST /rpc: the machine API (vm.ping, vm.stat, vm.run, vm.stop) and the first names
// of D-162 (ping, status), a method that does not exist (-32601), and the rules of the web door (404, 405).
// Every check prints "ok <what>"; the first one that fails prints "FAIL <what>" and ends the script with 1.
const http = require("node:http");
const { spawnSync } = require("node:child_process");
const eve = process.env.EVE || "eve";
const port = 8095;

function check(ok, what) {
  if (!ok) {
    console.error("FAIL " + what);
    process.exit(1);
  }
  console.log("ok " + what);
}

// a raw request, so a path such as /../eve.cfg reaches the machine as it is written (fetch would clean it)
function request(method, path, body) {
  return new Promise((resolve) => {
    // the length is given, so the body is not sent in chunks (the web door reads Content-Length)
    const headers = { "content-type": "application/json", "content-length": Buffer.byteLength(body || "") };
    const req = http.request({ host: "localhost", port, method, path, headers }, (res) => {
      let data = "";
      res.on("data", (c) => (data += c));
      res.on("end", () => resolve({ status: res.statusCode, body: data }));
    });
    req.on("error", () => resolve({ status: 0, body: "" }));
    if (body) req.write(body);
    req.end();
  });
}

// a POST whose body is sent in chunks (Transfer-Encoding: chunked): no Content-Length, two writes
function postChunked(path, parts) {
  return new Promise((resolve) => {
    const req = http.request({ host: "localhost", port, method: "POST", path, headers: { "content-type": "application/json" } }, (res) => {
      let data = "";
      res.on("data", (c) => (data += c));
      res.on("end", () => resolve({ status: res.statusCode, body: data }));
    });
    req.on("error", () => resolve({ status: 0, body: "" }));
    for (const p of parts) req.write(p);
    req.end();
  });
}

let nextId = 1;
async function rpc(method, params) {
  const r = await request("POST", "/rpc", JSON.stringify({ jsonrpc: "2.0", id: nextId++, method, params }));
  return r.status === 200 ? JSON.parse(r.body) : { status: r.status };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  let up = false;
  for (let i = 0; i < 50 && !up; i++) {
    up = (await request("GET", "/")).status === 200;
    if (!up) await sleep(200);
  }
  check(up, "the machine answers");

  check((await rpc("vm.ping")).result === "pong", "vm.ping answers pong");
  check((await rpc("ping")).result === "pong", "ping, the first name, still answers");
  const st = (await rpc("vm.stat")).result;
  check(st && st.http === true && Array.isArray(st.parts) && st.parts.includes("ux"), "vm.stat lists the active parts");
  const old = (await rpc("status")).result;
  check(old && old.http === true && old.parts === undefined, "status keeps its first shape");
  const nope = await rpc("vm.nope");
  check(nope.error && nope.error.code === -32601, "an unknown method is -32601");
  const run = (await rpc("vm.run", { name: "two.eve", source: "primary aspect two is\n  process main is\n    print 1 + 1;\n  return;\nend two;\n", args: [] })).result;
  check(run && run.status === 0 && run.output.trim() === "2", "vm.run runs a script");

  const ch = await postChunked("/rpc", ['{"jsonrpc":"2.0","id":99,', '"method":"vm.ping"}']);
  check(ch.status === 200 && JSON.parse(ch.body).result === "pong", "a body sent in chunks is read");
  check((await request("GET", "/../eve.cfg")).status === 404, "a path that leaves the web folder is 404");
  check((await request("PUT", "/index.html", "x")).status === 405, "another method is 405");
  check((await request("POST", "/other", "{}")).status === 404, "POST to a path other than /rpc is 404");

  const stop = spawnSync(eve, ["ux", "stop"], { encoding: "utf8", timeout: 20000 });
  check(stop.status === 0, "eve ux stop ends the machine with 0");
  console.log("api: all checks passed");
}

main();
