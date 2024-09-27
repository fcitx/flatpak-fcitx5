import http.server
import os.path
import urllib.request
import shutil
import socketserver
import sys

class BazelMirror(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if not self.path or self.path.endswith("/"):
            self.send_error(http.HTTPStatus.NOT_FOUND)
            return None
        local_path = os.getcwd() + self.path
        if not os.path.isfile(local_path):
            directory = os.path.dirname(local_path)
            os.makedirs(directory, exist_ok=True)
            url = f'https:/{self.path}'
            print(f"download {url}")
            urllib.request.urlretrieve(url, local_path)
        with open(local_path, 'rb') as f:
            print(f"sending {local_path}")
            self.send_response(http.HTTPStatus.OK)
            self.send_header("Content-type", 'application/octet-stream')
            fs = os.fstat(f.fileno())
            self.send_header("Content-Length", str(fs[6]))
            self.send_header("Last-Modified",
                self.date_time_string(fs.st_mtime))
            self.end_headers()

            shutil.copyfileobj(f, self.wfile)
            if not self.wfile.closed:
                self.wfile.flush()
            self.rfile.close()
            print(f"done {local_path}")

class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True

try:
    server = ThreadedHTTPServer(
        ('127.0.0.1', 8000),
        BazelMirror
    )
except Exception:
    e = sys.exc_info()[1]
    sys.exit(1)

server.serve_forever()
