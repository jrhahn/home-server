# Home Server

NixOS configuration for a family server on an Intel J4105-class machine.

For hardware assumptions, workload boundaries, and future service decisions,
start with [docs/server-context.md](docs/server-context.md).

For a fresh machine setup, follow [INSTALLATION.md](INSTALLATION.md).

This setup uses NixOS services and a small Podman-based Seafile stack for:

- AdGuard Home (LAN and tailnet DNS)
- Seafile
- Forgejo
- Home Assistant
- Immich
- Paperless-ngx (opt-in)
- Terminus / TRMNL e-paper server (opt-in)
- Mosquitto MQTT broker and an NTP time server for the LAN sensor fleet
- Sensor fleet extras (opt-in): OTA firmware server and QuestDB time-series archive
- CUPS print server for a Brother TD-2020 label printer (opt-in)
- Bulk data on an external disk via bind mounts (opt-in)
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
- Terminus / TRMNL (opt-in, `server.trmnl.enable`): `http://trmnl.home.arpa`
- Sensor history dashboard (opt-in, `server.smarthomeTimeseries.enable`): `http://iot.home.arpa`
- Sensor firmware images (opt-in, `server.firmwareServer.enable`): `http://fw.home.arpa/fw/`

Forgejo Actions is opt-in via `server.forgejo.actions.enable`. Boards on the
server's USB can each get a runner of their own for hardware-in-the-loop jobs
via `server.forgejo.actions.deviceRunners` (see the [Forgejo guide](docs/forgejo-getting-started.md)).
A Claude review bot workflow for Forgejo repos lives in
[docs/forgejo-claude-review.yml](docs/forgejo-claude-review.yml).

The sensor fleet (rs-smarthome-nodes) uses the always-on Mosquitto broker
(`modules/mosquitto.nix`) and LAN time server (`modules/time-server.nix`).
The QuestDB archive service itself comes from the fleet's own NixOS module,
which the private flake imports; this repo only holds its options, backup and
DNS wiring.

The label printer is opt-in via `server.printServer.enable` (pulls in Brother's
unfree driver). Immich originals and Seafile files can move to an external disk
with `server.storage.externalDisk.enable`; the `/srv` paths stay the same.

GitHub Actions runners for private GitHub repositories are opt-in via
`server.githubRunner.enable`; they run jailed in a NixOS container without
access to the LAN, the tailnet or host data ([guide](docs/github-runner.md)).

Getting started:

- [Seafile guide](docs/seafile-getting-started.md)
- [Immich guide](docs/immich-getting-started.md)
- [Google Photos -> Immich migration](docs/immich-google-photos-migration.md)
- [Forgejo guide](docs/forgejo-getting-started.md)
- [GitHub Actions runner](docs/github-runner.md)
- [Paperless-ngx guide](docs/paperless-getting-started.md)
- [TRMNL / Terminus guide](docs/trmnl-getting-started.md)
- [Upgrade runbook](docs/upgrade-runbook.md)
- [Tailscale DNS cutover](docs/tailscale-dns-cutover.md) (one-time migration for older tailnets)

The Liquid templates driving the panel describe one particular home — its
rooms and its radar location — so they live with that deployment's private
configuration, not here. The guide above covers the generic setup.

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
HA_IMPORT_DIR=<your-private-config>/ha-import/homeassistant \
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
custom `localtuya` integration comes from nixpkgs
(`home-assistant-custom-components.localtuya`, the maintained
xZetsubou/hass-localtuya fork) and is declared in the module, not copied.

This is Home Assistant Core on NixOS, not Home Assistant OS. That means no
Supervisor add-ons. Your Pi also had Mosquitto, Zigbee2MQTT, Node-RED, and
Pi-hole directories; those configs are in the `ha-import/` snapshot, but only
Mosquitto has a NixOS replacement here (`modules/mosquitto.nix`, written fresh,
not imported). DNS filtering is AdGuard Home instead of Pi-hole.

## Backups

Local Borg backups are configured in [modules/maintenance.nix](modules/maintenance.nix).

- `home-assistant-local`: stops Home Assistant briefly and backs up
  `/srv/home-assistant` at 03:45.
- `family-local`: dumps the Seafile MariaDB databases and Immich PostgreSQL
  database (`dump-family-service-databases`, 03:15, kept 14 days), then backs
  up the DB dumps, `/var/lib/secrets`, `/srv/forgejo`, `/srv/seafile`,
  `/srv/seafile-mysql`, `/srv/seafile-redis`, `/srv/immich`, and
  `/srv/immich-originals` at 04:00, minus files written around the clock
  (Seafile's Redis AOF and logs, Forgejo's job queue). Opt-in services ride
  along when enabled:
  - Paperless: PostgreSQL dump plus `/srv/paperless` (minus logs).
  - Terminus: PostgreSQL dump plus `/srv/trmnl` (minus the live database
    directory).
  - Sensor archive: the QuestDB data directory, copied under a checkpoint
    instead of a dump.
  - ai-trainer (`server.backups.aiTrainer`): its encrypted artefacts, pulled
    from its own host so that host holds no Storage Box credentials.
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
setup steps. The remote jobs run at 04:15 (Home Assistant) and 04:30 (family).
`server.backups.notify` emails a summary after each remote job, or only on
failure with `onSuccess = false`.

This server is intended for local network and Tailscale access only. Public
HTTPS is disabled through `server.enablePublicTls = false`; do not expose it
through the router.

## Notes

NixOS rollback protects the host configuration. It does not automatically roll
back Seafile or Immich database migrations. Always take a database dump and a
data backup before major upgrades.
