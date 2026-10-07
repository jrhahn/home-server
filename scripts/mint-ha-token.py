#!/usr/bin/env python3
"""Mint a Home Assistant long-lived access token without knowing the password.

Run as root (the auth store is hass-only):
  sudo .../mint-ha-token.py --list
  sudo .../mint-ha-token.py [NAME] [--user WHO] [--days N] [--print]

Why this works without credentials: /srv/home-assistant/.storage/auth keeps the
refresh tokens of every logged-in session in cleartext. A refresh token is
exactly what the frontend uses to stay signed in, so it can be exchanged at
POST /auth/token for a short-lived access token -- and an authenticated session
may mint a long-lived token over the WebSocket API
(`auth/long_lived_access_token`), which is the only place HA offers that.

Nothing is reset or invalidated: exchanging a refresh token does not consume
it, and the password is never involved (it is a bcrypt hash in
auth_provider.homeassistant and cannot be read back anyway).

--list   show users and sessions, no secrets printed
--user   pick the session of this user (name or username); default: the owner
NAME     label shown in HA under profile -> Security (default: the hostname)
--days   lifespan in days (default 3650)
--print  write the token to stdout instead of ~/.ha-token
Host: $HA_HOST (default 127.0.0.1), $HA_PORT (default 8123).
"""

import importlib.util
import json
import os
import pathlib
import pwd
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request

STORAGE = pathlib.Path("/srv/home-assistant/.storage")
HOST = os.environ.get("HA_HOST", "127.0.0.1")
PORT = int(os.environ.get("HA_PORT", "8123"))
BASE = f"http://{HOST}:{PORT}"

_registry = pathlib.Path(__file__).resolve().parent / "ha-entity-registry.py"
if not _registry.exists():
    sys.exit(f"cannot find the WebSocket helper at {_registry}")
_spec = importlib.util.spec_from_file_location("ha_entity_registry", _registry)
_ha = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_ha)
WebSocket = _ha.WebSocket


def load(name):
    path = STORAGE / name
    try:
        return json.loads(path.read_text())["data"]
    except PermissionError:
        sys.exit(f"{path} is hass-only -- rerun with sudo")
    except FileNotFoundError:
        sys.exit(f"no {path}; is $HA_HOST really this machine?")


def accounts():
    """Users with their login names and their password-login sessions."""
    auth = load("auth")
    usernames = {}
    for entry in load("auth_provider.homeassistant")["users"]:
        usernames.setdefault(entry["user_id"], entry["username"])

    users = {}
    for user in auth["users"]:
        if user.get("system_generated"):
            continue  # Supervisor et al., they cannot own a login
        users[user["id"]] = {
            "name": user.get("name") or "?",
            "username": usernames.get(user["id"]),
            "owner": bool(user.get("is_owner")),
            "active": bool(user.get("is_active")),
            "sessions": [],
            "tokens": [],
        }

    for token in auth["refresh_tokens"]:
        user = users.get(token["user_id"])
        if user is None:
            continue
        if token.get("token_type") == "long_lived_access_token":
            user["tokens"].append(token)
        elif token.get("client_id"):
            user["sessions"].append(token)
    for user in users.values():
        user["sessions"].sort(key=lambda t: t.get("created_at") or "")
    return users


def show(users):
    for user in users.values():
        flags = ", ".join(
            f
            for f in ("owner" if user["owner"] else "", "" if user["active"] else "disabled")
            if f
        )
        print(f"{user['name']}  login={user['username'] or '-'}  {flags}".rstrip())
        for token in user["sessions"]:
            print(
                f"    session   {token.get('created_at', '?')[:19]}"
                f"  {token.get('client_id')}"
            )
        for token in user["tokens"]:
            print(
                f"    token     {token.get('created_at', '?')[:19]}"
                f"  {token.get('client_name')}"
            )
        if not user["sessions"]:
            print("    (no password session -- cannot mint a token for this user)")


def pick(users, wanted):
    candidates = [u for u in users.values() if u["active"] and u["sessions"]]
    if not candidates:
        sys.exit(
            "no usable session in the auth store. Log in once in the browser, "
            "or reset the password: sudo -u hass hass --config "
            "/srv/home-assistant --script auth change_password <user> <new>"
        )
    if wanted:
        matches = [
            u
            for u in candidates
            if wanted in (u["username"], u["name"])
        ]
        if not matches:
            sys.exit(f"no active session for {wanted!r}; try --list")
        return matches[0]
    for user in candidates:
        if user["owner"]:
            return user
    return candidates[0]


def post(path, payload):
    request = urllib.request.Request(
        BASE + path,
        data=urllib.parse.urlencode(payload).encode(),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as error:
        sys.exit(
            f"POST {path} failed: {error.code} {error.reason}\n"
            f"{error.read().decode(errors='replace').strip()}"
        )
    except urllib.error.URLError as error:
        sys.exit(f"POST {path} failed: {error.reason}")


def access_token(session):
    # HA checks that client_id matches the one the refresh token was issued to.
    reply = post(
        "/auth/token",
        {
            "grant_type": "refresh_token",
            "refresh_token": session["token"],
            "client_id": session["client_id"],
        },
    )
    if "access_token" not in reply:
        sys.exit(f"no access token: {reply}")
    return reply["access_token"]


def long_lived_token(short_lived, name, days):
    ws = WebSocket(HOST, PORT)
    hello = ws.recv()
    if hello.get("type") != "auth_required":
        sys.exit(f"unexpected greeting: {hello}")
    ws.send({"type": "auth", "access_token": short_lived})
    ok = ws.recv()
    if ok.get("type") != "auth_ok":
        sys.exit(f"websocket authentication failed: {ok}")
    ws.send(
        {
            "id": 1,
            "type": "auth/long_lived_access_token",
            "client_name": name,
            "lifespan": days,
        }
    )
    while True:
        reply = ws.recv()
        if reply.get("id") == 1 and reply.get("type") == "result":
            break
    if not reply.get("success"):
        sys.exit(f"HA refused to mint the token: {reply.get('error')}")
    return reply["result"]


def destination():
    """~/.ha-token of the user who invoked sudo, not root's."""
    who = os.environ.get("SUDO_USER")
    if not who:
        return pathlib.Path.home() / ".ha-token", None
    entry = pwd.getpwnam(who)
    return pathlib.Path(entry.pw_dir) / ".ha-token", entry


def main(argv):
    args, name, days, to_stdout, listing, wanted = argv[1:], None, 3650, False, False, None
    while args:
        arg = args.pop(0)
        if arg == "--list":
            listing = True
        elif arg == "--print":
            to_stdout = True
        elif arg == "--days":
            days = int(args.pop(0))
        elif arg == "--user":
            wanted = args.pop(0)
        elif arg in ("-h", "--help"):
            sys.exit(__doc__)
        elif name is None:
            name = arg
        else:
            sys.exit(__doc__)

    users = accounts()
    if listing:
        show(users)
        return 0

    user = pick(users, wanted)
    session = user["sessions"][-1]  # the most recent login
    print(
        f"using {user['name']}'s session from {session.get('created_at', '?')[:19]}",
        file=sys.stderr,
    )
    token = long_lived_token(
        access_token(session), name or socket.gethostname(), days
    )

    if to_stdout:
        print(token)
        return 0
    target, owner = destination()
    # HA shows the value once; 0600 before the bytes land, not after.
    handle = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(handle, "w") as out:
        out.write(token + "\n")
    if owner:
        os.chown(target, owner.pw_uid, owner.pw_gid)
    print(f"wrote {target} (0600), token '{name or socket.gethostname()}', {days} days",
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
