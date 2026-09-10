#!/usr/bin/env python3
"""List and remove rows in Home Assistant's entity registry.

Why a script at all: removing a registry row is a WebSocket-only operation.
The REST API can delete a *state* (`DELETE /api/states/...`), but the state
machine is not the registry — the row survives and Home Assistant restores the
entity as `unavailable` on the next restart. Only
`config/entity_registry/remove` over `/api/websocket` actually forgets it.

Why it matters here: taking a sensor out of the Nix configuration only makes
its entity `unavailable`. The row stays, `GET /api/states` keeps serving it
with its `friendly_name`, and anything deriving from those names — the TRMNL
Zuhause screen derives its room tiles that way, see ../trmnl/README.md — keeps
showing a room that no longer exists. No rebuild can fix that, because the
registry is persistent state in /srv/home-assistant/.storage, not a build
output.

Usage:
  ha-entity-registry.py list [REGEX]      rows, optionally filtered
  ha-entity-registry.py remove ENTITY_ID...

Token: $HA_TOKEN, else the first line of ~/.ha-token. Create one under
profile -> Security -> long-lived access tokens; the value is shown once.
Host: $HA_HOST (default 192.168.1.67), $HA_PORT (default 8123).

Stdlib only, so it runs on the server without a Python environment.
"""

import base64
import hashlib
import json
import os
import pathlib
import re
import socket
import struct
import sys

HOST = os.environ.get("HA_HOST", "192.168.1.67")
PORT = int(os.environ.get("HA_PORT", "8123"))
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"  # RFC 6455


def token():
    if os.environ.get("HA_TOKEN"):
        return os.environ["HA_TOKEN"].strip()
    path = pathlib.Path.home() / ".ha-token"
    if not path.exists():
        sys.exit("no token: set $HA_TOKEN or write ~/.ha-token")
    return path.read_text().strip()


class WebSocket:
    """The 200 lines of RFC 6455 this script actually needs."""

    def __init__(self, host, port, path="/api/websocket"):
        self.sock = socket.create_connection((host, port), timeout=20)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall(
            (
                f"GET {path} HTTP/1.1\r\n"
                f"Host: {host}:{port}\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Key: {key}\r\n"
                "Sec-WebSocket-Version: 13\r\n\r\n"
            ).encode()
        )
        head = b""
        while b"\r\n\r\n" not in head:
            byte = self.sock.recv(1)
            if not byte:
                raise RuntimeError("server closed during handshake")
            head += byte
        status = head.split(b"\r\n", 1)[0].decode()
        if "101" not in status:
            raise RuntimeError(f"handshake refused: {status}")
        accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
        if accept.lower() not in head.decode().lower():
            raise RuntimeError("Sec-WebSocket-Accept does not match the key")
        self.buf = b""

    def _read(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise RuntimeError("server closed")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def _frame(self, opcode, payload):
        # Client frames MUST be masked (RFC 6455 5.3) -- with the key that is
        # actually applied to the payload, which is easy to get subtly wrong.
        header = bytes([0x80 | opcode])
        n = len(payload)
        if n < 126:
            header += bytes([0x80 | n])
        elif n < 1 << 16:
            header += bytes([0x80 | 126]) + struct.pack("!H", n)
        else:
            header += bytes([0x80 | 127]) + struct.pack("!Q", n)
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        return header + mask + masked

    def send(self, obj):
        self.sock.sendall(self._frame(0x1, json.dumps(obj).encode()))

    def recv(self):
        data = b""
        while True:
            b0, b1 = self._read(2)
            fin, opcode = b0 & 0x80, b0 & 0x0F
            if b1 & 0x80:
                raise RuntimeError("server frame is masked")
            n = b1 & 0x7F
            if n == 126:
                n = struct.unpack("!H", self._read(2))[0]
            elif n == 127:
                n = struct.unpack("!Q", self._read(8))[0]
            body = self._read(n)
            if opcode == 0x9:  # ping -> pong, echoing the payload
                self.sock.sendall(self._frame(0xA, body))
                continue
            if opcode == 0xA:  # unsolicited pong
                continue
            if opcode == 0x8:
                raise RuntimeError("server sent close")
            data += body
            if fin:
                return json.loads(data.decode())


class Client:
    def __init__(self):
        self.ws = WebSocket(HOST, PORT)
        hello = self.ws.recv()
        if hello.get("type") != "auth_required":
            raise RuntimeError(f"unexpected greeting: {hello}")
        self.ws.send({"type": "auth", "access_token": token()})
        ok = self.ws.recv()
        if ok.get("type") != "auth_ok":
            sys.exit(f"authentication failed: {ok}")
        self.next_id = 1

    def call(self, message):
        message["id"] = self.next_id
        self.next_id += 1
        self.ws.send(message)
        # Subscriptions would interleave events here, so match on the id.
        while True:
            reply = self.ws.recv()
            if reply.get("id") == message["id"] and reply.get("type") == "result":
                return reply


def main(argv):
    if len(argv) < 2 or argv[1] not in ("list", "remove"):
        sys.exit(__doc__)
    client = Client()

    if argv[1] == "list":
        pattern = re.compile(argv[2]) if len(argv) > 2 else None
        rows = client.call({"type": "config/entity_registry/list"})["result"]
        shown = 0
        for row in sorted(rows, key=lambda r: r["entity_id"]):
            if pattern and not pattern.search(row["entity_id"]):
                continue
            print(
                "\t".join(
                    (
                        row["entity_id"],
                        row.get("platform") or "-",
                        row.get("config_entry_id") or "-",
                        row.get("unique_id") or "-",
                    )
                )
            )
            shown += 1
        print(f"# {shown} of {len(rows)} rows", file=sys.stderr)
        return 0

    failed = 0
    for entity_id in argv[2:]:
        reply = client.call(
            {"type": "config/entity_registry/remove", "entity_id": entity_id}
        )
        if reply.get("success"):
            print(f"{entity_id}\tremoved")
        else:
            print(f"{entity_id}\tFAILED {reply.get('error')}", file=sys.stderr)
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
