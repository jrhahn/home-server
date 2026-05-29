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

The `nixosConfigurations.family-server` defined in this repo is built from the
placeholder values in [example/](example) — it is for `nix flake check` and as a
reference only. Do not deploy it directly; deploy your private flake.

## First Install

1. Install NixOS 25.11 on the server.
2. Create your private config from the template (a directory or its own repo):

   ```bash
   mkdir ~/home-server-private && cd ~/home-server-private
   cp /path/to/home-server/example/flake.nix .
   cp /path/to/home-server/example/local.nix .
   sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix
   ```

3. Edit `flake.nix` to point `home-server.url` at this repo, then edit
   `local.nix` and set at least:

   - `server.tailscaleAddress`
   - `server.adminSshKeys`
   - `server.backups.hetzner` (if using a Storage Box)
   - any domain / `enablePublicTls` overrides (defaults are `*.home.arpa`,
     private-only)

4. Create Seafile secrets (script lives in this repo; run it from a checkout on
   the server):

   ```bash
   ./scripts/create-seafile-secrets.sh
   ```

5. Build and switch from your **private** flake:

   ```bash
   sudo nixos-rebuild switch --flake ~/home-server-private#family-server
   ```

6. Initialize the local Borg repo once:

   ```bash
   sudo borg init --encryption=none /srv/backups/borg-local
   ```

## Services

Default local hostnames:

- AdGuard Home: `http://adguard.home.arpa`
- Seafile: `http://cloud.home.arpa`
- Forgejo: `http://git.home.arpa`
- Home Assistant: `http://ha.home.arpa`
- Immich: `http://photos.home.arpa`

Getting started:

- [Seafile guide](docs/seafile-getting-started.md)
- [Immich guide](docs/immich-getting-started.md)

Forgejo registration is disabled. After the first switch, create the initial
admin account on the server:

```bash
sudo -u forgejo forgejo --config /srv/forgejo/custom/conf/app.ini --work-path /srv/forgejo admin user create --admin --username admin --email admin@example.invalid --password 'change-me'
```

## Home Assistant Migration

The safe parts of the Pi config are tracked in
[home-assistant/config](home-assistant/config). The private state has been copied
into `.ha-import/homeassistant/`, which is ignored by git because it contains
Home Assistant storage, auth data, Zigbee state, and secrets.

After installing NixOS on the new server, copy it into the service config dir:

```bash
./scripts/import-home-assistant-config.sh
```

The import intentionally excludes Home Assistant logs, caches, and
`home-assistant_v2.db*`. Keep the Pi powered off or Home Assistant stopped
during the final migration if you want to avoid changes happening on both
systems at once.

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
