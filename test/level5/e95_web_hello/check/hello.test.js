// Client of the test e95: Node.js 18 or later (fetch is built in), no package to install.
// It asks the Eve web server for the page and looks for the text in the HTML, then checks that the machine
// is a singleton (a second `eve --serve` fails) and stops it with `eve --serve stop`. Exit code 0 = ok.
// The runner gives the path of the VM in the environment variable EVE.
const { spawnSync } = require("node:child_process");
const eve = process.env.EVE || "eve";
const base = "http://localhost:8095";

// The runner starts `eve --serve` and this script at once: try for up to 10 seconds until the server answers.
async function get(path) {
  let last;
  for (let i = 0; i < 50; i++) {
    try {
      return await fetch(base + path);
    } catch (e) {
      last = e;
      await new Promise((r) => setTimeout(r, 200));
    }
  }
  throw last;
}

function check(ok, what) {
  if (!ok) {
    console.error("FAIL " + what);
    process.exit(1);
  }
  console.log("ok " + what);
}

async function main() {
  const page = await get("/");
  const html = await page.text();
  check(page.status === 200, "GET / answers 200");
  check((page.headers.get("content-type") || "").startsWith("text/html"), "GET / is text/html");
  check(html.includes("Hello World"), "the page says: Hello World");
  check(html.includes("This is Eve"), "the page says: This is Eve");

  // the folders of the web folder are served with their own content types
  const css = await get("/css/style.css");
  check(css.status === 200 && (css.headers.get("content-type") || "").startsWith("text/css"), "GET /css/style.css is text/css");
  const js = await get("/js/app.js");
  check(js.status === 200 && /javascript/.test(js.headers.get("content-type") || ""), "GET /js/app.js is JavaScript");

  // a path that is not in the web folder is a 404; a file of the project outside of it, such as eve.cfg, is never served
  check((await get("/nothing.html")).status === 404, "GET /nothing.html answers 404");
  const head = await fetch(base + "/", { method: "HEAD" });
  check(head.status === 200 && (await head.text()) === "", "HEAD / answers 200 without a body");
  check((await get("/eve.cfg")).status === 404, "GET /eve.cfg (not in web) answers 404");

  // one machine per domain and port: a second --serve in the same project fails, and says why
  const second = spawnSync(eve, ["--serve"], { encoding: "utf8", timeout: 10000 });
  check(second.status === 75, "a second --serve fails with 75");
  check(/already running/.test(second.stdout + second.stderr), "the second --serve says: already running");
  check((await get("/")).status === 200, "the first server still answers");

  // stop: the machine answers the command, then the port is free
  const stop = spawnSync(eve, ["--serve", "stop"], { encoding: "utf8", timeout: 10000 });
  check(stop.status === 0, "--serve stop ends with 0");
  let down = false;
  for (let i = 0; i < 50 && !down; i++) {
    try {
      await fetch(base + "/");
      await new Promise((r) => setTimeout(r, 200));
    } catch (e) {
      down = true;
    }
  }
  check(down, "the port is free after --serve stop");

  console.log("web: all checks passed");
}

main().catch((e) => {
  console.error("FAIL " + e);
  process.exit(1);
});
