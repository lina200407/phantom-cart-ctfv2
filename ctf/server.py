#!/usr/bin/env python3
"""
Operation Phantom Cart — Render-Compatible Server
"""
import http.server
import socketserver
import os
import time
import urllib.parse
import secrets
import threading
import urllib.request
from collections import defaultdict
from datetime import datetime

PORT        = int(os.environ.get("PORT", 8080))
ACCESS_CODE = os.environ.get("ACCESS_CODE", "phantom2026")
SERVE_DIR   = os.path.dirname(os.path.abspath(__file__))
RATE_LIMIT  = int(os.environ.get("RATE_LIMIT", 90))

BLOCKED_PATHS = ["/PRESENTER_ANSWERS.md", "/.git", "/server.py", "/render.yaml"]

sessions     = {}
rate_buckets = defaultdict(list)

def log(ip, method, path, status):
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] {ip:20s} {method} {path[:55]:55s} {status}", flush=True)

def get_forwarded_ip(headers):
    forwarded = headers.get("X-Forwarded-For", "")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return "unknown"

def is_rate_limited(ip):
    now = time.time()
    rate_buckets[ip] = [t for t in rate_buckets[ip] if now - t < 60]
    if len(rate_buckets[ip]) >= RATE_LIMIT:
        return True
    rate_buckets[ip].append(now)
    return False

def get_session_token(headers):
    cookie_header = headers.get("Cookie", "")
    for part in cookie_header.split(";"):
        part = part.strip()
        if part.startswith("ctf_session="):
            return part[len("ctf_session="):]
    return None

def is_authed(headers):
    token = get_session_token(headers)
    if not token:
        return False
    session = sessions.get(token)
    if not session:
        return False
    if time.time() - session["ts"] > 14400:
        del sessions[token]
        return False
    return True

LOGIN_PAGE = """<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Operation Phantom Cart</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:#0a0f1e;color:#f5f3ee;font-family:sans-serif;
       display:flex;align-items:center;justify-content:center;min-height:100vh;padding:20px}
  .box{background:#121929;border:1px solid rgba(255,255,255,0.08);
        border-radius:12px;padding:40px 48px;width:100%;max-width:380px;text-align:center}
  h1{color:#c9a84c;font-size:22px;margin-bottom:8px}
  p{color:#8a95a8;font-size:13px;margin-bottom:28px;line-height:1.6}
  input{width:100%;background:#0a0f1e;border:1px solid rgba(255,255,255,0.1);
         border-radius:6px;color:#f5f3ee;font-size:16px;padding:12px 16px;
         outline:none;text-align:center;letter-spacing:4px;font-family:monospace}
  input:focus{border-color:#c9a84c}
  button{width:100%;margin-top:14px;background:#c9a84c;color:#0a0f1e;border:none;
          border-radius:6px;padding:13px;font-weight:700;font-size:14px;cursor:pointer}
  button:hover{background:#e8c870}
  .err{color:#e05252;font-size:13px;margin-top:12px;display:__ERR__}
  .dot{width:8px;height:8px;border-radius:50%;background:#e05252;
        display:inline-block;margin-right:6px;animation:p 1.2s infinite}
  @keyframes p{0%,100%{opacity:1}50%{opacity:.3}}
</style>
</head>
<body>
<div class="box">
  <h1>Operation Phantom Cart</h1>
  <p>Enter the workshop access code to begin the investigation.</p>
  <form method="POST" action="/auth">
    <input type="password" name="code" placeholder="access code" autofocus autocomplete="off">
    <button type="submit">Enter</button>
  </form>
  <div class="err"><span class="dot"></span>Incorrect code. Try again.</div>
</div>
</body>
</html>"""

BLOCKED_PAGE = b"<html><body style='background:#0a0f1e;color:#e05252;font-family:monospace;display:flex;align-items:center;justify-content:center;min-height:100vh;font-size:18px'>403 Forbidden</body></html>"
RATE_PAGE    = b"<html><body style='background:#0a0f1e;color:#e05252;font-family:monospace;display:flex;align-items:center;justify-content:center;min-height:100vh;font-size:18px'>429 Too Many Requests</body></html>"


class SecureHandler(http.server.SimpleHTTPRequestHandler):

    def get_client_ip(self):
        return get_forwarded_ip(self.headers)

    def send_login(self, wrong_code=False):
        page = LOGIN_PAGE.replace("__ERR__", "block" if wrong_code else "none").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(page)))
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(page)

    def do_GET(self):
        ip = self.get_client_ip()
        if is_rate_limited(ip):
            log(ip, "GET", self.path, "429")
            self.send_response(429); self.end_headers(); self.wfile.write(RATE_PAGE); return
        clean_path = urllib.parse.urlparse(self.path).path
        for blocked in BLOCKED_PATHS:
            if clean_path.startswith(blocked):
                log(ip, "GET", self.path, "403")
                self.send_response(403); self.end_headers(); self.wfile.write(BLOCKED_PAGE); return
        if not is_authed(self.headers):
            log(ip, "GET", self.path, "401")
            self.send_login(); return
        log(ip, "GET", self.path, "200")
        super().do_GET()

    def do_POST(self):
        ip = self.get_client_ip()
        if is_rate_limited(ip):
            self.send_response(429); self.end_headers(); self.wfile.write(RATE_PAGE); return
        if self.path == "/auth":
            length = int(self.headers.get("Content-Length", 0))
            body   = self.rfile.read(length).decode()
            params = urllib.parse.parse_qs(body)
            code   = params.get("code", [""])[0].strip()
            if code == ACCESS_CODE:
                token = secrets.token_hex(32)
                sessions[token] = {"ts": time.time()}
                log(ip, "POST", "/auth", "302-OK")
                self.send_response(302)
                self.send_header("Set-Cookie",
                    f"ctf_session={token}; Path=/; HttpOnly; SameSite=Strict; Max-Age=14400")
                self.send_header("Location", "/index.html")
                self.end_headers()
            else:
                log(ip, "POST", "/auth", "401-WRONG")
                self.send_login(wrong_code=True)
            return
        self.send_response(405); self.end_headers()

    def log_message(self, format, *args):
        pass


def keep_alive():
    time.sleep(60)
    while True:
        try:
            urllib.request.urlopen(f"http://localhost:{PORT}/", timeout=10)
            print("[keep-alive] ping OK", flush=True)
        except Exception as e:
            print(f"[keep-alive] {e}", flush=True)
        time.sleep(600)


if __name__ == "__main__":
    os.chdir(SERVE_DIR)
    threading.Thread(target=keep_alive, daemon=True).start()
    print(f"Starting on port {PORT} | access code: {ACCESS_CODE}", flush=True)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("", PORT), SecureHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("Stopped.")
