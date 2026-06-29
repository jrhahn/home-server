# Home Server

NixOS configuration for a family server on an Intel J4105-class machine.

For hardware assumptions, workload boundaries, and future service decisions,
start with [docs/server-context.md](docs/server-context.md).

For a fresh machine setup, follow [INSTALLATION.md](INSTALLATION.md).

This setup uses NixOS services and a small Podman-based Seafile stack for:

- Seafile
- Forgejo
- Home Assistant
- Immich
- Paperless-ngx (opt-in)
- PostgreSQL, MariaDB, and Redis dependencies
- nginx reverse proxy
- database dumps and local Borg backups

Podman is enabled for Seafile because NixOS 25.11 removed the old native
`services.seafile` module, and for future services without a good NixOS module.

## Layout: shareable repo + private instance

This repo is the **shareable** half. It contains only reusable NixOS modules,
exposed as `nixosModules.default`, with no credentials or machine-specific
values. All per-deployment values are declared as `server.*` options in
[modules/options.nix](modules/options.nix).

Your **private** half is a separate flake that imports this one and supplies the
personal bits: a `local.nix` (Tailscale IP, SSH keys, Storage Box coordinates)
and a `hardware-configuration.nix`. Because you never edit the shared repo
locally, there are no untracked files and no merge conflicts here — you pull
improvements with `nix flake update`. A ready-to-copy template lives in
[example/](example). Actual secrets (private keys, passphrases, DB passwords)
never live in either repo; they stay in `/var/lib/secrets` on the server.

The `nixosConfigurations.example` defined in this repo is built from the
placeholder values in [example/](example) — it is for `nix flake check` and as a
reference only. It is named `example` (not `family-server`) and refuses to
activate, so it cannot be accidentally deployed onto the real host. Do not
deploy it directly; deploy your private flake.

## First Install

[INSTALLATION.md](INSTALLATION.md) is the full walkthrough: install NixOS,
create your private config from the [example/](example) template, generate
secrets, run the first `nixos-rebuild switch`, and initialize backups.

The key values to set in your private `local.nix` are `server.tailscaleAddress`,
`server.adminSshKeys`, optional domain / `enablePublicTls` overrides (defaults
are `*.home.arpa`, private-only), and `server.backups.hetzner` if you use a
Storage Box.

## Services

Default local hostnames:

- AdGuard Home: `http://adguard.home.arpa`
- Seafile: `http://cloud.home.arpa`
- Forgejo: `http://git.home.arpa`
- Home Assistant: `http://ha.home.arpa`
- Immich: `http://photos.home.arpa`
- Paperless-ngx (opt-in, `server.paperless.enable`): `http://paperless.home.arpa`

Forgejo Actions is opt-in via `server.forgejo.actions.enable`.

Getting started:

- [Seafile guide](docs/seafile-getting-started.md)
- [Immich guide](docs/immich-getting-started.md)
- [Google Photos -> Immich migration](docs/immich-google-photos-migration.md)
- [Forgejo guide](docs/forgejo-getting-started.md)
- [Paperless-ngx guide](docs/paperless-getting-started.md)

Forgejo registration is disabled. After the first switch, create the initial
admin account on the server:

```bash
sudo -u forgejo forgejo --config /srv/forgejo/custom/conf/app.ini --work-path /srv/forgejo admin user create --admin --username admin --email admin@example.invalid --password 'change-me'
```

## Home Assistant Migration

The safe parts of the Pi config are tracked in
[home-assistant/config](home-assistant/config). The full Pi state (Home
Assistant storage, auth data, Zigbee state, and secrets) lives in the **private**
repo at `ha-import/homeassistant/` — keep it out of any public repo.

After installing NixOS on the new server, import it into the service config dir,
pointing `HA_IMPORT_DIR` at the snapshot in your private checkout:

```bash
HA_IMPORT_DIR=~/home-server-private/ha-import/homeassistant \
  ./scripts/import-home-assistant-config.sh
```

This is a one-time migration: afterwards `/srv/home-assistant` is the live source
of truth and is covered by the Borg backups. The import intentionally excludes
Home Assistant logs, caches, and `home-assistant_v2.db*` (you start with fresh
history). It stops Home Assistant first, so keep the Pi powered off during the
final cutover to avoid changes on both systems at once.

Zigbee (ZHA) pairings in `zigbee.db` only survive if you physically move the
**same Zigbee USB coordinator** from the Pi to the server.

The NixOS Home Assistant module includes the built-in integrations listed in
the Pi's `.storage/core.config_entries`: ZHA, Tuya, TP-Link, Denon/HEOS, mobile
app, Met, Radio Browser, Shopping List, Bluetooth, and related defaults. The
custom `localtuya` integration is copied as part of `custom_components/`.

This is Home Assistant Core on NixOS, not Home Assistant OS. That means no
Supervisor add-ons. Your Pi also had Mosquitto, Zigbee2MQTT, Node-RED, and
Pi-hole directories; those configs are copied into `.ha-import/`, but they are
not yet enabled as NixOS services.

## Backups

Local Borg backups are configured in [modules/maintenance.nix](modules/maintenance.nix).

- `home-assistant-local`: stops Home Assistant briefly and backs up
  `/srv/home-assistant` at 03:45.
- `family-local`: dumps the Seafile MariaDB databases and Immich PostgreSQL
  database, then backs up the DB dumps, `/var/lib/secrets`, `/srv/forgejo`,
  `/srv/seafile`,
  `/srv/seafile-mysql`,
  `/srv/seafile-redis`, `/srv/immich`, and `/srv/immich-originals` at 04:00.
  Forgejo also writes its own dump under `/srv/forgejo/dump` at 03:30.

Initialize the local repo once:

```bash
sudo borg init --encryption=none /srv/backups/borg-local
```

This protects against local app mistakes, but not disk loss. Add a second Borg
or restic target to an external disk or offsite location before trusting the box
with family photos.

Remote Borg backups to a Hetzner Storage Box can be enabled with the
`server.backups.hetzner` settings in your private `local.nix`. See
[Hetzner Storage Box backups](docs/hetzner-storage-box-backups.md) for the
setup steps.

This server is intended for local network and Tailscale access only. Public
HTTPS is disabled through `server.enablePublicTls = false`; do not expose it
through the router.

## Notes

NixOS rollback protects the host configuration. It does not automatically roll
back Seafile or Immich database migrations. Always take a database dump and a
data backup before major upgrades.
