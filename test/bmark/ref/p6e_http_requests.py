# reference for p6e_http_requests.eve: the same work in Python, with http.server in a thread and http.client
import http.client
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *args):
        pass

    def reply(self, text):
        body = text.encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path.startswith("/users/"):
            self.reply("user " + url.path.split("/")[2])
        else:
            q = parse_qs(url.query)
            self.reply(str(int(q["a"][0]) + int(q["b"][0])))

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        self.reply(self.rfile.read(n).decode())


server = HTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
port = server.server_address[1]


def call(verb, path, body=None):
    con = http.client.HTTPConnection("127.0.0.1", port)
    con.request(verb, path, body=body)
    data = con.getresponse().read().decode()
    con.close()
    return data


total = 0
for i in range(1, 101):
    total += len(call("GET", f"/users/{i}"))
    total += len(call("GET", f"/sum?a={i}&b=1"))
    total += len(call("POST", "/echo", f"payload {i}"))
assert total == 1878, total
print(total)
server.shutdown()
