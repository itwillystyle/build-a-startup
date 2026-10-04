"""recv.py -- a tiny localhost receiver: Studio POSTs data here (HttpService),
it lands in blender/out/<name>. Usage: python recv.py 8732
POST /<name>  body -> out/<name>   (localhost only, never exposed)"""
import http.server
import os
import sys

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")


class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        name = os.path.basename(self.path.strip("/")) or "post.bin"
        n = int(self.headers.get("Content-Length", 0))
        data = self.rfile.read(n)
        with open(os.path.join(OUT, name), "ab" if self.headers.get("X-Append") else "wb") as f:
            f.write(data)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok %d" % len(data))

    def log_message(self, *a):
        pass


port = int(sys.argv[1]) if len(sys.argv) > 1 else 8732
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
