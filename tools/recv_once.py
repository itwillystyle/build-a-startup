# recv_once.py (27 Oct 2026): take ONE POST from Studio on 127.0.0.1:34999, write its body to argv[1], exit.
# Studio's HttpService:PostAsync is how a fingerprint or doctor report reaches disk. Interactive
# sessions only: in a routine its python command is a permission prompt nobody answers.
import sys, http.server
out = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        open(out, "wb").write(body)
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok %d" % len(body))
        raise SystemExit
srv = http.server.HTTPServer(("127.0.0.1", 34999), H)
srv.timeout = 300   # no POST in 5 minutes: give up instead of waiting forever
srv.handle_request()
