#!/usr/bin/env bash
set -euo pipefail

target="/var/lib/secrets/trmnl.env"

if [[ -e "${target}" ]]; then
  echo "${target} already exists; leaving it unchanged." >&2
  exit 0
fi

# Hex, not base64: this password is also embedded in DATABASE_URL, where '+'
# and '/' from base64 would have to be percent-encoded to survive parsing.
database_password="$(openssl rand -hex 32)"
app_secret="$(openssl rand -hex 64)"

sudo install -d -m 0750 -o root -g root /var/lib/secrets
tmp="$(mktemp)"
chmod 0600 "${tmp}"

# The hostnames are the container names; Podman's DNS resolves them on the
# 'trmnl' network. Valkey runs without a password, so KEYVALUE_URL has none —
# its port is never published (see modules/trmnl.nix).
cat > "${tmp}" <<EOF
APP_SECRET=${app_secret}
POSTGRES_PASSWORD=${database_password}
DATABASE_URL=postgres://terminus:${database_password}@trmnl-database:5432/terminus
KEYVALUE_URL=redis://trmnl-keyvalue:6379/0
EOF

sudo install -m 0400 -o root -g root "${tmp}" "${target}"
rm -f "${tmp}"

echo "Created ${target}"
echo
echo "Next: set server.trmnl.enable and server.trmnl.apiUri in your private"
echo "local.nix, then run nixos-rebuild switch. Register the first account at"
echo "http://trmnl.home.arpa — registration is open, so do it before pointing"
echo "any device at the server."
