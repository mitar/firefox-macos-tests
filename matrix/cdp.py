"""Sets a preference of Chrome or Edge as its settings page does, through the DevTools protocol.

Usage: python3 cdp.py PORT SETTINGS_URL PREF VALUE

The browser runs with --remote-debugging-port=PORT and --remote-allow-origins=*. The script opens SETTINGS_URL in a new
tab and calls chrome.settingsPrivate.setPref(PREF, VALUE) in it, the function the page's own controls call, so that the
browser stores and signs the preference as for a click. It prints the result of setPref (true when set). The WebSocket
client is minimal, for the text frames of the protocol, as the runners' Python has none.
"""

import base64
import json
import os
import socket
import struct
import sys
import time
import urllib.parse
import urllib.request


class WebSocket:
    def __init__(self, url):
        parts = urllib.parse.urlparse(url)
        self.sock = socket.create_connection((parts.hostname, parts.port), timeout=30)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall((f"GET {parts.path} HTTP/1.1\r\nHost: {parts.hostname}:{parts.port}\r\nUpgrade: websocket\r\n"
                           f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
        response = b""
        while b"\r\n\r\n" not in response:
            response += self.sock.recv(1)
        if b" 101 " not in response.split(b"\r\n", 1)[0]:
            raise RuntimeError(f"no WebSocket: {response!r}")

    def send(self, text):
        data = text.encode()
        mask = os.urandom(4)
        header = bytes([0x81])
        if len(data) < 126:
            header += bytes([0x80 | len(data)])
        elif len(data) < 65536:
            header += bytes([0x80 | 126]) + struct.pack(">H", len(data))
        else:
            header += bytes([0x80 | 127]) + struct.pack(">Q", len(data))
        self.sock.sendall(header + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

    def recv_exact(self, n):
        data = b""
        while len(data) < n:
            chunk = self.sock.recv(n - len(data))
            if not chunk:
                raise RuntimeError("the WebSocket closed")
            data += chunk
        return data

    def receive(self):
        first, second = self.recv_exact(2)
        length = second & 0x7F
        if length == 126:
            length = struct.unpack(">H", self.recv_exact(2))[0]
        elif length == 127:
            length = struct.unpack(">Q", self.recv_exact(8))[0]
        return self.recv_exact(length).decode(errors="replace")


def main():
    port, url, pref, value = sys.argv[1], sys.argv[2], sys.argv[3], json.loads(sys.argv[4])
    base = f"http://127.0.0.1:{port}"
    for _ in range(60):
        try:
            urllib.request.urlopen(f"{base}/json/version", timeout=2)
            break
        except OSError:
            time.sleep(1)
    request = urllib.request.Request(f"{base}/json/new?{url}", method="PUT")
    target = json.load(urllib.request.urlopen(request, timeout=10))
    time.sleep(5)
    ws = WebSocket(target["webSocketDebuggerUrl"])
    expression = (f"new Promise(resolve => chrome.settingsPrivate.setPref({json.dumps(pref)}, {json.dumps(value)}, '', "
                  "result => resolve(result)))")
    ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate", "params": {"expression": expression, "awaitPromise": True,
                                                                          "returnByValue": True}}))
    while True:
        message = json.loads(ws.receive())
        if message.get("id") == 1:
            print(json.dumps(message.get("result", message)))
            return


main()
