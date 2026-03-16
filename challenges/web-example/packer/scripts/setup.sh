#!/bin/bash
# web-example 題目 provisioning
# 安裝 nginx + 簡易 vulnerable web app
set -euo pipefail

echo "==> [web-example] 安裝 python3..."
# nginx 不需要（題目用 Python HTTP server），移除以加速開機
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 > /dev/null

echo "==> [web-example] 建立題目 Web 應用..."
sudo mkdir -p /opt/challenge

# 簡易 Python web server（有目錄遍歷漏洞的示範）
sudo tee /opt/challenge/server.py > /dev/null << 'PYEOF'
#!/usr/bin/env python3
"""CTF Web Challenge - Directory Traversal Demo"""
import http.server
import os

FLAG_PATH = "/opt/ctf/flag.txt"
PORT = 8080

class VulnerableHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory="/opt/challenge/www", **kwargs)

    def do_GET(self):
        # Hint: 試試 /static?file=../../../opt/ctf/flag.txt
        if self.path.startswith("/static?file="):
            filename = self.path.split("file=", 1)[1]
            try:
                filepath = os.path.join("/opt/challenge/www", filename)
                with open(filepath, "r") as f:
                    content = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.wfile.write(content.encode())
            except Exception:
                self.send_error(404, "File not found")
        elif self.path == "/":
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(b"""<!DOCTYPE html>
<html><body>
<h1>Welcome to the CTF Challenge!</h1>
<p>Can you find the hidden flag?</p>
<p>Try browsing: <a href="/static?file=readme.txt">/static?file=readme.txt</a></p>
</body></html>""")
        else:
            super().do_GET()

if __name__ == "__main__":
    server = http.server.HTTPServer(("0.0.0.0", PORT), VulnerableHandler)
    print(f"Challenge server running on port {PORT}")
    server.serve_forever()
PYEOF

sudo chmod +x /opt/challenge/server.py

# 建立靜態檔案目錄
sudo mkdir -p /opt/challenge/www
echo "This is a readme file. The flag is hidden somewhere on this server..." | sudo tee /opt/challenge/www/readme.txt > /dev/null

echo "==> [web-example] 建立 systemd service..."
sudo tee /etc/systemd/system/challenge.service > /dev/null << 'SVCEOF'
[Unit]
Description=CTF Web Challenge
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/challenge/server.py
Restart=always
RestartSec=3
WorkingDirectory=/opt/challenge

[Install]
WantedBy=multi-user.target
SVCEOF

sudo systemctl daemon-reload
sudo systemctl enable challenge.service

echo "==> [web-example] 題目設定完成"
