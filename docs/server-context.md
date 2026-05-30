# Server Context

This repository targets a small family home server.

## Intended Hardware

- CPU: Intel Celeron J4105-class x86_64 system
- RAM: 8 GB
- Network: wired Ethernet preferred
- Current Home Assistant source system: Raspberry Pi 4, reachable as
  `admin@home-assistant.local`
- Target OS: NixOS stable via this flake

The machine is modest. Prefer boring, low-maintenance services and avoid adding
heavy workloads that assume a modern desktop CPU or lots of RAM.

## Primary Workloads

- Home Assistant Core on NixOS
- Seafile for family file sync and sharing
- Forgejo for private Git hosting
- Immich for family photo/video backup and browsing
- nginx reverse proxy
- Tailscale for private remote access
- PostgreSQL, MariaDB, and Redis where required by services
- Borg backups
- Podman for Seafile and as an escape hatch for services without a good NixOS module

## Design Principles

- Prefer native NixOS modules when they are mature enough.
- Keep state under `/srv`.
- Keep secrets and live application state out of git unless encrypted first.
- Treat NixOS rollback as host rollback, not application database rollback.
- Take app/data backups before major Seafile, Immich, or Home Assistant
  upgrades.
- Prefer services that can run comfortably on 8 GB RAM.
- Avoid running duplicate stacks for the same purpose.

## Current Service Paths

- Home Assistant: `/srv/home-assistant`
- Seafile: `/srv/seafile`
- Seafile MariaDB: `/srv/seafile-mysql`
- Seafile Redis: `/srv/seafile-redis`
- Forgejo: `/srv/forgejo`
- Immich generated data/cache: `/srv/immich`
- Immich originals: `/srv/immich-originals` (bind target; on external disk when `server.storage.externalDisk` is enabled)
- Database dumps: `/srv/backups/database-dumps`
- Local Borg repo: `/srv/backups/borg-local`

## Local Domains

- AdGuard Home: `adguard.home.arpa`
- Home Assistant: `ha.home.arpa`
- Seafile: `cloud.home.arpa`
- Forgejo: `git.home.arpa`
- Immich: `photos.home.arpa`

These are local-use names. The server is intended for local network and
Tailscale access only, with no public HTTPS exposure.

## Capacity Notes

The J4105 and 8 GB RAM are enough for the planned home workloads, but with
limits:

- Immich machine-learning jobs may be slow.
- Avoid multiple heavy indexers/transcoders running at the same time.
- Prefer scheduled maintenance windows for backups and upgrades.
- Use SSD storage for OS, databases, and application state.
- Use a larger SSD/HDD for photos and files.

## External Disk for Bulk Data

`server.storage.externalDisk` relocates bulk, append-mostly, already-backed-up
data onto a separate disk while keeping OS, databases, caches, and the local
Borg repo on the internal disk. This matches the failure profile of an
externally-attached disk: fine for large recoverable media, poor for
fsync-heavy databases and anything whose corruption breaks a service.

- Relocated by default: `/srv/immich-originals` and `/srv/seafile`.
- Deliberately NOT relocated: the OS, Postgres, Seafile MariaDB/Redis
  (`/srv/seafile-mysql`, `/srv/seafile-redis`), Immich caches (`/srv/immich`),
  and the local Borg repo (`/srv/backups/borg-local`) — keeping source data and
  its local backup on different disks.
- Mechanism: the external disk mounts at `server.storage.externalDisk.mountPoint`
  (default `/srv/external`), and each dataset is bind-mounted from
  `<mountPoint>/<basename>`. Service `/srv` paths are unchanged, so the modules
  and the Borg `paths` in `modules/maintenance.nix` need no edits.
- All mounts use `nofail`, so a missing/late external disk does not block boot.
- The device UUID is machine-specific: set `server.storage.externalDisk.device`
  in the PRIVATE `local.nix`, never in the shared repo.
- One-time data move: `scripts/migrate-to-external-disk.sh`.

## Home Assistant Migration

The Pi Home Assistant config has been copied locally into `.ha-import/`.

Safe, reviewable config is tracked under:

- `home-assistant/config`

Private migration state remains ignored:

- `.storage/`
- `secrets.yaml`
- `zigbee.db`
- recorder databases and logs

Use `scripts/import-home-assistant-config.sh` on the target server to install
the tracked config and overlay the private migration state when present.

## Adding New Services

Before adding a new service, check:

1. Does NixOS already have a mature module for it?
2. How much RAM and idle CPU does it need?
3. Where will its persistent state live under `/srv`?
4. How is it backed up and restored?
5. Does it duplicate Seafile, Immich, or Home Assistant functionality?
6. Can it live behind Tailscale/local DNS?

If the answer is unclear, start with a small isolated service and document the
rollback path before making it part of the always-on system.
