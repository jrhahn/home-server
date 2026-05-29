#!/usr/bin/env bash
set -euo pipefail

target_dir="/var/lib/secrets"
key_file="${target_dir}/borg-hetzner-ed25519"
passphrase_file="${target_dir}/borg-hetzner-passphrase"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

sudo install -d -m 0750 -o root -g root "${target_dir}"

if ! sudo test -f "${key_file}"; then
  ssh-keygen -t ed25519 -N "" -C "borg-hetzner@$(hostname)" -f "${tmp_dir}/borg-hetzner-ed25519"
  sudo install -m 0600 -o root -g root "${tmp_dir}/borg-hetzner-ed25519" "${key_file}"
  sudo install -m 0644 -o root -g root "${tmp_dir}/borg-hetzner-ed25519.pub" "${key_file}.pub"
fi

if ! sudo test -f "${passphrase_file}"; then
  openssl rand -base64 48 > "${tmp_dir}/borg-hetzner-passphrase"
  sudo install -m 0600 -o root -g root "${tmp_dir}/borg-hetzner-passphrase" "${passphrase_file}"
fi

echo "Created or kept:"
echo "  ${key_file}"
echo "  ${key_file}.pub"
echo "  ${passphrase_file}"
echo
echo "Add this public key to the Storage Box authorized_keys file:"
sudo cat "${key_file}.pub"
