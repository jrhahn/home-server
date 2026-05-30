#!/usr/bin/env bash
#
# Generate a Forgejo Actions runner registration token and write it as the
# EnvironmentFile the act_runner service expects (server.forgejo.actions).
#
# The file contains a single `TOKEN=<token>` line. The runner registers itself
# on first start; rerun this only to rotate the token (then restart the runner).
set -euo pipefail

target="/var/lib/secrets/forgejo-runner-token"
work_path="/srv/forgejo"
config="${work_path}/custom/conf/app.ini"

token="$(sudo -u forgejo forgejo \
  --config "${config}" \
  --work-path "${work_path}" \
  actions generate-runner-token)"

if [[ -z "${token}" ]]; then
  echo "Failed to generate a runner token." >&2
  exit 1
fi

sudo install -d -m 0750 -o root -g root /var/lib/secrets
printf 'TOKEN=%s\n' "${token}" | sudo install -m 0600 -o root -g root /dev/stdin "${target}"

echo "Wrote ${target}"
echo "Now: sudo nixos-rebuild switch ...  (or: sudo systemctl restart gitea-runner-default)"
