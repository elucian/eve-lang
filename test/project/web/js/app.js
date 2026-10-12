// The frontend of the live machine page: plain JavaScript, no package. It talks to the machine through its HTTP door
// with JSON-RPC 2.0 in POST /rpc (spec/library/machine.md): the method status for the panel, run for the editor.

let nextId = 1;

// One JSON-RPC call: the result, or an exception with the error of the machine or of the network.
async function rpc(method, params) {
  const answer = await fetch("/rpc", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: nextId++, method, params }),
  });
  const msg = await answer.json();
  if (msg.error) throw new Error(msg.error.message);
  return msg.result;
}

const $ = (id) => document.getElementById(id);

async function refresh() {
  try {
    const s = await rpc("status");
    $("status").className = "";
    $("status").textContent =
      `machine: ${s.domain} ipc=${s.ipc_port} http=${s.http_port}\n` +
      `ipc: ${s.ipc ? "listening" : "off"}\n` +
      `http: ${s.http ? "listening" : "off"}\n` +
      `runs: ${s.runs}`;
  } catch (e) {
    $("status").className = "down";
    $("status").textContent = "the machine does not answer (stopped?)";
  }
}

async function run() {
  $("run").disabled = true;
  $("exit").textContent = "running…";
  $("output").textContent = "";
  $("errors").textContent = "";
  try {
    const r = await rpc("run", { name: "browser.eve", source: $("source").value, args: [] });
    $("output").textContent = r.output;
    $("errors").textContent = r.errors;
    $("exit").textContent = "exit code " + r.status;
  } catch (e) {
    $("exit").textContent = "failed: " + e.message;
  } finally {
    $("run").disabled = false;
    refresh();
  }
}

$("refresh").addEventListener("click", refresh);
$("run").addEventListener("click", run);
document.getElementById("app").dataset.ready = "true";
refresh();
setInterval(refresh, 2000);
