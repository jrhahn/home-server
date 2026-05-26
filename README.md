# Home Server

NixOS configuration for a family server on an Intel J4105-class machine.

This setup uses native NixOS services for:

- Nextcloud
- Home Assistant
- Immich
- PostgreSQL and Redis as managed dependencies
- nginx reverse proxy
- database dumps and local Borg backups

Docker is enabled only as an escape hatch for future services without a good
NixOS module.

## First Install

1. Install NixOS 25.11 on the server.
2. Copy the generated hardware config into this repo:

   ```bash
   sudo nixos-generate-config --show-hardware-config > hosts/family-server/hardware-configuration.nix
   ```

3. Edit [hosts/family-server/default.nix](hosts/family-server/default.nix) and set:

   - `cloudDomain`
   - `homeAssistantDomain`
   - `photosDomain`
   - `enablePublicTls`
   - the SSH public key for `admin`

4. Create the Nextcloud admin password:

   ```bash
   sudo install -d -m 0750 -o root -g root /var/lib/secrets
   sudo sh -c 'openssl rand -base64 32 > /var/lib/secrets/nextcloud-admin-pass'
   sudo chmod 0400 /var/lib/secrets/nextcloud-admin-pass
   ```

5. Build and switch:

   ```bash
   sudo nixos-rebuild switch --flake .#family-server
   ```

6. Initialize the local Borg repo once:

   ```bash
   sudo borg init --encryption=none /srv/backups/borg-local
   ```

## Services

Default local hostnames:

- Nextcloud: `http://cloud.home.arpa`
- Home Assistant: `http://ha.home.arpa`
- Immich: `http://photos.home.arpa`

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
- `family-local`: dumps Nextcloud and Immich PostgreSQL databases, then backs
  up the DB dumps plus `/srv/nextcloud` and `/srv/immich` at 04:00.

Initialize the local repo once:

```bash
sudo borg init --encryption=none /srv/backups/borg-local
```

This protects against local app mistakes, but not disk loss. Add a second Borg
or restic target to an external disk or offsite location before trusting the box
with family photos.

For public HTTPS, point real DNS names at the server, update the two domain
values, set `enablePublicTls = true`, and replace the ACME email in
[modules/base.nix](modules/base.nix).

## Notes

NixOS rollback protects the host configuration. It does not automatically roll
back Nextcloud or Immich database migrations. Always take a database dump and a
data backup before major upgrades.
