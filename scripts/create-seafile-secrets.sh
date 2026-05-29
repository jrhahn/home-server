#!/usr/bin/env bash
set -euo pipefail

target="/var/lib/secrets/seafile.env"

if [[ -e "${target}" ]]; then
  echo "${target} already exists; leaving it unchanged." >&2
  exit 0
fi

mysql_root_password="$(openssl rand -base64 32)"
mysql_user_password="$(openssl rand -base64 32)"
jwt_private_key="$(openssl rand -base64 48)"
admin_password="$(openssl rand -base64 24)"

sudo install -d -m 0750 -o root -g root /var/lib/secrets
tmp="$(mktemp)"
chmod 0600 "${tmp}"

cat > "${tmp}" <<EOF
MYSQL_ROOT_PASSWORD=${mysql_root_password}
MARIADB_ROOT_PASSWORD=${mysql_root_password}
INIT_SEAFILE_MYSQL_ROOT_PASSWORD=${mysql_root_password}
SEAFILE_MYSQL_DB_PASSWORD=${mysql_user_password}
JWT_PRIVATE_KEY=${jwt_private_key}
INIT_SEAFILE_ADMIN_EMAIL=admin@home.arpa
INIT_SEAFILE_ADMIN_PASSWORD=${admin_password}
EOF

sudo install -m 0400 -o root -g root "${tmp}" "${target}"
rm -f "${tmp}"

echo "Created ${target}"
echo "Initial Seafile admin email: admin@home.arpa"
echo "Initial Seafile admin password: ${admin_password}"
