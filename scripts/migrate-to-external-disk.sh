#!/usr/bin/env bash
#
# One-time migration of bulk data onto an external disk for use with
# server.storage.externalDisk (see modules/external-storage.nix).
#
# It copies each dataset onto the external disk, then renames the original
# /srv directory to <dir>.pre-external so the disk space stays reclaimable and
# the bind-mount target is clean. Nothing is deleted: roll back by reversing
# the rename. After this runs, set server.storage.externalDisk in your private
# local.nix and `nixos-rebuild switch` to activate the bind mounts.
#
# Usage:
#   sudo ./migrate-to-external-disk.sh /dev/disk/by-uuid/<UUID> [MOUNTPOINT] [DATASET ...]
#
# Defaults: MOUNTPOINT=/srv/external, datasets are
#   /srv/immich-originals /srv/seafile
set -euo pipefail

device="${1:-}"
mountpoint="${2:-/srv/external}"
shift || true
shift || true
datasets=("$@")
if [[ ${#datasets[@]} -eq 0 ]]; then
  datasets=(/srv/immich-originals /srv/seafile)
fi

if [[ -z "${device}" ]]; then
  echo "usage: sudo $0 /dev/disk/by-uuid/<UUID> [MOUNTPOINT] [DATASET ...]" >&2
  exit 1
fi
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi
if [[ ! -b "${device}" ]]; then
  echo "Not a block device: ${device}" >&2
  exit 1
fi

echo "Device:     ${device}"
echo "Mount point:${mountpoint}"
echo "Datasets:   ${datasets[*]}"
echo
read -r -p "Stop Immich/Seafile, copy data to the external disk, and rename originals to .pre-external? [y/N] " ans
[[ "${ans}" == "y" || "${ans}" == "Y" ]] || { echo "Aborted."; exit 1; }

echo "==> Stopping services that hold these paths open"
systemctl stop immich-server.service immich-machine-learning.service 2>/dev/null || true
systemctl stop podman-seafile.service podman-seafile-mysql.service podman-seafile-redis.service 2>/dev/null || true

echo "==> Mounting ${device} at ${mountpoint}"
mkdir -p "${mountpoint}"
if ! mountpoint -q "${mountpoint}"; then
  mount "${device}" "${mountpoint}"
fi

for src in "${datasets[@]}"; do
  base="$(basename "${src}")"
  dst="${mountpoint}/${base}"
  if [[ ! -d "${src}" ]]; then
    echo "==> Skipping ${src} (not a directory)"
    continue
  fi
  echo "==> Copying ${src}/ -> ${dst}/"
  mkdir -p "${dst}"
  rsync -aHAX --numeric-ids --info=progress2 "${src}/" "${dst}/"
done

echo "==> Verifying sizes"
for src in "${datasets[@]}"; do
  base="$(basename "${src}")"
  [[ -d "${src}" ]] || continue
  printf '  %-28s source=%s  external=%s\n' "${base}" \
    "$(du -sh "${src}" 2>/dev/null | cut -f1)" \
    "$(du -sh "${mountpoint}/${base}" 2>/dev/null | cut -f1)"
done

echo "==> Renaming originals to .pre-external (rollback copies, kept on the internal disk)"
for src in "${datasets[@]}"; do
  [[ -d "${src}" ]] || continue
  if [[ -e "${src}.pre-external" ]]; then
    echo "  ${src}.pre-external already exists; leaving ${src} in place." >&2
    continue
  fi
  mv "${src}" "${src}.pre-external"
done

echo "==> Unmounting ${mountpoint} (NixOS will remount it via fileSystems)"
umount "${mountpoint}" || true

cat <<EOF

Done. Next steps:
  1. In your PRIVATE local.nix, set:
       server.storage.externalDisk = {
         enable = true;
         device = "${device}";
         fsType = "ext4";   # adjust if not ext4
       };
  2. sudo nixos-rebuild switch --flake <your-private-flake>#<host>
  3. Verify the mounts:
       findmnt ${mountpoint}
       findmnt ${datasets[0]}
  4. Start services if needed and confirm Immich/Seafile see their data.
  5. Once happy, reclaim space by deleting the rollback copies:
       sudo rm -rf ${datasets[*]/%/.pre-external}
EOF
