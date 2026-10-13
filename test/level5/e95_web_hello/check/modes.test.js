// Client of the tests e95_test1 to e95_test3: Node.js 18 or later, no package. Usage: node check/modes.test.js <mode>
//   ipc  : the machine was started with `eve --listen`          (IPC only)
//   http : the machine was started with `eve --serve`           (HTTP only)
//   both : the machine was started with `eve --listen --serve`
// Every check prints "ok <what>"; the first one that fails prints "FAIL <what>" and ends the script with 1.
// The runner gives the path of the VM in the variable EVE. The client of the CLI is `eve` itself.
const { spawnSync } = require("node:child_process");
const eve = process.env.EVE || "eve";
const mode = process.argv[2];
const http = "http://localhost:8095";
const hasIpc = mode === "ipc" || mode === "both";
const hasHttp = mode === "http" || mode === "both";

function check(ok, what) {
  if (!ok) {
    console.error("FAIL " + what);
    process.exit(1);
  }
  console.log("ok " + what);
}

function run(args) {
  const r = spawnSync(eve, args, { encoding: "utf8", timeout: 20000 });
  return { code: r.status, out: r.stdout || "", err: r.stderr || "", all: (r.stdout || "") + (r.stderr || "") };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// the machine is started by the runner at the same time: wait until the channel answers (10 seconds at most)
async function waitFor(test) {
  for (let i = 0; i < 50; i++) {
    if (await test()) return true;
    await sleep(200);
  }
  return false;
}

async function httpUp() {
  try {
    await fetch(http + "/");
    return true;
  } catch (e) {
    return false;
  }
}

function runs() {
  const m = /runs: (\d+)/.exec(run(["--serve", "status"]).out);
  return m ? Number(m[1]) : -1;
}

async function main() {
  check(["ipc", "http", "both"].includes(mode), "the mode is ipc, http or both");
  check(await waitFor(() => run(["--serve", "status"]).code === 0), "the machine answers");

  // which doors are open
  const st = run(["--serve", "status"]);
  check(st.out.includes("ipc: " + (hasIpc ? "listening" : "off")), "ipc is " + (hasIpc ? "listening" : "off"));
  check(st.out.includes("http: " + (hasHttp ? "listening" : "off")), "http is " + (hasHttp ? "listening" : "off"));
  check((await httpUp()) === hasHttp, "the http port " + (hasHttp ? "answers" : "is closed"));
  if (hasHttp) {
    const page = await (await fetch(http + "/")).text();
    check(page.includes("Hello World") && page.includes("This is Eve"), "the page says: Hello World, This is Eve");
  }

  // --local never uses the network: with IPC it reaches the machine, without IPC it runs the script by itself
  const before = runs();
  const local = run(["-loc", "-x", "check/hello.eve"]);
  check(local.code === 0 && local.out.includes("Hello from the machine"), "--local runs the script");
  check(runs() === before + (hasIpc ? 1 : 0), hasIpc ? "--local ran it in the machine (IPC)" : "--local ran it by itself, no machine");
  const lstat = run(["-loc", "--serve", "status"]);
  check(hasIpc ? lstat.code === 0 : lstat.code === 69, "--local status " + (hasIpc ? "answers" : "finds no machine (69)"));
  // --listen <word> speaks through the IPC door only, like --local (D-169)
  const istat = run(["--listen", "status"]);
  check(hasIpc ? istat.code === 0 && istat.out.includes("ipc: listening") : istat.code === 69,
    "--listen status " + (hasIpc ? "answers through IPC" : "finds no IPC door (69)"));
  const old = run(["-lsn"]);
  check(old.code === 64 && /unknown option -lsn/.test(old.all), "-lsn is an unknown option now (64)");

  // --remote uses HTTP only
  const remote = run(["-rem", "localhost:8095", "-x", "check/hello.eve"]);
  if (hasHttp) {
    check(remote.code === 0 && remote.out.includes("Hello from the machine"), "--remote runs the script over HTTP");
    check(runs() === before + (hasIpc ? 2 : 1), "--remote ran it in the machine");
    const bad = run(["-rem", "localhost:8095", "-x", "check/fail.eve"]);
    check(bad.code === 4 && bad.err.includes("boom"), "the error of a remote script comes back with exit code 4");
  } else {
    check(remote.code === 69 && /no remote machine/.test(remote.all), "--remote fails when HTTP is off (69, no remote machine)");
  }
  const nobody = run(["-rem", "localhost:8197", "-x", "check/hello.eve"]);
  check(nobody.code === 69 && /no remote machine/.test(nobody.all), "--remote fails when nobody listens there (69)");
  const bare = run(["-rem", "--serve", "status"]);
  check(bare.code === 64 && /needs an address/.test(bare.all), "--remote without an address is a usage error (64)");

  // a machine is a singleton: a second start on the same address fails
  const again = run(hasIpc ? ["--listen"] : ["--serve"]);
  check(again.code === 75 && /already running/.test(again.all), "a second start fails: already running (75)");

  // stop: the machine ends, the doors close
  // with an IPC door the machine is stopped through it; with HTTP only, through the web door
  const stopWith = hasIpc ? "--listen" : "--serve";
  check(run([stopWith, "stop"]).code === 0, stopWith + " stop ends with 0");
  check(await waitFor(async () => run(["--serve", "status"]).code === 69), "after stop: not running (69)");
  check(!(await httpUp()), "after stop: the http port is closed");

  console.log("modes " + mode + ": all checks passed");
}

main().catch((e) => {
  console.error("FAIL " + e);
  process.exit(1);
});
