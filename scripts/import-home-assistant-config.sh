#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tracked_source_dir="${repo_root}/home-assistant/config/"
# The private Pi snapshot now lives in the private repo. Override with
# HA_IMPORT_DIR, e.g. HA_IMPORT_DIR=~/repositories/home-server-private/ha-import/homeassistant
private_source_dir="${HA_IMPORT_DIR:-${repo_root}/.ha-import/homeassistant}"
private_source_dir="${private_source_dir%/}/"
target_dir="/srv/home-assistant/"

if [[ ! -d "${tracked_source_dir}" ]]; then
  echo "Missing ${tracked_source_dir}" >&2
  exit 1
fi

sudo systemctl stop home-assistant.service 2>/dev/null || true
sudo install -d -m 0750 -o hass -g hass "${target_dir}"
sudo rsync -a --delete "${tracked_source_dir}" "${target_dir}"

if [[ -d "${private_source_dir}" ]]; then
  sudo rsync -a "${private_source_dir}" "${target_dir}"
else
  echo "No private Pi import found at ${private_source_dir}; imported tracked config only." >&2
fi

sudo chown -R hass:hass "${target_dir}"
sudo systemctl start home-assistant.service

echo "Imported Home Assistant config into ${target_dir}"
